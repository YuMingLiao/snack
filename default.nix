let  overlay = _: pkgs:
      { 
        packages = pkgs.callPackages nix/packages.nix {};
      };
in
with { pkgs = import <nixpkgs> {overlays = [overlay];}; };
{
  inherit (pkgs.packages)
    snack-lib
    snack-exe
    ;
}
