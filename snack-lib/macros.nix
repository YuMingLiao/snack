{ lib
, callPackage
, runCommand
, glibcLocales
, haskellPackages
}:
{ pkgs
, ghc-version ? "ghc864"
, ghcWithPackages ? pkgs.haskell.packages.${ghc-version}.ghcWithPackages
, haskellPackages ? pkgs.haskell.packages.${ghc-version}
, buildInputs ? []
}:

