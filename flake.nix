{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs-19-03.url = "https://github.com/NixOS/nixpkgs/archive/80bda4933272f7e244dc9702f39d18433988cdd0.tar.gz";
    nixpkgs-19-03.flake = false;
  };
  outputs = { self, nixpkgs, flake-utils, nixpkgs-19-03 }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ overlay ];
        overlay = _: pkgs: {
          packages = pkgs.callPackages nix/packages.nix { };
          nix = (import nixpkgs-19-03 {}).nix;
        };

        pkgs = import nixpkgs { inherit system overlays; };
      in with pkgs; {
        devShells.default = import ./shell.nix { inherit pkgs; };
        checks = {
          # my-check = import ./tests/tests.nix { inherit pkgs; };
        };

      });
}
