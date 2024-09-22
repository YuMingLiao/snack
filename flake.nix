{
  inputs = {
#    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
#    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ overlay ];
        overlay = prev: pkgs: {
          packages = pkgs.callPackages nix/packages.nix { };
        };

        pkgs = import nixpkgs { inherit system overlays; };
      in with pkgs; {
        devShells.default = import ./shell.nix { inherit pkgs; };
        checks = {
          my-check = import ./tests/tests.nix { inherit pkgs; };
        };
        pkgs = pkgs;
      });
}
