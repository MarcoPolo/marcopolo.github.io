+++
title = "From C to Rust to C again. Or: Re-exporting C exports in Rust"
insert_anchor_links = "right"
[taxonomies]
tags = ["FFI", "rust", "C"]
+++

The only difference between being a grown up and being a kid, in my experience, is as a grown up, you have much fewer people who are willing to play the game _telephone_ with you. Luckily for me, I have access to a computer, a C compiler, and a Rust compiler. Let me show you how I played telephone with Rust & C.

tl;dr:
* Rust can't re-export from a linked C library (unless you rename) when compiled as a cdylib.
* Look at this [issue][gh-issue]

Imagine you have some C code that provides `add_two`. It looks like this:
```c
int add_two(int n)
{
    return n + 2;
}
```
And you can even let Cargo deal with building your C library by making a build.rs with `cc`. Like so:
```rust
use cc;

fn main() {
    cc::Build::new().file("src/c/foo.c").compile("foo");
}
```



Now you want to be able to call `add_two` from Rust. Easy! You look at the [FFI](https://doc.rust-lang.org/nomicon/ffi.html) section in the Nomicon. And follow it like so:

```rust
#[link(name = "foo", kind = "static")]
#[no_mangle]
extern "C" {
    pub fn add_two(x: u32) -> u32;
}

#[no_mangle]
pub extern "C" fn add_one(x: u32) -> u32 {
    let a = unsafe { add_two(x) };
    a - 1
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn it_works() {
        assert_eq!(add_one(2), 3);
        assert_eq!(unsafe { add_two(2) }, 4);
    }
}
```

Now for the last chain in our telephone. We'll make a new C file that will call our Rust defined `add_one` and our C defined `add_two`.

```c
extern int add_one(int n);
extern int add_two(int n);

int main()
{
    return add_one(add_two(39));
}
```

We use Clang to build this file:
```
clang call_rust.c -lrust_c_playground -L./target/debug -o call_rust
```

Now we have an executable called `call_rust` which calls a Rust defined function and calls a C defined function that it pulled in from a single Rust Library (called `librust_c_playground.dylib` on macOS). The flags in the clang command mean: `-l` link this library; `-L` look here for the library.

We've built the code, now we can even run it!
```
./call_rust
echo $? # Print the return code of our program, hopefully 42
```

Great! We've called C from a Rust Library from a C program. But there's a catch. This won't work if you are building a `cdylib`. There isn't an RFC yet on how to re-export C externs. In the mean time you'll either have to: re-export under a different name, or build a `dylib`. See this issue: [Re-exporting C symbols for cdylib][gh-issue].

Hope this helps.


[gh-issue]: https://github.com/rust-lang/rfcs/issues/2771