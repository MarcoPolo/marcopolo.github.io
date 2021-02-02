{
  description = "marcopolo.io";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/release-20.09";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
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
      );
}
