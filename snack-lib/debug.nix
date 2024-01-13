let
  mn = (import <nixpkgs> {}).callPackage /root/snack/snack-lib/modules.nix {};
  de = (import <nixpkgs> {}).callPackage /root/snack/snack-lib/default.nix {};
  ms = (import <nixpkgs> {}).callPackage /root/snack/snack-lib/module-spec.nix {};
in
  mn // de // ms 
