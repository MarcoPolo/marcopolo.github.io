+++
title = "Building a simple and fast Datalog engine in JavaScript"
draft = true
[taxonomies]
tags = ["JavaScript", "Datalog"]
+++

Datalog is a declarative logic language that can be used to query data. Think
SQL, but simpler and smaller. Even though the syntax is simple, it is still
very powerful. It's used in the [Datomic] database, [Datascript], and as part
of [Polonius] – Rust's borrow checker.

In this post we'll go through the steps to build our own Datalog engine in JavaScript. We'll take some care to make it fast, but we won't do any fine tuning. Specifically, we'll be building the part executes a datalog rule through repeated joins. We won't be building the query compiler, which is the part that turns a datalog program into runnable code (maybe in another post!). That means you'll have to do some mental translation and eye-squinting to turn your datalog rules into something this engine can understand. 

This post is **heavily** inspired by Frank McSherry's post on [Datafrog]. It's basically a copy-paste, I highly recommended checking it out, and reading the section on [Worst Case Optimal Joins](https://github.com/frankmcsherry/blog/blob/master/posts/2018-05-19.md#addendum-2018-05-21-treefrog-leapjoin)

## Datalog Syntax

It's syntax is often implementation specific, but looks roughly like this:
```datalog
grandParentOf(gp, child) <- parentOf(gp, p) and parentOf(p, child).
```
This says that if someone (`gp`) is the parent of `p` and that `p` is also the parent of `child`, then that `gp` is the grandparent of `child`. 

`parentOf` represents a *Relation*. It tells us that someone, `p`, is related to (as in parent of) `child`. 

As Another example, here's the classic "Socrates is man and all men are mortal, therefore Socrates is mortal".

```datalog
// The rule: "All men are mortal"
mortal(m) <- man(m).

// We state that socrates is a man
man("socrates")

// We query if socrates is mortal
?- mortal("socrates").
// -> [mortal("socrates")]. // If this were false then we would get an empty output list.
```

Relatively straightforward syntax.

# A simple rule

We won't be parsing datalog syntax, but we'll still want a rule that we can use an example, and to demonstrate the engine along the way. This rule will be our friend for the journey:
```datalog
nodes(y) <- nodes(x), edges(x,y) // Comma represents a logical AND
```

This rule says that a new node can be added to the `nodes` relation if we have an edge connecting the existing node, `x`, to a new node, `y`. The edge is represented by the `edges` relation. This is a simple and useful rule that has a lot of real world applications. For example, it can answer the question of "how far can I get if I only take trains?" (`trainStation(y) <- trainStation(x), trainGoesTo(x, y)`) or "Am I connected to Google?" (`server("me"). server(y) <- server(x), connectedTo(x, y). ?- server("google").`).

The heart of this rule is a join on the `nodes` relation and the `edges` relation. We join on a common `x` field. When we find a match we add it back to our `nodes` relation. A naive solution to this problem would look something like this:

<pre id="embed-js" class="embed">
const _ = require('lodash')
// A naiveJoin implementation
function naiveJoin(nodes, edges) {
  let lastNodes = []
  while (lastNodes.length != nodes.length) {
    lastNodes = nodes
    let matchedNodes = nodes.reduce((matchedNodes, [node, _]) => {
      let newNodes = edges.filter(([fromNode, toNode]) => fromNode === node)
      // Match the shape of [node, node]
      newNodes = newNodes.map(([_, toNode]) => [toNode, toNode])
      matchedNodes.push(...newNodes)
      return matchedNodes
    }, [])
    // Concat our existing nodes with our new found nodes.
    // And remove any duplicates we've found
    nodes = _.uniqWith(matchedNodes.concat(nodes), _.isEqual)
  }

  return nodes
}

const edges = [[1, 2], [2, 3]]
const nodes = [1].map(node => ([node, node])) // map to match shape of edge

naiveJoin(nodes, edges)
// => [[3, 3], [2, 2], [1, 1]]
</pre>

That's fine if you're dealing with very small datasets or you don't mind
running forever. For the rest of us, there are some relatively easy tricks we
can do.

First, we want to look for the node `x` in `edges`, but we don't want to have
to check the whole list. What if we kept `edges` in order so that if we
wanted to find a node with a big number, we could skip a lot of the other
numbers. The keywords "order" and "skip a lot" should bring to mind a binary
search solution. That exactly what we'll do. We'll optimize the join by
simply keeping the things we're joining in some sort of order. This is how
database indices work.

Second, every time we are running the join in the `naiveJoin` we are running the rule through every node we've ever seen. At the beginning the only known node is `1` so we have to join `edges` against `1`, but after the first round we shouldn't have to. We aren't going to get any matches that we haven't already seen. We can fix this by keeping track of 3 sets of nodes. 
- A *stable* set of nodes. Nodes that have already run through the rule, and if run again wouldn't produce new data. 
- A set of *recent* nodes. Nodes that we need to run through the rule and see if we get any new matches.
- A set of *toAdd* nodes. Nodes that we think we may want to add to *recent* but aren't sure if they are novel.


To illustrate the problem of duplicate work, here's an example of our `naiveJoin` repeating the work it already did before:
<pre class="embed">
const _ = require('lodash')
// endPreamble
let timesIveCheckedNode = {}

// A naiveJoin implementation
function naiveJoin(nodes, edges) {
  let lastNodes = []
  while (lastNodes.length != nodes.length) {
    lastNodes = nodes
    let matchedNodes = nodes.reduce((matchedNodes, [node, _]) => {
      timesIveCheckedNode[node] = timesIveCheckedNode[node] ? timesIveCheckedNode[node] + 1 : 1
      let newNodes = edges.filter(([fromNode, toNode]) => fromNode === node)
      // Match the shape of [node, node]
      newNodes = newNodes.map(([_, toNode]) => [toNode, toNode])
      matchedNodes.push(...newNodes)
      return matchedNodes
    }, [])
    // Concat our existing nodes with our new found nodes.
    // And remove any duplicates we've found
    nodes = _.uniqWith(matchedNodes.concat(nodes), _.isEqual)
  }

  return nodes
}

const edges = [[1, 2], [2, 3], [3, 4]]
const nodes = [1].map(node => ([node, node])) // map to match shape of edge

naiveJoin(nodes, edges)
// => [[4, 4], [3, 3], [2, 2], [1, 1]]
console.log("Times I've checked each node:", timesIveCheckedNode)
// Repeats the work for node 1 4 times!
</pre>

Yikes! we repeat a lot of work. Thankfully we can do better with our strategy of keeping a *stable*, *recent*, and *toAdd* set of nodes.

## Optimization 1: Index our Relation

We derived on first principles the idea that we want to sort our Relations so that we can look things up faster. Now we'll implement that idea.

First let's make a JavaScript class for Relation. We'll also add a helper to sortTuples so we can sort the data in our relation.
<pre class="embed">
const _ = require('lodash')

class Relation {
  constructor(fromArray, sortFn) {
    // Keep track of our sortFn in case we need to re-sort later
    this.sortFn = sortFn;

    // First we'll sort our data
    const sorted = fromArray.sort(sortFn)
    // Then we'll remove duplicates
    // Having only unique statements will make things easier
    this.elements = _.uniqWith(sorted, _.isEqual)
  }
}

// Define a way to sort tuples
function sortTuple (a, b){
  if (a.length != b.length) {
    throw new Error("Can't sort different sized tuples. Tuples are not the same length:", a, b)
  }
  for (let index = 0; index < a.length; index++) {
    const elementA = a[index];
    const elementB = b[index];

    if (elementA === elementB) {
      continue
    }

    if (Array.isArray(elementA)) {
      return sortTuple(elementA, elementB)
    }


    if (typeof elementA == "string") {
      return elementA < elementB ? -1 : 1
    }

    return elementA - elementB
  }

  return 0
};

const edges = new Relation([[2, 3], [3, 4], [1, 2]], sortTuple)
// Use the output inspector to see that the relation is sorted
edges
</pre>

Easy enough to index a relation when we create it. But we need one more thing. We want to merge relations too. We'll have to reindex after we merge, but it's roughly the same as above.

<pre class="embed">
const _ = require('lodash')
// Define a way to sort tuples
function sortTuple (a, b){
  if (a.length != b.length) {
    throw new Error("Can't sort different sized tuples. Tuples are not the same length:", a, b)
  }
  for (let index = 0; index < a.length; index++) {
    const elementA = a[index];
    const elementB = b[index];

    if (elementA === elementB) {
      continue
    }

    if (Array.isArray(elementA)) {
      return sortTuple(elementA, elementB)
    }

    if (typeof elementA == "string") {
      return elementA < elementB ? -1 : 1
    }

    return elementA - elementB
  }

  return 0
};
// endPreamble
class Relation {
  constructor(fromArray, sortFn = sortTuple) {
    // Keep track of our sortFn in case we need to re-sort later
    this.sortFn = sortFn;

    // First we'll sort our data
    const sorted = fromArray.sort(sortFn)
    // Then we'll remove duplicates
    // Having only unique statements will make things easier
    this.elements = _.uniqWith(sorted, _.isEqual)
  }

  // We added this helper to help us merge other relations
  merge(otherRelation) {
    if (otherRelation.sortFn !== this.sortFn) {
      throw new Error(
        "Merging a relation that doesn't have the same sortFn!"
      );
    }

    return new Relation(
      this.elements.concat(otherRelation.elements),
      this.sortFn
    );
  }

  get length() {
    return this.elements.length;
  }
}

const edges = new Relation([[2, 3], [3, 4], [1, 2]], sortTuple)
const edges2 = new Relation([[4, 6], [2, 5]], sortTuple)
edges.merge(edges2)
</pre>

Great, we've created an index relation that can be merged with other
relations. Now we need to write the joining code that will take advantage of
the relation being indexed. The rough gist of this is:

- given two sorted relations `relationA` and `relationB`
- keep two indices into the relations, we'll call them `indexA` and `indexB`
- advance each index until we find a key (the first item in the tuple) that matches
  - If we find a match call a given `logicFn` for each match
  - If we don't find a match advance one of the indices

Let's write a helper that takes two relations and a logicFn that will be
called for every match we find:

<pre class="embed" id="joinHelper">
// logicFn takes the form of (key, val1, val2)
// relations should be a sorted set of (K, V) tuples, sorted by key.
// we join on the first item in the tuple.
function joinHelper(relationA, relationB, logicFn) {
  // Keep track of the indices into the relation's elements
  let idxA = 0;
  let idxB = 0;
  while (
    idxA < relationA.elements.length &&
    idxB < relationB.elements.length
  ) {
    // We're joining on the key (the first item in the tuple)
    let elemAKey = relationA.elements[idxA][0];
    let elemBKey = relationB.elements[idxB][0];

    if (elemAKey < elemBKey) {
      // We have to move idxA up to catch to elemB
      idxA = gallop(relationA.elements, ([k]) => k < elemBKey, idxA);
    } else if (elemBKey < elemAKey) {
      // We have to move idxB up to catch to elemA
      idxB = gallop(relationB.elements, ([k]) => k < elemAKey, idxB);
    } else {
      // They're equal. We have our join

      // Figure out the count of matches in each relation
      let matchingCountA = 0
      while (idxA + matchingCountA < relationA.elements.length && relationA.elements[idxA + matchingCountA][0] === elemAKey) {
        matchingCountA++
      }
      let matchingCountB = 0
      while (idxB + matchingCountB < relationB.elements.length && relationB.elements[idxB + matchingCountB][0] === elemAKey) {
        matchingCountB++
      }

      // Call logicFn on the cross product
      for (let i = 0; i < matchingCountA; i++) {
        for (let j = 0; j < matchingCountB; j++) {
          logicFn(
            elemAKey,
            relationA.elements[idxA + i][1],
            relationB.elements[idxB + j][1]
          );
        }
      }

      idxA += matchingCountA;
      idxB += matchingCountB;
    }
  }
}
</pre>

The implementation should be unsurprising except for `gallop`. Roughly, `gallop` is a variant on binary search that finds the first index for which the given function becomes false. For example:

<pre class="embed">
// Finds the first index for which predicate is false. Returns an index of array.length if it will never be true
// predFn takes the form of (tuple) => boolean
function gallop(array, predFn, startIdx = 0) {
  if (array.length - startIdx <= 0 || !predFn(array[startIdx])) {
    return startIdx;
  }

  let step = 1;

  // Step up until we've seen a false result from predFn
  while (startIdx + step < array.length && predFn(array[startIdx + step])) {
    startIdx += step;
    step = step << 1;
  }

  // Now step down until we get a false result
  step = step >> 1;
  while (step > 0) {
    if (startIdx + step < array.length && predFn(array[startIdx + step])) {
      startIdx += step;
    }
    step = step >> 1;
  }

  return startIdx + 1;
}
// endPreamble
const array = [0,1,2,3,4,5]
const index = gallop(array, n => n < 3)
array[index]
</pre>

The implementation of `gallop` is pretty interesting. It starts with an index into the array, by default 0. It then increments the index by some `step`. For every round that the predicate function is true, step will double. This means you exponentially index forward in the array. Once the predicate function is false, we stop advancing the index. Now we want to find the greatest index for which the predicate function is still true. We start halving the step size and adding the step to the index while the predicate function is true. We do this until the predicate function is no longer true, at that point we're done.

<pre class="embed" id="gallop">
// Finds the first index for which predicate is false. Returns an index of array.length if it will never be false
// predFn takes the form of (tuple) => boolean
// startIdx lets you start at some index instead of the start of the array
function gallop(array, predFn, startIdx = 0) {
  if (array.length - startIdx <= 0 || !predFn(array[startIdx])) {
    return startIdx;
  }

  let step = 1;

  // Step up until we've seen a false result from predFn
  while (startIdx + step < array.length && predFn(array[startIdx + step])) {
    startIdx += step;
    step = step << 1;
  }

  // Now step down until we get a false result
  step = step >> 1;
  while (step > 0) {
    if (startIdx + step < array.length && predFn(array[startIdx + step])) {
      startIdx += step;
    }
    step = step >> 1;
  }

  return startIdx + 1;
}
</pre>

We have an indexed `Relation` and our `joinHelper` to join two `Relation`s.
Let's make the `naiveJoin` a little better.

<pre style="display: none;" id="sortTuple">
function sortTuple (a, b){
  if (a.length != b.length) {
    throw new Error("Can't sort different sized tuples. Tuples are not the same length:", a, b)
  }
  for (let index = 0; index < a.length; index++) {
    const elementA = a[index];
    const elementB = b[index];

    if (Array.isArray(elementA)) {
      return sortTuple(elementA, elementB)
    }

    if (elementA === elementB) {
      continue
    }

    if (typeof elementA == "string") {
      return elementA < elementB ? -1 : 1
    }

    return elementA - elementB
  }

  return 0
};
</pre>

<pre class="embed">
// inline#gallop
// inline#joinHelper
const _ = require('lodash')
// Define a way to sort tuples
function sortTuple (a, b){
  if (a.length != b.length) {
    throw new Error("Can't sort different sized tuples. Tuples are not the same length:", a, b)
  }
  for (let index = 0; index < a.length; index++) {
    const elementA = a[index];
    const elementB = b[index];

    if (Array.isArray(elementA)) {
      return sortTuple(elementA, elementB)
    }

    if (elementA === elementB) {
      continue
    }

    if (typeof elementA == "string") {
      return elementA < elementB ? -1 : 1
    }

    return elementA - elementB
  }

  return 0
};
class Relation {
  constructor(fromArray, sortFn = sortTuple) {
    // Keep track of our sortFn in case we need to re-sort later
    this.sortFn = sortFn;

    // First we'll sort our data
    const sorted = fromArray.sort(sortFn)
    // Then we'll remove duplicates
    // Having only unique statements will make things easier
    this.elements = _.uniqWith(sorted, _.isEqual)
  }

  // We added this helper to help us merge other relations
  merge(otherRelation) {
    if (otherRelation.sortFn !== this.sortFn) {
      throw new Error(
        "Merging a relation that doesn't have the same sortFn!"
      );
    }

    return new Relation(
      this.elements.concat(otherRelation.elements),
      this.sortFn
    );
  }

  get length() {
    return this.elements.length;
  }
}
// endPreamble

const edges = new Relation([[2, 3], [3, 4], [1, 2]], sortTuple)
let nodes = new Relation([[1, 1]], sortTuple)

let lastNodes = new Relation([], sortTuple)
while (lastNodes.length != nodes.length) {
  lastNodes = nodes
  const output = []
  joinHelper(nodes, edges, (fromNode, _fromNode, toNode) => output.push([toNode, toNode]))
  nodes = (new Relation(output, sortTuple)).merge(nodes)
}
nodes.elements
</pre>

Better than before. But there's still one more thing we can improve on in our `Relation`. Lodash's `uniqWith` isn't optimized for sorted arrays, and the `sortedUniq` variants don't support a comparator function. So let's write our own faster version that deduplicates items from a sorted array. For my `dedupBy` I copied what Rust does in their dedup_by implementation.

<pre class="embed" id="dedupBy">
// Mutates the input array!
// See https://doc.rust-lang.org/1.40.0/src/core/slice/mod.rs.html#1891 for a
// great explanation of this algorithm.
// Basically we bubble duplicates to the end of the array, then split the array
// to before dupes and after dupes. O(n)
// If the array is sorted, this will remove all duplicates.
// comparatorFn should return true if the items are the same.
function dedupBy(array, comparatorFn) {
  let w = 1
  for (let r = 1; r < array.length; r++) {
    const rElement = array[r];
    const wElementPrev = array[w - 1];
    if (comparatorFn(rElement, wElementPrev)) {
      // The same so we keep `w` where it is
    } else {
      // We need to swap the elements 
      // But only swap if their indices are different (otherwise it's no-op)
      if (r !== w) {
        array[r] = array[w]
        array[w] = rElement
      }
      w++
    }
  }
  array.splice(w)
}
</pre>

That was fun and all, but was it really worth it? Is our version really that
much better than calling an existing library? Fair questions. Let's find out:

<pre class="embed">
// inline#dedupBy
// inline#sortTuple
const _ = require('lodash')
// endPreamble
function createRandomNumbers(n) {
  const randomNumbers = new Array(n)
  randomNumbers.fill(0)
  return randomNumbers.map(() => [Math.floor(Math.random() * 10), Math.floor(Math.random() * 100)])
}

function dedupWithUniq(array, sortFn) {
  console.time("Sort numbers")
  const sorted = array.sort(sortFn)
  console.timeEnd("Sort numbers")

  console.time("Remove Duplicates")
  const deduped = _.uniqWith(sorted, _.isEqual)
  console.timeEnd("Remove Duplicates")
  return deduped
}

function customDedup(array, sortFn) {
  console.time("Sort numbers")
  const sorted = array.sort(sortFn)
  console.timeEnd("Sort numbers")

  console.time("Remove Duplicates")
  dedupBy(sorted, (a, b) => sortFn(a,b) === 0)
  console.timeEnd("Remove Duplicates")
  return sorted
}

// warm up the JIT
const time = console.time
const timeEnd = console.timeEnd
console.time = () => {}
console.timeEnd = () => {}
for (let i = 0; i < 100; i++) {
  const dedupedA = dedupWithUniq(createRandomNumbers(1e2), sortTuple)
  const dedupB = customDedup(createRandomNumbers(1e2), sortTuple)
}

console.time = time
console.timeEnd = timeEnd
console.log("Deduping using _.uniqWith")
let randomNumbers = createRandomNumbers(1e5)
const dedupedA = dedupWithUniq([...randomNumbers], sortTuple)

console.log("Deduping using our version")
const dedupedB = customDedup([...randomNumbers], sortTuple);
_.isEqual(dedupedA, dedupedB)
</pre>

When I ran this on RunKit I got 250x speed improvement by using our custom
version. Not bad. Now we swap our version in the constructor for `Relation`
for our final version of `Relation`:

<pre class="embed" id="Relation">
// inline#sortTuple
// inline#dedupBy
// endPreamble
// Final version of `Relation`
class Relation {
  constructor(fromArray, sortFn = sortTuple) {
    this.sortFn = sortFn;
    const sorted = fromArray.sort(sortFn)
    dedupBy(sorted, (a, b) => sortFn(a, b) === 0)
    this.elements = sorted
  }

  merge(otherRelation) {
    if (otherRelation.sortFn !== this.sortFn) {
      throw new Error(
        "Merging a relation that doesn't have the same sortFn!"
      );
    }

    return new Relation(
      this.elements.concat(otherRelation.elements),
      this.sortFn
    );
  }

  get length() {
    return this.elements.length;
  }
}

</pre>

## Optimization 2: Minimize duplicate work

We saw in the `naiveJoin` how we did a lot of duplicate work. Now we'll fix that. What if we had a kind of relation that could keep track of the tuples which have already been used in a rule (*stable* tuples), which ones haven't (*recent* tuples), and which ones we might want to add (*toAdd* tuples). It would be varying over time, so let's call it a `Variable`. To make things a little easier let's use `Relation`s inside the `Variable` to represent the 3 states. Our `Variable` will look a little something like this:

<pre class="embed">
class Variable {
  constructor() {
    // Already processed tuples.
    this.stable = new Relation([])
    // Recently added but unprocessed tuples.
    this.recent = new Relation([]);
    // Tuples yet to be introduced.
    this.toAdd = new Relation([])
  }
}
</pre>

Hmm, this looks okay. But how about we try to minimize merges when possible? Namely instead of having just one relation in `this.stable` and one relation in `this.toAdd`, let's keep a list of relations. This will prevent us from calling `relation.merge` more often than we need to and loose performance. Let's also add an `insert` method which will add a new relation to `this.toAdd`.

<pre class="embed">
// inline#Relation
// endPreamble
class Variable {
  constructor() {
    // A list of already processed tuples.
    this.stable = []; // Type: Array of Relations
    // Recently added but unprocessed tuples.
    this.recent = new Relation([]);
    // A list of tuples yet to be introduced.
    this.toAdd = []; // Type: Array of Relations
  }

  // When we add a relation to this variable, we'll call insert and that will
  // push it to our toAdd list
  insert(relation) {
    this.toAdd.push(relation);
  }
}
</pre>

Given these 3 fields, we need to figure out how to move relations between them.
This happens at the end of one iteration step of the rule. We can run this logic
when we check to see if the `Variable` has changed (roughly what we did when
we checked if `lastNodes.length !== nodes.length`). The rules for moving
relations after an iteration are:
- If we have relations in `recent`, let's merge those into `stable`. Doing some tricks to find the sweet spot between having many small relations and one giant relation.
- If we have relations in `toAdd`, let's:
  - merge them all down into a single `Relation`.
  - filter out any tuples we already know about in stable. 
  - move the filtered relation into `recent`. 

In code, this lives in the `changed` method of `Variable`. Note how it returns true only if `this.recent` is not empty. Meaning if there are recent relations, then this variable has changed. If run again with a rule, it may produce new tuples.

<pre class="embed">
// inline#Relation
// endPreamble
class Variable {
  constructor() {
    // A list of already processed tuples.
    this.stable = [];
    // Recently added but unprocessed tuples.
    this.recent = new Relation([]);
    // A list of tuples yet to be introduced.
    this.toAdd = [];
  }

  insert(relation) {
    this.toAdd.push(relation);
  }

  changed() {
    // 1. Merge this.recent into this.stable.
    if (this.recent.elements.length > 0) {
    }

    // 2. Move this.toAdd into this.recent.
    if (this.toAdd.length > 0) {
      // 2a. Merge all newly added relations.

      // 2b. Restrict `toAdd` to tuples not in `this.stable`.
    }

    // Return true iff recent is non-empty.
    return !!this.recent.length;
  }
}
</pre>

With the general skeleton of the code out of the way, here's the actual implementation of changed:

<pre class="embed">
class Variable {
// ...
  changed() {
    // 1. Merge this.recent into this.stable.
    if (this.recent.elements.length > 0) {
      let recent = this.recent;
      this.recent = new Relation([], recent.sortFn);

      // Merge smaller stable relations into our recent one. This keeps bigger
      // relations to the left, and smaller relations to the right. merging them
      // over time so not to keep a bunch of small relations.
      while (
        this.stable[this.stable.length - 1] &&
        this.stable[this.stable.length - 1].length <= 2 * recent.elements.length
      ) {
        const last = this.stable.pop();
        recent = last.merge(recent);
      }

      this.stable.push(recent);
    }

    // 2. Move this.toAdd into this.recent.
    if (this.toAdd.length > 0) {
      // 2a. Merge all newly added relations.
      let toAdd = this.toAdd.pop();
      while (this.toAdd.length > 0) {
        toAdd = toAdd.merge(this.toAdd.pop());
      }

      // 2b. Restrict `toAdd` to tuples not in `this.stable`.
      for (let index = 0; index < this.stable.length; index++) {
        const stableRelation = this.stable[index];
        toAdd.elements = toAdd.elements.filter(elem => {
          let searchIdx = gallop(stableRelation.elements, (tuple) => stableRelation.sortFn(tuple, elem) < 0);
          if (searchIdx < stableRelation.elements.length && stableRelation.sortFn(stableRelation.elements[searchIdx], elem) === 0) {
            return false
          }

          return true;
        });
      }
      this.recent = toAdd;
    }

    // Return true iff recent is non-empty.
    return !!this.recent.length;
  }
// ...
}
// Not the full class so this will error if you try to use it.
</pre>

Our Variable has our 3 sets of relations. We know the `stable` won't produce any new rules when joined with a fixed `Relation`. That means we only need to consider `recent` and a fixed `Relation` when applying the rules.

<pre style="display:none" id="Variable">
const _ = require('lodash')
// inline#gallop
// inline#Relation
// inline#joinHelper
// endPreamble

class Variable {
  constructor() {
    // A list of already processed tuples.
    this.stable = [];
    // Recently added but unprocessed tuples.
    this.recent = new Relation([]);
    // A list of tuples yet to be introduced.
    this.toAdd = [];
  }

  insert(relation) {
    this.toAdd.push(relation);
  }

  changed() {
    // 1. Merge this.recent into this.stable.
    if (this.recent.elements.length > 0) {
      let recent = this.recent;
      this.recent = new Relation([], recent.sortFn);

      // Merge smaller stable relations into our recent one. This keeps bigger
      // relations to the left, and smaller relations to the right. merging them
      // over time so not to keep a bunch of small relations.
      while (
        this.stable[this.stable.length - 1] &&
        this.stable[this.stable.length - 1].length <= 2 * recent.elements.length
      ) {
        const last = this.stable.pop();
        recent = last.merge(recent);
      }

      this.stable.push(recent);
    }

    // 2. Move this.toAdd into this.recent.
    if (this.toAdd.length > 0) {
      // 2a. Merge all newly added relations.
      let toAdd = this.toAdd.pop();
      while (this.toAdd.length > 0) {
        toAdd = toAdd.merge(this.toAdd.pop());
      }

      // 2b. Restrict `toAdd` to tuples not in `this.stable`.
      for (let index = 0; index < this.stable.length; index++) {
        const stableRelation = this.stable[index];
        toAdd.elements = toAdd.elements.filter(elem => {
          let searchIdx = gallop(stableRelation.elements, (tuple) => stableRelation.sortFn(tuple, elem) < 0);
          if (searchIdx < stableRelation.elements.length && stableRelation.sortFn(stableRelation.elements[searchIdx], elem) === 0) {
            return false
          }

          return true;
        });
      }
      this.recent = toAdd;
    }

    // Return true iff recent is non-empty.
    return !!this.recent.length;
  }

  joinRelation(relation, logicFn) {
    const results = [];

    // join: this.recent – relation
    joinHelper(this.recent, relation, (k, vA, vB) =>
      results.push(logicFn(k, vA, vB))
    );
    this.insert(new Relation(results));
  }
}
</pre>

<pre class="embed" id="Variable">
const _ = require('lodash')
// inline#gallop
// inline#Relation
// inline#joinHelper
// endPreamble

class Variable {
  constructor() {
    // A list of already processed tuples.
    this.stable = [];
    // Recently added but unprocessed tuples.
    this.recent = new Relation([]);
    // A list of tuples yet to be introduced.
    this.toAdd = [];
  }

  insert(relation) {
    this.toAdd.push(relation);
  }

  changed() {
    // 1. Merge this.recent into this.stable.
    if (this.recent.elements.length > 0) {
      let recent = this.recent;
      this.recent = new Relation([], recent.sortFn);

      // Merge smaller stable relations into our recent one. This keeps bigger
      // relations to the left, and smaller relations to the right. merging them
      // over time so not to keep a bunch of small relations.
      while (
        this.stable[this.stable.length - 1] &&
        this.stable[this.stable.length - 1].length <= 2 * recent.elements.length
      ) {
        const last = this.stable.pop();
        recent = last.merge(recent);
      }

      this.stable.push(recent);
    }

    // 2. Move this.toAdd into this.recent.
    if (this.toAdd.length > 0) {
      // 2a. Merge all newly added relations.
      let toAdd = this.toAdd.pop();
      while (this.toAdd.length > 0) {
        toAdd = toAdd.merge(this.toAdd.pop());
      }

      // 2b. Restrict `toAdd` to tuples not in `this.stable`.
      for (let index = 0; index < this.stable.length; index++) {
        const stableRelation = this.stable[index];
        toAdd.elements = toAdd.elements.filter(elem => {
          let searchIdx = gallop(stableRelation.elements, (tuple) => stableRelation.sortFn(tuple, elem) < 0);
          if (searchIdx < stableRelation.elements.length && stableRelation.sortFn(stableRelation.elements[searchIdx], elem) === 0) {
            return false
          }

          return true;
        });
      }
      this.recent = toAdd;
    }

    // Return true iff recent is non-empty.
    return !!this.recent.length;
  }

  joinRelation(relation, logicFn) {
    const results = [];

    // join: this.recent – relation
    joinHelper(this.recent, relation, (k, vA, vB) =>
      results.push(logicFn(k, vA, vB))
    );
    this.insert(new Relation(results));
  }
}


const edges = new Relation([[1, 2], [2, 3]])
const nodes = new Variable()
nodes.insert(new Relation([[1, 1]]))

while (nodes.changed()) {
  nodes.joinRelation(edges, (fromNode, _fromNode, toNode) => [toNode, toNode])
}
nodes // Inside nodes.stable we see our list of connected nodes!
</pre>

🎉 We've made a pretty fast Datalog engine. Yay! But there's still more we can do. We did a join from a `Variable` and a `Relation`, but what would it look like to join two `Variable`s?

## Addon – join two **Variables**

Joining two variables is a little different than joining a `Variable` and a
`Relation`. They both have a `recent` fields we need to consider. Similar to what we did above, we need to compare each `Variable`'s `recent` field with the other's `stable` field. We also need to compare one `Variable`'s `recent` to the other `Variable`'s `recent` field since these are two Relations that have just been added and haven't been processed by the rule yet.
To summarize, we need to do three things to join two Variables, let call them `VariableA` and `VariableB`:
- Compare `VariableA.recent` with `VariableB.stable`
- Compare `VariableA.stable` with `VariableB.recent`
- Compare `VariableA.recent` with `VariableB.recent`

Let's write a helper that takes two input variables, an output variable, and a `logicFn` that specifies the new tuple to be added given the match:

<pre class="embed">
// inline#Variable
// endPreamble
// logicFn is of the type: (Key, ValA, ValB) => Result
// where Result is the type of data that will live in outputVariable.
// To join these two variables we have to join 3 things.
// inputVariableA.recent – inputVariableB.stable
// inputVariableA.stable – inputVariableB.recent
// inputVariableA.recent – inputVariableB.recent
function joinInto(inputVariableA, inputVariableB, outputVariable, logicFn) {
  const results = [];

  // inputVariableA.recent – inputVariableB.stable
  for (let index = 0; index < inputVariableB.stable.length; index++) {
    const stableRelation = inputVariableB.stable[index];
    joinHelper(inputVariableA.recent, stableRelation, (k, vA, vB) =>
      results.push(logicFn(k, vA, vB))
    );
  }
  // inputVariableA.stable – inputVariableB.recent
  for (let index = 0; index < inputVariableA.stable.length; index++) {
    const stableRelation = inputVariableA.stable[index];
    joinHelper(stableRelation, inputVariableB.recent, (k, vA, vB) =>
      results.push(logicFn(k, vA, vB))
    );
  }

  // inputVariableA.recent – inputVariableB.recent
  joinHelper(inputVariableA.recent, inputVariableB.recent, (k, vA, vB) =>
    results.push(logicFn(k, vA, vB))
  );

  outputVariable.insert(new Relation(results));
}


const edges = new Variable()
edges.insert(new Relation([[1, 2], [2, 3]]))

const nodes = new Variable()
nodes.insert(new Relation([[1, 1]]))

while (nodes.changed() || edges.changed()) {
  joinInto(nodes, edges, nodes, (fromNode, _fromNode, toNode) => [toNode, toNode])
}
nodes // Inside nodes.stable we see our list of connected nodes!
</pre>

<pre style="display: none;" id="joinInto">
// logicFn is of the type: (Key, ValA, ValB) => Result
// where Result is the type of data that will live in outputVariable.
// To join these two variables we have to join 3 things.
// inputVariableA.recent – inputVariableB.stable
// inputVariableA.stable – inputVariableB.recent
// inputVariableA.recent – inputVariableB.recent
function joinInto(inputVariableA, inputVariableB, outputVariable, logicFn) {
  const results = [];

  // inputVariableA.recent – inputVariableB.stable
  for (let index = 0; index < inputVariableB.stable.length; index++) {
    const stableRelation = inputVariableB.stable[index];
    joinHelper(inputVariableA.recent, stableRelation, (k, vA, vB) =>
      results.push(logicFn(k, vA, vB))
    );
  }
  // inputVariableA.stable – inputVariableB.recent
  for (let index = 0; index < inputVariableA.stable.length; index++) {
    const stableRelation = inputVariableA.stable[index];
    joinHelper(stableRelation, inputVariableB.recent, (k, vA, vB) =>
      results.push(logicFn(k, vA, vB))
    );
  }

  // inputVariableA.recent – inputVariableB.recent
  joinHelper(inputVariableA.recent, inputVariableB.recent, (k, vA, vB) =>
    results.push(logicFn(k, vA, vB))
  );

  outputVariable.insert(new Relation(results));
}
</pre>


## Our Datalog engine – in action

We've built our engine, let's use it.

Our grandparent example:

```datalog
grandParentOf(gp, child) <- parentOf(gp, p) and parentOf(p, child).
```

Which is that same as:
```datalog
childOf(child, p) <- parentOf(p, child).
grandParentOf(gp, child) <- childOf(p, gp) and parentOf(p, child).
```
We changed the right hand side to have the same first value so we can join on `p`.

<pre class="embed">
// inline#Variable
// inline#joinInto
// endPreamble
const parentOf = new Variable()
const childOf = new Variable()
const grandParentOf = new Variable()

// Populate initial data
parentOf.insert(new Relation([["bob", "alice"], ["alice", "eve"]]))

while (grandParentOf.changed() || parentOf.changed() || childOf.changed()) {
  // the rule: childOf(child, p) <- parentOf(p, child).
  childOf.insert(new Relation(parentOf.recent.elements.map(([parent, child]) => [child, parent])))

  // the rule: grandParentOf(gp, child) <- childOf(p, gp) and parentOf(p, child).
  joinInto(childOf, parentOf, grandParentOf, (parent, gp, child) => [gp, child])
}


// Query our data. Who is the grandchild of "bob"?
const query = new Variable()
query.insert(new Relation([["bob"]]))

const queryOutput = new Variable()

while (query.changed()) {
  // the rule: queryOuput(child, query) <- grandParentOf(query, child), query("bob")
  joinInto(grandParentOf, query, queryOutput, (gp, child, _) => {
    console.log(`${child} is the grandchild of ${gp}`)
    return [child, gp]
   })
}
queryOutput

</pre>



<!-- <script src="https://embed.tonic.work"></script> -->
<script src="https://embed.runkit.com"></script>
<script>
const enableRK = true
const preambleToken = "// endPreamble\n";
const inlineRE = /\/\/ inline#([\w-]*)\n/g

const inline = (source) => {
  const hasInlines = source.indexOf("// inline") >= 0
  if (hasInlines) {
    (source.match(inlineRE) || []).map(inlineDecl => {
      const inlineId = inlineDecl.split("#")[1].trim()
      let inlineContent = document.getElementById(inlineId).textContent
      // Remove any preambles
      inlineContent = inlineContent.replace(preambleToken, "")
      // Recursively inline
      inlineContent = inline(inlineContent)

      source = source.replace(inlineDecl, inlineContent)
    })
  }
  return source
}

window.notebooks = [...document.getElementsByClassName('embed')].map(element => {
  let preamble = ""
  let source = element.textContent
  const textElement = element.firstChild
  const hasPreamble = source.indexOf(preambleToken) >= 0
  const hasInlines = source.indexOf("// inline") >= 0
  if (hasInlines) {
    source = inline(source)
  }
  if (hasPreamble) {
    [preamble, source] = source.split(preambleToken)
  }
  source = source.trim()
  
  if (enableRK) {
    const notebook = RunKit.createNotebook({
      element,
      preamble,
      source,
      onLoad: () => textElement.remove()
    })
    return notebook
  }
})

</script>

[Datafrog]: https://github.com/frankmcsherry/blog/blob/master/posts/2018-05-19.md
[Datascript]: https://github.com/tonsky/datascript
[Datomic]: https://en.wikipedia.org/wiki/Datomic
[Polonius]: https://github.com/rust-lang/polonius