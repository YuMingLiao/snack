rec {
# If you only wish to change the version of GHC being used, set
# `ghc-version`. The following versions are currently available:
#  * ghc7103
#  * ghc7103Binary
#  * ghc802
#  * ghc821Binary
#  * ghc822
#  * ghc841
#  * ghc842
#  * ghc864
#  * ghcHEAD
#  * ghcjs
#  * ghcjsHEAD
#  * integer-simple
# NOTE: not all versions have been tested with snack.
#  ghc-version = "ghc865";
# Alternatively you can provide you own `ghcWithPackages`, which should have
# the same structure as that provided by
# `pkgs.haskell.packages.<version>.ghcWithPackages:
  ghcWithPackages = pkgs.haskell.packages.ghc924.ghcWithPackages;
# Finally you can provide your own set of Nix packages, which should evaluate
# to an attribute set:
  pkgs = (import <nixpkgs> {}).pkgsMusl;
}
