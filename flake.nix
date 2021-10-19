{
  description = "Tezos NixOS development environment using flakes";

  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs-unstable, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs-unstable.legacyPackages.${system};
      in {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            autoconf
            rsync
            git
            m4
            patch
            unzip
            wget
            pkg-config
            gcc
            gmp
            libev
            hidapi
            libffi
            jq
            zlib
            opam
          ];
        };
      });
}
