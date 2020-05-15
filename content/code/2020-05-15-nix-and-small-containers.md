+++
title = "Nix and small containers with Docker multi-stage builds"
[taxonomies]
tags = ["Docker", "Container", "Nix", "ops", "multi-stage"]
+++

Multi Stage builds are great for minimizing the size of your container. The
general idea is you have a stage as your builder and another stage as your
product. This allows you to have a full development and build container while
still having a lean production container. The production container only carries
its runtime dependencies.

```dockerfile
FROM golang:1.7.3
WORKDIR /go/src/github.com/alexellis/href-counter/
RUN go get -d -v golang.org/x/net/html
COPY app.go .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=0 /go/src/github.com/alexellis/href-counter/app .
CMD ["./app"]
```
(from Docker's [docs on multi-stage])

Sounds great, right? What's the catch? Well, it's not always easy to know what the
runtime dependencies are. For example you may have installed something in /lib
that was needed in the build process. But it turned out to be a shared library
and now it needs to be included in the production container. Tricky! Is there
some automated way to know all your runtime dependencies?

## Enter Nix
[Nix] is a functional and immutable package manager. It works great for
reproducible builds. It keeps track of packages and their dependencies via their
content hashes. And, relevant for this exercise, it also keeps track of the
dependencies of a built package. That means we can use Nix to build our project
and then ask Nix what our runtime dependencies are. With that information we can
copy just those files to the product stage of our multi-stage build and end up
with the smallest possible docker container.

Our general strategy will be to use a Nix builder to build our code. Ask the Nix
builder to tell us all the runtime dependencies of our built executable. Then
copy the executable with all it's runtime dependencies to a fresh container. Our
expectation is that this will result in a minimal production container.

## Example

As a simple example let's package a "Hello World" program in Rust. The code is
what you'd expect:

```rust
pub fn main() {
    println!("Hello, world!");
}
```

### Nix build expression

If we were just building this locally, we'd just run `cargo build --release`.
But we are going to have Nix build this for us so that it can track the runtime
dependencies. Therefore we need a `default.nix` file to describe the build
process. Our `default.nix` build file looks like this:

```nix
with (import <nixpkgs> {});
rustPlatform.buildRustPackage {
  name = "hello-rust";
  buildInputs = [ cargo rustc ];
  src = ./.;
  # This is a shasum over our crate dependencies
  cargoSha256 = "1s4vg081ci6hskb3kk965nxnx384w8xb7n7yc4g93hj55qsk4vw5";
  # Use this to figure out the correct Sha256
  # cargoSha256 = lib.fakeSha256;
  buildPhase = ''
    cargo build --release
  '';
  checkPhase = "";
  installPhase = ''
    mkdir -p $out/bin
    cp target/release/hello $out/bin
  '';
}
```

Breaking down the Nix expression: we specify what our inputs our to our
build: `cargo` and `rustc`; we figure out what the sha256sum is of our crate
dependencies; and we define some commands to build and install the executable.

We can verify this works locally on our machine by running `nix-build .`
(assuming you have Nix installed locally). You'll end up with a symlink named
result that points the compiled executable residing in /nix/store. Running
`./result/bin/hello` should print "Hello, world!".

### Docker file

Now that we've built our Nix expression that defines how the code is built, we
can add Docker to the mix. The goal is to have a builder stage that runs the
nix-build command, then have a production stage that copies the executable and
its runtime dependencies from builder. The production stage container will
therefore have only the minimal amount of stuff needed to run.

```Dockerfile
# Use nix as the builder
FROM nixos/nix:latest AS builder

# Update the channel so we can get the latest packages
RUN nix-channel --update nixpkgs

WORKDIR /app

# Run the builder first without our code to fetch build dependencies.
# This will fail, but that's okay. We just want to have the build dependencies
# cached as a layer. This is just a caching optimization that can be removed.
COPY default.nix .
RUN nix-build . || true

COPY . .

# Now that our code is here we actually build it
RUN nix-build .

# Copy all the run time dependencies into /tmp/nix-store-closure
RUN mkdir /tmp/nix-store-closure
RUN echo "Output references (Runtime dependencies):" $(nix-store -qR result/)
RUN cp -R $(nix-store -qR result/) /tmp/nix-store-closure

ENTRYPOINT [ "/bin/sh" ]

# Our production stage
FROM scratch
WORKDIR /app
# Copy the runtime dependencies into /nix/store
# Note we don't actually have nix installed on this container. But that's fine,
# we don't need it, the built code only relies on the given files existing, not
# Nix.
COPY --from=builder /tmp/nix-store-closure /nix/store
COPY --from=builder /app/result /app
CMD ["/app/bin/hello"]
```

If we build this `Dockerfile` with `docker build .`, we'll end up with an 33MB
container. Compare this to a naive
[Dockerfile](https://gist.github.com/MarcoPolo/7953f1ca2691405b5b04659027967336)
where we end up with a 624 MB container! That's an order of magnitude smaller
for a relatively simple change.

Note that our executable has a shared library dependency on libc. Alpine
linux doesn't include libc, but this still works. How? When we build our code we
reference the libc shared library stored inside `/nix/store`. Then when we copy
the executable nix tells us that the libc shared library is also a dependency so
we copy that too. Our executable uses only the libc inside `/nix/store` and
doesn't rely on any system provided libraries in `/lib` or elsewhere.

## Conclusion

With a simple Nix build expression and the use of Docker's multi stage builds we
can use Docker's strength of providing a consistent and portable environment
with Nix's fine grained dependency resolution to create a minimal production
container.

## A note on statically linked executables

Yes, you could build the hello world example as a statically linked musl-backed
binary. But that's not the point. Sometimes code relies on a shared library, and
it's just not worth or impossible to convert it. The beauty of this system is
that it doesn't matter if the output executable is fully statically linked or
not. It will work just the same and copy over the minimum amount of code needed
for the production container to work.

## A note on Nix's dockerTools

Nix proves a set of functions for creating Docker images:
[pkgs.dockerTools](https://nixos.org/nixpkgs/manual/#sec-pkgs-dockerTools). It's
very cool, and I recommend checking it. Unlike docker it produces
deterministic images. Note, for all but the simplest examples, KVM is required.

## A note on Bazel's rules_docker

I don't know much about this, but I'd assume this would be similar to what I've
described. If you know more about this, please let me know!

[docs on multi-stage]: https://docs.docker.com/develop/develop-images/multistage-build/
[Nix]: https://nixos.org/