{ pkgs ? import <nixpkgs> {}}:
with pkgs;
let
  any-paths = stdenv.mkDerivation rec {
    name = "any-paths";
    src = ./any-paths;
    builder = ./any-paths/test;
    nativeBuildInputs = [ packages.snack-exe coreutils nix];
  }; 
in any-paths

# failed because testing snack in nix would be a recursive nix.
