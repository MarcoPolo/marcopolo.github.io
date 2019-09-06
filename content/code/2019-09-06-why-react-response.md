+++
title = "Interacting with Go from React Native through JSI"
[taxonomies]
tags = ["javascript", "react"]
+++

# Response to [Why React?](https://gist.github.com/sebmarkbage/a5ef436427437a98408672108df01919)

Some quick thoughts I had after reading the [Why React?](https://gist.github.com/sebmarkbage/a5ef436427437a98408672108df01919) gist.

Disclaimer: _I want to be critical with React. I don't disagree that it has done some amazing things_

## "Compiled output results in smaller apps"

> E.g. Svelte apps start smaller but the compiler output is 3-4x larger per component than the equivalent VDOM approach.

This may be true currently, but that doesn't mean it will always be true of compiled-to frameworks. A theoretical compiler can produce a component that uses a shared library for all components. If a user doesn't use all the features of a framework, then a compiler could remove the unused features from the output. Which is something that could not happen with a framework that relies on a full runtime.

Note: I'm not advocating for a compiled-to approach, I just think this point was misleading

## "DOM is stateful/imperative, so we should embrace it"

I agree with OP here. Most use-cases would not benefit from an imperative UI api.

## "React leaks implementation details through useMemo"

A common problem to bite new comers is when they pass a closure to a component, and that closure gets changed every time which causes their component to re-render every time. `useMemo` can fix this issue, but it offloads a bit of work to the developer.

In the above context, it's an implementation detail. I'm not saying it's the wrong or right trade off, I'm only saying that the reason you have to reach for `useMemo` when passing around closures is because of how React is implemented. So the quote is accurate.

Is that a bad thing? That's where it gets more subjective. I think it is, because these types of things happen very often and, in a big app, you quickly succumb to death by a thousand cuts (one closure causing a component to re-render isn't a big deal, but when you have hundreds of components with various closures it gets hairy).

The next example OP posts is about setting users in a list.

```js
setUsers([
  ...users.filter(user => user.name !== "Sebastian"),
  { name: "Sebastian" }
]);
```

If you are happy with that syntax, and the tradeoff of having to use `key` props whenever you display lists, and relying on React's heuristics to efficiently update the views corresponding to the list, then React is fine. If, however, you are okay with a different syntax you may be interested in another idea I've seen. The basic idea is you keep track of the diffs themselves instead of the old version vs. the new version. Knowing the diffs directly let you know exactly how to update the views directly so you don't have to rely on the `key` prop, heuristics, and you can efficiently/quickly update the View list. This is similar to how [Immer](https://github.com/immerjs/immer) works. [Futures Signals](https://docs.rs/futures-signals/0.3.8/futures_signals/tutorial/index.html) also does this to efficiently send updates of a list to consumers (look at `SignalVec`).

## "Stale closures in Hooks are confusing"

I agree with OP's points here. It's important to know where your data is coming from. In the old hook-less style of React, your data was what you got from your props/state and nothing else. With hooks, it's easier to work with stale data that comes in from outside your props. It's a learning curve, but not necessarily bad.

One thing I find interesting is that the use of hooks moves functional components into becoming more stateful components. I think this is fine, but it loses the pure functional guarantees you had before.

I haven't yet made up my mind about hooks that interact with the context. (i.e. `useSelector` or `useDispatch`) since the context is less structured. i.e. This component's selector function for `useSelector` relies on the state being `X`, but `X` isn't passed in, it's set as the store in redux configuration file somewhere else. Now that the component relies on the shape of the store being `X` it makes it harder to move out. This may not actually matter in practice, and it may be much more useful to be able to pull arbitrary things out of your store. Hence why I'm currently undecided about it.
