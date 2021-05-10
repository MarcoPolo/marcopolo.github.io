## Analogy

I don't install development tools globally. I don't have `node` added to my
`PATH` in my `~/.zshrc` file. And running `cargo` outside a project folder
returns "command not found." It's not that I don't use these programs, I just
don't have them installed globally. They are added, along with other tools, when
I enter a project folder.

I not only don't install project-specific tools globally, I think doing so is a
bad pattern that leads to nothing but heartache and woe. If you are running
`sudo apt-get install` or `brew install` prior to building a project, you are
doing it wrong. I define my tools in a declarative and reproducible way so that
my projects will easily build on any machine at any point in time. Whether it's
on a friends machine today, or a new laptop in 10 years.

With a declarative dev environment you are able to `cd` into a directory and
start working on the project.

## Why do I need a declarative dev environment?

Not only does this setup get you a better dev experience, it makes sure that the
project will work the same for others as it does for you. Thus solving the
"Works on my machine" issue.
 
## What do I mean by a declarative dev environment?

I mean a project that has a special file (or files) that define all the
dependencies required to build and run your project. It doesn't necessarily have
to include the actual binaries you will run in the repo, but it should be
reproducible. Such that if you clone the project you should be running the exact
same tools as me.

## How to setup one up With Nix

To accomplish this I use [Nix] with [Nix Flakes] and [direnv].

## How it works

## Why not Docker?

* Not reproducible out of the box
* Less efficient storage
* Doesn't integrate with your existing setup. i.e. vim/emacs
* Runs in a VM on MacOS




[Nix]: https://nixos.org
[Nix Flakes]: https://www.tweag.io/blog/2020-05-25-flakes/
[direnv]: https://direnv.net/