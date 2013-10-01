---
layout: post
title: Introducing Servant, a Clojurescript library for using web workers
published: false
---

# Concurrent Programming
Yes, yes, we all know javascript is single threaded, but web workers introduce OS level threads into the mix.
Web workers provide a powerful outlet for writing efficient multithreaded javascript. 
"Multithreaded javascript? Yuck!", I know. Trust me I know. Concurrent programming is hard enough (in imperative languages), 
so the webworker designers decided to circumvent a bunch of concurrency problems by forbidding any shared data between threads.
There are better ways of doing this (read _immutability_), but we work with what we got. Which leads us into my next point.

# Problems with web workers







```clojure   

;; Finding answers in code
(def answer 42)
(defn the-answer-to-life? [n]
    (= n answer))
(the-answer-to-life? (* 6 7))
```


