+++
title = "Declarative Dev Environments"
draft = true
[taxonomies]
tags = ["Nix"]
+++

I don't install development tools globally. I don't have `node` added to my
`PATH` in my `~/.zshrc` file, and running `cargo` outside a project folder
returns "command not found." I wipe my computer on every reboot. With the
exception of four folders (`/boot`, `/nix`, `/home`, and `/persist`), everything
gets [deleted](https://grahamc.com/blog/erase-your-darlings). And it has worked
out great.

Instead of installing development packages globally, I declare them as a
dependency in my project's dev environment. They become available as soon as I
`cd` into the project folder. If two projects use the same tool then I only keep
one version of that tool on my computer.

I think installing dev tools globally is a bad pattern that leads to nothing but
heartache and woe. If you are running `sudo apt-get install` or `brew install`
prior to building a project, you are doing it wrong. By defining your dev tool
dependencies explicitly you allow your projects to easily build on any
machine at any point in time. Whether it's on a friends machine today, or a new
laptop in 10 years. It even makes CI integration a breeze.

## What do I mean by a declarative dev environment?

I mean a project that has a special file (or files) that define all the
dependencies required to build and run your project. It doesn't necessarily have
to include the actual binaries you will run in the repo, but it should be
reproducible. If you clone my project you should be running the exact
same tools as me.

## How I setup my declarative dev environments

To accomplish this I use [Nix] with [Nix Flakes] and [direnv]. There are three
relevant files: `flake.nix` which defines the build of the project and the tools
I need for development; `flake.lock` which is similar in spirit to a `yarn.lock`
or `Cargo.lock` file, it _locks_ the exact version of any tool used and
generated automatically the first time you introduce dependencies; and finally a
`.envrc` file which simply tells direnv to ask Nix what the environment should
be, and sets up the environment. Here are some simple examples:
[flake.nix](https://github.com/MarcoPolo/templates/tree/master/trivial),
[.envrc](https://github.com/MarcoPolo/templates/blob/master/trivial/.envrc)
(`flake.lock` omitted since it's automatically generated).

As a shortcut for setting up a `flake.nix` and `.envrc`, you can use a template
to provide the boilerplate. When I start a new project I'll run `nix flake init
-t github:marcopolo/templates` which copies the files from this
[repo](https://github.com/MarcoPolo/templates/tree/master/trivial) and puts them
in your current working directory. Then running `direnv allow` will setup your
local environment, installing any missing dependencies through Nix as a side
effect.

This blog itself makes use of [declarative dev
environments](https://github.com/MarcoPolo/marcopolo.github.io/blob/master/flake.nix#L14).


## How Nix works, roughly

This all works off [Nix]. Nix is a fantastic package manager and build tool that
provides reproducible versions of packages that don't rely on a specific global
system configuration. Specifically packages installed through Nix don't rely an
a user's `/usr/lib` or anything outside of `/nix/store`. You don't even need
libc installed (as may be the case if you are on [Alpine
Linux](https://www.alpinelinux.org/)).

For a deeper dive see [How Nix Works](https://nixos.org/guides/how-nix-works.html).

## An example, how to setup a Yarn based JS project.

To be concrete, let me show an example. If I wanted to start a JS project and
use [Yarn](https://yarnpkg.com/) as my dependency manager, I would do something
like this: 

```bash
# 1. Create the project folder
mkdir my-project

# 2. Add the boilerplate files.
nix flake init -t github:marcopolo/templates

# 3. Edit flake.nix file to add yarn and NodeJS.
# With your text editor apply this diff:
# -          buildInputs = [ pkgs.hello ];
# +          buildInputs = [ pkgs.yarn pkgs.nodejs-12_x ];

# 4. Allow direnv to run this environment. This will also fetch yarn with Nix
#    and add it to your path.
direnv allow

# 5. Yarn is now available, proceed as normal. 
yarn init
```

You can simplify this further by making a Nix Flake template that already has
Yarn and NodeJS included. 

## Another example. Setting up a Rust project.

```bash
# 1. Create the project folder
mkdir rust-project

# 2. Add the boilerplate files.
nix flake init -t github:marcopolo/templates#rust

# 3. Cargo and rust is now available, proceed as normal. 
cargo init
cargo run
```

Here we used a Rust specific template, so no post template init changes were required.

## Dissecting the `flake.nix` file

Let's break down the `flake.nix` file so we can understand what it is we are
declaring.


First off, the file is written in [Nix, the programming
language](https://nixos.wiki/wiki/Nix_Expression_Language). At a high level you
can read this as JSON but with functions. Like JSON it can only represent
expressions (you can only have one top level JSON object), unlike JSON you can
have functions and variables. 

```nix
{
  # These are comments

  # Here we are defining a set. This is equivalent to a JSON object.
  # The key is description, and the value is the string.
  description = "A very basic flake";

  # You can define nested sets by using a `.` between key parts.
  # This is equivalent to the JSON object {inputs: {flake-utils: {url: "github:..."}}}
  inputs.flake-utils.url = "github:numtide/flake-utils";

  # Functions are defined with the syntax of `param: functionBodyExpression`.
  # The param can be destructured if it expects a set, like what we are doing here. 
  # This defines the output of this flake. Our dev environment will make use of
  # the devShell attribute, but you can also define the release build of your
  # package here.
  outputs = { self, nixpkgs, flake-utils }:
    # This is a helper to generate these outputs for each system (x86-linux,
    # arm-linux, macOS, ...)
    flake-utils.lib.eachDefaultSystem (system:
      let
        # The nixpkgs repo has to know which system we are using.
        pkgs = import nixpkgs { system = system; };
      in
      {
        # This is the environment that direnv will use. You can also enter the
        # shell with `nix shell`. The packages in `buildInputs` are what become
        # available to you in your $PATH. As an example this only has the hello
        # package.
        devShell = pkgs.mkShell {
          buildInputs = [ pkgs.hello ];
        };

        # You can also define a package that is built by default when you run
        # `nix build`.  The build command creates a new folder, `result`, that
        # is a symlink to the build output.
        defaultPackage = pkgs.hello;
      });
}

```

## On Dev Tools and A Dev Setup

There is a subtle distinction on what constitutes a Dev Tool vs A Dev Setup. I
classify Dev Tools as things that need to be available to build or develop a given
project specifically. Think of `gcc`, `yarn`, or `cargo`. The Dev Setup category
are for things that are useful when developing in general. Vim, Emacs,
[ag](https://geoff.greer.fm/ag/) are some examples.

Dev tools are worth defining explicitly in your project's declarative dev environment (in
a `flake.nix` file). A Dev Setup is highly personal and not worth defining in the
project's declarative dev environment. But that is not to your dev setup in not
worth defining at all. In fact, if you are familiar with Nix, you can extend the
same ideas of this post to your user account with
[Home Manager](https://github.com/nix-community/home-manager). 

With Home Manager You can declaratively define which programs you want available
in your dev setup, what Vim plugins you want installed, what ZSH plugins you
want available and much more. It's the core idea of declarative environments
taken to the user account level.

## Why not Docker?

Many folks use Docker to get something like this, but while it gets close – and
in some cases functionally equivalent – it has some shortcomings:

For one, a Dockerfile is not reproducible out of the box. It is common to use
`apt-get install` in a Dockerfile to add packages. This part isn't reproducible
and brings you back to the initial problem I outlined. 

Docker is less effecient with storage. It uses layers as the base block of
Docker images rather than packages. This means that it's relatively easy to end
up with many similar docker images (for a more thorough analysis check
out [Optimising Docker Layers for Better Caching with
Nix](https://grahamc.com/blog/nix-and-layered-docker-images)).

Spinning up a container and doing development inside may not leverage your
existing dev setup. For example you may have Vim setup neatly on your machine,
but resort to `vi` when developing inside a container.  Or worse, you'll 
rebuild your dev setup inside the container, which does nothing more than
add dead weight to the container since it's an addition solely for you and not
really part of the project. Of course there are some workarounds to this issue,
for example VS Code supports opening a project inside a container.
[ZMK](https://github.com/zmkfirmware/zmk) does this and it has worked great for
me.

If you are on MacOS, developing inside a container is actually slower. Docker
on Mac relies on running a linux VM in the background and running containers in
that VM. By default that VM is underpowered relative to the host MacOS machine.

There are cases where you actually do only want to run the code in an
x86-linux environment and Docker provides a convenient proxy for this. In these
cases I'd suggest using Nix to generate the Docker images. This way you get the
declarative and reproducible properties from Nix and the convenience from Docker.

As a caveat to all of the above, if you already have a reproducible dev setup
with a Docker container that works for you, please don't throw that all out and
redesign your system from scratch. Keep using it until it stops meeting your
needs and come back to this when it happens. Until then, keep building.

## On Nix Flakes

Nix Flakes is still new and in beta, so it's likely that if you install Nix from
their [download page](https://nixos.org/download.html) you won't have Nix Flakes
available. If you don't already have Nix installed, you can install a version
with Nix Flakes [here](https://github.com/numtide/nix-unstable-installer),
otherwise read the section on [installing flakes](https://nixos.wiki/wiki/Flakes#Installing_flakes).


## Closing thoughts

In modern programming languages we define all our dependencies explicitly and
lock the specific versions used. It's about time we do that for all our tools
too. Let's get rid of the `apt-get install` and `brew install` section of READMEs.


[Nix]: https://nixos.org
[Nix Flakes]: https://www.tweag.io/blog/2020-05-25-flakes/
[direnv]: https://direnv.net/