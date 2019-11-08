+++
title = "Wasm is the future of serverless. Terrafirma, serverless wasm functions."
aliases = ["wasm"]
insert_anchor_links = "right"
[taxonomies]
tags = ["wasm", "rust", "Go"]
+++

When I ran into Fastly's [Terrarium](https://wasm.fastlylabs.com/), the appeal of Webassembly (wasm) finally clicked for me. We could have lightweight sandboxes and bring in my own language and libraries without the overhead of a full OS VM or [Docker](https://blog.iron.io/the-overhead-of-docker-run/). That's great for the serverless provider, but it's also great for the end user. Less overhead means faster startup time and less total cost.

## How much faster?

On my machine™, a hello world shell script takes 3ms, a docker equivalent takes 700ms, and a wasm equivalent takes 15ms.

Following [this experiment](https://blog.iron.io/the-overhead-of-docker-run/) I get these results:

```
Running: ./hello.sh
avg: 3.516431ms
Running: docker run treeder/hello:sh
avg: 692.306769ms
Running: docker run --rm treeder/hello:sh
avg: 725.912422ms
Running: docker start -a reuse
avg: 655.059021ms
Running: node hello.js
avg: 79.233337ms
Running: wasmer run wasi-hello-world.wasm
avg: 15.155896ms
```

When I think about how WASM, Docker, and OS VMs (compute instances) play together, I picture this graph below.

![Safety versus overhead – Raw binary is fast unsafe; was is fast and safe; docker is safe.](/code/wasm-graph.png "Safety vs Overhead")

The trend is that if you want safety and isolation, you must pay for it with overhead. WASM's exception to that rule is what I think makes it so promising and interesting. Wasm provides the fastest way to run arbitrary user code in a sandboxed environment.

## What is Webassembly?

Webassembly is a spec for a lightweight and sandboxed VM. Webassembly is run by a host, and can't do any side effects, unless it calls a function provided by the host. For example, if your WASM code wanted to make a GET request to a website, it could only do that by asking the host to help. The host exposes these helper function to the WASM guest. In Terrafirma, these are the `hostcall_*` functions in [`imports.go`](https://github.com/MarcoPolo/go-wasm-terrafirma/blob/master/imports.go). It's called `imports.go` because it is what your WASM code is importing from the host.

## Bring your own tools

As long as you can compile everything to a .wasm file, you can use whatever tools and language you want. All I have to do is provide a runtime, and all you have to do is provide a wasm file. However, there is a subtle caveat here. The only way you can run side effects is with the host cooperation. So you (or some library you use) must understand the environment you're running in in order to do anything interesting.

## What about a standard WASM Environment?

There isn't a mature industry standard for what imports a host should provide to the WASM code running outside the browser. The closest thing we have is [WASI](https://wasi.dev/), which defines a POSIX inspired set of syscalls that a host should implement. It's useful because it allows code would otherwise require a real syscall to work in a WASM environment. For example, In Rust you can build with the `--target wasm32-wasi` flag and your code will just work in any [wasi environment](https://wasmer.io/).

## Terrafirma

Phew! Finally at TerraFirma. TerraFirma is a WASM runtime environment I wrote to let you run wasm code in the cloud. You upload your wasm file by copying it into a shared [KBFS folder](https://keybase.io/docs/kbfs) with the keybase user [kbwasm](https://keybase.io/kbwasm). Then you setup some DNS records to point your domain to TerraFirma's servers. And that's it! You can update the wasm code at any time by overwriting the old .wasm file with the new one.

## Code Examples

- [Hello World](https://github.com/MarcoPolo/terrafirma-scraper)
- [Scraper Endpoint](https://github.com/MarcoPolo/terrafirma-scraper) – A web scraper that uses Servo – a new browser engine from Mozilla.

### Terrafirma – Hello World Tutorial

This example uses Rust, so if you don't have that setup [go here first](https://rustup.rs/).

1. Point your domain to TerraFirma servers (`terrafirma.marcopolo.io` or `52.53.126.109`) with an A record, and set a `TXT` record to point to your shared folder (e.g. `"kbp=/keybase/private/<my_keybase_username>,kbwasm/"`)

```

example.com 300 A terrafirma.marcopolo.io

_keybase_pages.example.com 300 TXT "kbp=/keybase/private/<my_keybase_username>,kbwasm/"

```

2. Verify the DNS records are correct

```

$ dig example.com A
...
;; ANSWER SECTION:
wasm.marcopolo.io.      300     IN      A       52.53.126.109
...

```

<br/>

```

$ dig _keybase_pages.example.com TXT
...
;; ANSWER SECTION:
_keybase_pages.example.com <number> IN TXT "kbp=/keybase/private/<my_keybase_username>,kbpbot/"
...

```

3. Clone the Hello World Repo

```
git clone git@github.com:MarcoPolo/terrafirma-hello-world.git
```

4. Build it

```
cd terrafirma-hello-world
cargo build --release
```

5. Deploy it

```

cp target/wasm32-unknown-unknown/release/terrafirma_helloworld.wasm /keybase/private/<your_kb_username>,kbwasm/hello.wasm

```

6. Test it

```
curl https://example.com/hello.wasm
```

[terrafirma]: https://github.com/marcopolo/go-wasm-terrafirma
