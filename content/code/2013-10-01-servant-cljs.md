+++
title = "Introducing Servant, a Clojurescript library for web workers"
[taxonomies]
tags = ["javascript", "react-native", "JSI", "Go"]
+++

# Concurrent Programming

Javascript by default is single threaded, but web workers introduce
OS level threads. Concurrent programming is hard enough (in imperative
languages), so the webworker designers decided to circumvent a bunch of
concurrency problems by forbidding any shared data between threads. There are
better ways of doing this (read _immutability_), but we work with what we got.

<br></br>

# Problems with web workers

I've done a couple projects with web workers. The biggest project being
[Cryptic.io](http://cryptic.io), which uses webworkers to efficiently
encrypt/decrypt large (GBs) files, and parallel {down,up}load file chunks. Here
are problems I've stumbled across:

- Everything about the web worker needs to be asynchronous, meaning callback hell
- You need to think in a separate context for the web worker, you can't call any functions defined with the rest of your code.
- Distributing workload effectively.
- The problems only gets worse the more web workers you bring in.

<br />

# Enter Servant

[Servant](https://github.com/marcopolo/servant) is a super small (literally ~100 lines) library that solves all the
problems above, allowing you to write clean, multithreaded, ClojureScript. Even
though it's small, it does a lot.

- It allows you to define servant functions alongside the rest of your code, even using functions already defined in your
  namespace.
- It automatically balances work across webworkers.
- It provides simple ways to do a normal (copy of arguments) or efficient (arraybuffer transfer) call
  to webworkers, easily.

# Sharing functions, and predefined variables

This was the trickiest part of the library. I wanted the ability to define
useful functions, and use them in the webworker without having to copy it over
to a separate worker.js file. I solved it by using the same exact file for both
the main page (browser context) and the web worker. That, however, came with one
problem; you have to explicitly declare code that should run on the webworker
and code that runs in the browser. Like so:

```clojure
(ns servant.demo
  (:require [servant.core :as servant]
            [servant.worker :as worker]))

(defn window-load [] (.log js/console "this runs in the browser"))

(if (servant/webworker?)
    (worker/bootstrap) ;;Sets the worker up to receive messages
    (set! (.-onload js/window) window-load))
```

As part of that caveat, the webworker can only see code that it can get to.
Anything defined in window-load would not be visible to the webworker. Now let's
take a look at how we can define a servant function, using the `defservantfn`
macro.

We need to use a special function, `defservantfn` to define functions that will
serve as our "access points" to the web worker.

```clojure
(ns servant.demo
  (:require-macros [servant.macros :refer [defservantfn]]))

(defn make-it-funny [not-funny]
  (str "Hahahah:" not-funny))

(defservantfn servant-with-humor [your-joke]
    (make-it-funny your-joke))
```

The `defservantfn` macro simply calls a defn with the
same arguments, and registers that function with a hashmap atom for the
webworker. The key is the hash of the function and the value is the function
itself. The webworker needs to be able to know what function the browser is
referring in a message, so I use the function's hash as a token that
the browser context and webworker can both agree on. The function's
`.toString()` value could have worked just as well.

I should also mention, for efficiency reasons, Servant keeps a pool of N
webworkers (you specify N) alive (until you explicitly kill them) so you only
pay for the webworkers once. You control when the webworkers are created with
`servant/spawn-servants`.

# Workload Balancing

Core.async is simply amazing, it took this tricky problem and made it trivial. The solution is 4 lines.
The solution for Servant is:

- spawn N number of workers and place them in a buffered (of size N) channel.
- Take workers from the channel as you use them.
- Put them back when you get your result.

This is so beautifully simple. I just write the behavior I want, and core.async
handles the messy state. If all the webworkers are busy the code will "block"
until a webworker is free. What this means for you as a user, is you don't have
to think about which worker is available to run your code.

# Configurable message types

Now the whole point of using webworkers is to be as fast as possible. Sometimes
you can't even afford copying data to the webworker (especially if the data is
big, like at [Cryptic.io](http://cryptic.io)). Servant provides a way to access
webworkers' nifty [arraybuffer transfer context ability](<https://developer.mozilla.org/en-US/docs/Web/Guide/Performance/Using_web_workers#Passing_data_by_transferring_ownership_(transferable_objects)>).
Take for example:

```clojure
(defservantfn get-first-4bytes-as-str [arraybuffer]
  (let [d (js/DataView. arraybuffer)]
      (.toString (.getUint32 d 0) 16)))
```

That function expects an arraybuffer and returns a string. If we wanted to be
efficient about it (and didn't care about getting rid of the arraybuffer) we can
make the call using the `servant/array-buffer-message-standard-reply` fn instead
of the `servant/standard-message`. So the efficient result would be:

```clojure
(def arraybuffer (js/ArrayBuffer. 10))
(def d (js/DataView. arraybuffer))
(.setUint32 d 0 0xdeadbeef)
(def result-channel
  (servant/servant-thread
    servant-channel
    servant/array-buffer-message-standard-reply
    get-first-4bytes-as-str arraybuffer [arraybuffer]))
```

The arguments to servant-thread are:

- `servant-channel` - channel that contains the available workers
- `servant/array-buffer-message-standard-reply` - A function that defines how the `.postMessage` function will be called (a.k.a mesage-fn)
- `get-first-4bytes-as-str` - The servant function we defined earlier
- `arraybuffer` - our argument to the function
- `[arraybuffer]` - a vector of arraybuffers that are going to be transferred

The message-fn can be anything, but I think servant has you covered with:

- `standard-message` : Copies all the data both ways
- `array-buffer-message` : _Can_ transfer the context both ways
- `array-buffer-message-standard-reply` : _Can_ transfer the context when making the call, _won't_ transfer the context coming back

There is a reason why array-buffer-message isn't just the standard. You need to
explicitly tell the postMessage call that you want to transfer arraybuffers. So
to transfer context you need an additional argument, an array of arraybuffers.
You also need to make sure the defservantfn returns a vector of results and an
array of arraybuffers [result [arraybuffer1]] if you want to transfer the
arraybuffer from the worker to the browser context. I figured if you wanted
that you could use it and deal with the extra argument, if you didn't you could
write your functions how you normally would.

# Examples

I wrote two examples using the servant library:

- The first is a [simple demo](https://github.com/MarcoPolo/servant-demo) showing several use cases.
- The next is more featured demo that can encrypt/decrypt large files efficiently using webworkers.

# Last thoughts

I used to curse the name webworkers. They brought gifts of speed at the cost of
complexity. Servant is different, it doesn't sacrifice simplicity or
efficiency. I'm pretty excited at the ease of using webworkers with servant, and
I hope you have fun making an amazing, multithreaded Clojurescript application!

<br />
