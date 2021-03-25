{
  description = "marcopolo.io";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/release-20.09";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    (flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          devShell = pkgs.mkShell {
            buildInputs = [ pkgs.zola ];
          };
          defaultPackage = pkgs.stdenv.mkDerivation {
            name = "marcopolo-blog-1.0.0";
            buildInputs = [ pkgs.zola ];
            src = ./.;
            installPhase = "mkdir $out; zola build; cp -r public/* $out/";
          };
        }
      )
    ) // {
      nixosConfigurations = {
        small-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ({ lib, pkgs, modulesPath, ... }: {
              imports = [
                (modulesPath + "/virtualisation/qemu-vm.nix")
              ];
              users.mutableUsers = false;
              security.sudo.wheelNeedsPassword = false;
              virtualisation = {
                graphics = false;
                qemu.networkingOptions = [
                  # We need to re-define our usermode network driver
                  # since we are overriding the default value.
                  "-net nic,netdev=user.0,model=virtio,"
                  # Then we can use qemu's hostfwd option to forward ports.
                  "-netdev user,hostfwd=tcp::8222-:22,id=user.0\${QEMU_NET_OPTS:+,$QEMU_NET_OPTS}"
                ];
              };
              services.openssh.enable = true;
              environment.systemPackages = with pkgs; [ git wget vim zsh htop ];

              users.users.root = {
                password = "root";
              };
            })
          ];
        };
      };
    };
}
