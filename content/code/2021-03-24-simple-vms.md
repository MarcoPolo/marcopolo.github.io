+++
title = "Simple Declarative VMs"
date = 2021-03-07T00:00:00.000Z

[taxonomies]
tags = ["Nix", "VMs", "cryptic"]

[extra]
author = "Marco"
+++

I've been on a hunt to find a simple and declarative way to define VMs. I wanted
something like [NixOS
Containers](https://nixos.org/manual/nixos/stable/#ch-containers), but with a
stronger security guarantee. I wanted to be able to use a Nix expression to
define what the VM should look like, then reference that on my Server's
expression and have it all work automatically. I didn't want to manually
run any commands. The hunt is over, I finally found it.

## My Use Case

I want a machine that I can permanently hook up to a WireGuard VPN and treat
as if it were in a remote place. At first I did this with a physical machine,
but I didn't want to commit the whole machine's compute for a novelty. What I
really want is a small VM that is permanently hooked up to a WireGuard VPN.
Minimal investment with all the upsides.

## NixOS QEMU

Nix OS supports building your system in a QEMU runnable environment right out of
the box. `nixos-rebuild build-vm` is a wrapper over `nix build
github:marcopolo/marcopolo.github.io#nixosConfigurations.small-vm.config.system.build.vm`. (Side note, with
flakes you can build this exact VM by running that command[^1]). This means NixOS
already did the hard work of turning a NixOS configuration into a valid VM that
can be launched with QEMU. Not only that, but the VM shares the `/nix/store`
with the host. This results in a really small VM (disk size is 5MB).

NixOS does the heavy lifting of converting a configuration into a script that
will run a VM, so all I need to do is write a service that manages this process.
Enter [simple-vms], heavily inspired by
[vms.nix](https://github.com/Nekroze/vms.nix) and
[nixos-shell](https://github.com/Mic92/nixos-shell). [simple-vms] is a NixOS
module that takes in a reference to the
`nixosConfigurations.small-vm.config.system.build.vm` derivation and the
option of whether you want state to be persisted, and defines a Systemd
service for the vm (There can be multiple VMs). This really is a simple
module, the NixOS service definition is about 10 lines long, and its
`ExecStart` is simply:
```
mkdir -p /var/lib/simple-vms/${name}
cd /var/lib/simple-vms/${name}
exec ${cfg.vm.out}/bin/run-nixos-vm;
```

With this service we can get and keep our VMs up and running.

## Stateless VMs

I got a sticker recently that said "You either have one source of truth, of
multiple sources of lies." To that end, I wanted to make my VM completely
stateless. QEMU lets you mount folders into the VM, so I used that to mount host
folders in the VM's `/etc/wireguard` and `/etc/ssh` so that the host can
provide the VM with WireGuard keys, and the VM can persist it's SSH host keys.

That's all the VM really needs. Every time my VM shuts down I delete the drive.
And just to be safe, I try deleting any drive on boot too.

If you're running a service on the VM, you'll likely want to persist that
service's state files too in a similar way.

## Fin

That's it. Just a small post for a neat little trick. If you set this up let
me know! I'm interested in hearing your use case.

### Footnotes
[^1]: User/pass = root/root. Exit qemu with C-a x.

[simple-vms]: https://github.com/MarcoPolo/simple-vms/

