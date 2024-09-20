{ pkgs ? import <nixpkgs> {}}:
with pkgs;
let
  any-paths = derivation {
    name = "any-paths";
    builder = "${bash}/bin/bash";
    src = ./any-paths;
    buildInputs = [ packages.snack-exe ];
    args = [ any-paths/test ];
    system = builtins.currentSystem;
  };
in any-paths
