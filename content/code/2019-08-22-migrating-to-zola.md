+++
title = "I moved my blog over to Zola, you should too"
[taxonomies]
tags = ["rust", "blogging"]
+++

# Blogging

I started this blog like many other folks, on GitHub Pages. It was great at
the time. You can have a source repo that compiles to a blog. Neat! Over time
though I started really feeling the pain points with it. When I wanted to
write a quick post about something I'd often spend hours just trying to get
the right Ruby environment set up so I can see my blog locally. When I got an
email from GitHub saying that my blog repo has a security vulnerability in
one of its Gems, I took the opportunity to switch over to
[Zola](https://www.getzola.org).

# Zola

Zola make more sense to me than Jekyll. I think about my posts in a
hierarchy. I'd like my source code to match my mental representation. If you
look at the [source](https://marcopolo.io/code/migrating-to-zola/) of this blog, you'll see I have 3 folders (code, books,
life). In each folder there are relevant posts. I wanted my blog to show the
contents folder as different sections. For the life of me I couldn't figure
out how to do that in Jekyll. I ended up just using a single folder for all
my posts and using the category metadata in the front-matter to create the
different sections. With Zola, this kind of just worked. I had to create an
`_index.md` file to provide some metadata, but nothing overly verbose.

# I'm not a Jekyll pro...

Or even really any level past beginner. I image if you've already heavily
invested yourself in the Jekyll ecosystem this probably wouldn't make sense
for you. I'm sure there are all sorts of tricks and features that Jekyll
can do that Zola cannot. I'm Okay with that. I really don't need that much
from my blogging library.

Zola has 3 commands: `build`, `serve`, and `init`. They do what you'd expect
and nothing more. I really admire this philosophy. Whittle down your feature
set and make those features a _joy_ to use.

# Fast

Changes in Zola propagate quickly. Zola rebuilds my (admittedly very small blog) in less than a millisecond. Zola comes with a livereload script that automatically updates your browser when you are in `serve` mode. It's feasible to write your post and see how it renders almost instantly.

# Transition

The biggest change was converting Jekyll's front-matter (the stuff at the top
of the md files) format into Zola's front-matter format. Which was changing
this:

```
---
layout: post
title: Interacting with Go from React Native through JSI
categories: javascript react-native jsi go
---

```

into this:

```
+++
title = "Interacting with Go from React Native through JSI"
[taxonomies]
tags = ["javascript", "react-native", "JSI", "Go"]
+++
```

There was also a slight rewrite in the template files that was necessary
since Zola uses the [Tera Templating Engine](https://tera.netlify.com)

The rest was just moving (I'd argue organizing) files around.

# Prettier Repo

I think at the end the repo became a little prettier to look at. You could
argue it's a small thing, but I think these small things matter. It's already
hard enough to sit down and write a post. I want every bit of the experience
to be beautiful.

But don't take my word for it! judge yourself: [Jekyll](https://github.com/MarcoPolo/marcopolo.github.io/tree/jekyll_archive) vs. [Zola](https://github.com/MarcoPolo/marcopolo.github.io)
