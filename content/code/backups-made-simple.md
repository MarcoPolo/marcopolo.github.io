+++
title = "Backups made simple"
date = 2021-03-07T00:00:00.000Z

[taxonomies]
tags = ["Nix", "foundations", "cryptic"]

[extra]
author = "Marco"
+++

I've made a backup system I can be proud of, and I'd like to share it with you
today. It follows a philosophy I've been fleshing out called _The
Functional Infra_. Concretely it aims to:
* Be pure. An output should only be a function of its inputs.
* Be declarative and reproducible. A by product of being pure.
* Support rollbacks. Also a by product of being pure.
* Surface actionable errors. The corollary being it should be easy to understand
  and observe what is happening.

At a high level, the backup system works like so:
1. ZFS creates automatic snapshots every so often.
2. Those snapshots are replicated to an EBS-backed EC2 instance that is only
   alive while backup replication is happening. Taking advantage of ZFS'
   incremental snapshot to make replication generally quite fast.
3. The EBS drive itself stays around after the instance is terminated. This
   drive is a Cold HDD (sc1) which costs about $0.015 gb/month.

## ZFS

To be honest I haven't used ZFS all that much, but that's kind of my point. I,
as a non-expert in ZFS, have been able to get a lot out of it just by
following the straightforward documentation. It seems like the API is well
thought out and the semantics are reasonable. For example, a consistent snapshot
is as easy as doing `zfs snapshot tank/home/marco@friday`.

### Automatic snapshots

On NixOS setting up automatic snapshots is a breeze, just add the following to
your NixOS Configuration:

```nix
{
  services.zfs.autoSnapshot.enable = true;
}
```

and setting the `com.sun:auto-snapshot` option on the filesystem. E.g.: `zfs set
com.sun:auto-snapshot=true <pool>/<fs>`. Note that this can also be done on
creation of the filesystem: `zfs create -o mountpoint=legacy -o
com.sun:auto-snapshot=true tank/home`.

With that enabled, ZFS will keep a snapshot for the latest 4 15-minute, 24
hourly, 7 daily, 4 weekly and 12 monthly snapshots.

### On Demand EC2 Instance for Backups

Now that we've demonstrated how to setup snapshotting, we need to tackle the
problem of replicating those snapshots somewhere so we can have real backups.
For that I use one of my favorite little tools:
[lazyssh](https://github.com/stephank/lazyssh). Its humble description betrays
little information at its true usefulness. The description is simply:
_A jump-host SSH server that starts machines on-demand_. What it enables is
pretty magical. It essentially lets you run arbitrary code when something SSHs
through the jump-host.

Let's take the classic ZFS replication example from the
[docs](https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html):
`host1# zfs send tank/dana@snap1 | ssh host2 zfs recv newtank/dana`. This
command copies a snapshot from a machine named `host1` to another machine named
`host2` over SSH. Simple and secure backups. But it relies on `host2` being
available. With `lazyssh` we can make `host2` only exist when needed.
`host2` would start when the ssh command is invoked and terminated when the ssh
command finishes. The command with `lazyssh` would look something like this
(assuming you have a `lazyssh` target in your `.ssh/config` as explained in the
[docs](https://github.com/stephank/lazyssh)):

```
host1# zfs send tank/dana@snap1 | ssh -J lazyssh host2 zfs recv newtank/dana
```
Note the only difference is the `-J lazyssh`.


So how do we actually setup `lazyssh` to do this? Here is my configuration:
{{ gist(url="https://gist.github.com/MarcoPolo/13462e986711f62bfc6b7b8e494c5cc8") }}

Note there are a couple of setup steps:
1. Create the initial sc1 EBS Drive. I did this in the AWS Console, but you
   could do this in Terraform or the AWS CLI.
2. Create the ZFS pool on the drive. I launched my lazy archiver without the ZFS
   filesystem option and ran: `zpool create -o ashift=12 -O
   mountpoint=none POOL_NAME /dev/DRIVE_LOCATION`. Then I created the
   `POOL_NAME/backup` dataset with `zfs create -o acltype=posixacl -o xattr=sa -o mountpoint=legacy POOL_NAME/backup`.

As a quality of life and security improvement I setup
[homemanager](https://github.com/nix-community/home-manager) to manage my SSH
config and known_hosts file so these are automatically correct and properly
setup. I generate the lines for known_hosts when I generate the host keys
that go in the `user_data` field in the `lazsyssh-config.hcl` above. Here's the
relevant section from my homemanager config:

```nix
{
  programs.ssh = {
    enable = true;

    # I keep this file tracked in Git alongside my NixOS configs.
    userKnownHostsFile = "/path/to/known_hosts";
    matchBlocks = {
      "archiver" = {
        user = "root";
        hostname = "archiver";
        proxyJump = "lazyssh";
        identityFile = "PATH_TO_AWS_KEYPAIR";
      };

      "lazyssh" = {
        # This assume you are running lazyssh locally, but it can also
        # reference another machine.
        hostname = "localhost";
        port = 7922;
        user = "jump";
        identityFile = "PATH_TO_LAZYSSH_CLIENT_KEY";
        identitiesOnly = true;
        extraOptions = {
          "PreferredAuthentications" = "publickey";
        };
      };
    };
  };
}
```

Finally, I use the provided NixOS Module for `lazyssh` to manage starting it and
keeping it up. Here's the relevant parts from my `flake.nix`:

```
{
  # My fork that supports placements and terminating instances after failing to
  # attach volume.
  inputs.lazyssh.url = "github:marcopolo/lazyssh/attach-volumes";
  inputs.lazyssh.inputs.nixpkgs.follows = "nixpkgs";

    outputs =
    { self
    , nixpkgs
    , lazyssh
    }: {
      nixosConfigurations = {

        nixMachineHostName = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
              {
                imports = [lazyssh.nixosModule]
                services.lazyssh.configFile =
                  "/path/to/lazyssh-config.hcl";
                # You'll need to add the correct AWS credentials to `/home/lazyssh/.aws`
                # This could probably be a symlink with home-manager to a
                # managed file somewhere else, but I haven't go down that path
                # yet
                users.users.lazyssh = {
                  isNormalUser = true;
                  createHome = true;
                };
              }
          ];
        };
      };
    }
}
```

With all that setup, I can ssh into the archiver by simple running `ssh
archiver`. Under the hood, `lazyssh` starts the EC2 instance and attaches the
EBS drive to it. And since `ssh archiver` works, so does the original example
of: `zfs send tank/dana@snap1 | ssh archiver zfs recv newtank/dana`.

## Automatic Replication

The next part of the puzzle is to have backups happen automatically. There are
various tools you can use for this. Even a simple cron that runs the `send/recv`
on a schedule. I opted to go for what NixOS supports out of the box, which is
[https://github.com/alunduil/zfs-replicate](https://github.com/alunduil/zfs-replicate).
Unfortunately, I ran into a couple issues that led me to make a fork. Namely:
1. Using `/usr/bin/env - ssh` fails to use the ssh config file. My fork supports
   specifying a custom ssh binary to use.
2. Support for `ExecStartPre`. This is to "warm up" the archiver instance. I run
   `nixos-rebuild switch` which is basically a no-op if there is no changes to
   apply from the configuration file, or blocks until the changes have been
   applied. In my case these are usually the changes inside the UserData field.
3. Support for `ExecStopPost`. This is to add observability to this process.
5. I wanted to raise the systemd timeout limit. In case the `ExecStartPre` takes
   a while to warm-up the instance.

Thankfully with flakes, using my own fork was painless. Here's the relevant
section from my `flake.nix` file:
```nix
  # inputs.zfs-replicate.url = "github:marcopolo/zfs-replicate/flake";
  # ...
  # Inside nixosSystem modules...
  ({ pkgs, ... }:
    {
      imports = [ zfs-replicate.nixosModule ];
      # Disable the existing module
      disabledModules = [ "services/backup/zfs-replication.nix" ];

      services.zfs.autoReplication =
        let
          host = "archiver";
          sshPath = "${pkgs.openssh}/bin/ssh";
          # Make sure the machine is up-to-date
          execStartPre = "${sshPath} ${host} nixos-rebuild switch";
          honeycombAPIKey = (import ./secrets.nix).honeycomb_api_key;
          honeycombCommand = pkgs.writeScriptBin "reportResult" ''
            #!/usr/bin/env ${pkgs.bash}/bin/bash
            ${pkgs.curl}/bin/curl https://api.honeycomb.io/1/events/zfs-replication -X POST \
              -H "X-Honeycomb-Team: ${honeycombAPIKey}" \
              -H "X-Honeycomb-Event-Time: $(${pkgs.coreutils}/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")" \
              -d "{\"serviceResult\":\"$SERVICE_RESULT\", \"exitCode\": \"$EXIT_CODE\", \"exitStatus\": \"$EXIT_STATUS\"}"
          '';
          execStopPost = "${honeycombCommand}/bin/reportResult";
        in
        {
          inherit execStartPre execStopPost host sshPath;
          enable = true;
          timeout = 90000;
          username = "root";
          localFilesystem = "rpool/safe";
          remoteFilesystem = "rpool/backup";
          identityFilePath = "PATH_TO_AWS_KEY_PAIR";
        };
    })
```

That sets up a systemd service that runs after every snapshot. It also
reports the result of the replication to
[Honeycomb](https://www.honeycomb.io/), which brings us to our next
section...


## Observability

The crux of any automated process is it failing silently. This is especially bad
in the context of backups, since you don't need them until you do. I solved this
by reporting the result of the replication to Honeycomb after every run. It
reports the `$SERVICE_RESULT`, `$EXIT_CODE` and `$EXIT_STATUS` as returned by
systemd. I then create an alert that fires if there are no successful runs in
the past hour.

## Future Work

While I like this system for being simple, I think there is a bit more work in
making it pure. For one, there should be no more than 1 manual step for setup,
and 1 manual step for tear down. There should also be a similar simplicity in
upgrading/downgrading storage space.

For reliability, the archiver instance should scrub its drive on a schedule.
This isn't setup yet.

At $0.015 gb/month this is relatively cheap, but not the cheapest. According to
[filstats](https://filstats.com/) I could use
[Filecoin](https://www.filecoin.com/) to store data for much less. There's no
Block Device interface to this yet, so it wouldn't be as simple as ZFS
`send/recv`. You'd lose the benefits of incremental snapshots. But it may be
possible to build a block device interface on top. Maybe with an [nbd-server](https://en.wikipedia.org/wiki/Network_block_device)?

## Extra

Bits and pieces that may be helpful if you try setting something similar up.

### Setting host key and Nix Configuration with UserData

NixOS on AWS has this undocumented nifty feature of setting the ssh host
key and a new `configuration.nix` file straight from the [UserData
field](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_UserData.html).
This lets you one, be sure that your SSH connection isn't being
[MITM](https://en.wikipedia.org/wiki/Man-in-the-middle_attack), and two, configure
the machine in a simple way. I use this feature to set the SSH host key and set
the machine up with ZFS and the the `lz4` compression package.


### Questions? Comments?
Email me if you set this system up. This is purposely not a tutorial, so you may
hit snags. If you think something could be clearer feel free to make an
[edit](https://github.com/marcopolo/marcopolo.github.io).


