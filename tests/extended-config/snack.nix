rec {
  pkgs = import <nixpkgs> {};
  ghcWithPackages = pkgs.haskellPackages.ghcWithPackages;
}
