{ lib, nix-freeze-files ? (import <nixpkgs> {}).haskellPackages.nix-freeze-files, runCommand ? (import <nixpkgs> {}).runCommand}:
/*
let
  nix-freeze-files = import (builtins.fetchGit {
    url = https://github.com/YuMingLiao/nix-freeze-files;
    rev = "672d9a1c2e4574a448206d30062e0d1d687faecd";
  }) {};
in*/
with lib.attrsets;
with builtins;
with lib.lists;
with lib; rec {
  setAttrs = s: filterAttrs (n: v: isAttrs v) s;
  regularAttrs = s: filterAttrs (_: v: !(isAttrs v)) s;
  isEmpty = s: s == { };
  minus = s1: s2: removeAttrs s1 (attrNames s2);
  separate = s: mapAttrsToList (n: v: v) s;
  separatelyAddAttrPath = s:
    mapAttrsToList (n: v:
      mapAttrs' (inner_n: inner_v: nameValuePair (n + "/" + inner_n) inner_v) v)
    s;
  leaves = s:
    if isEmpty (setAttrs s) then
      s
    else
      (foldl' (a: b: a // b) (regularAttrs s)
        (map leaves (separate (setAttrs s))));
  flatten = s:
    if isEmpty (setAttrs s) then
      s
    else
      (foldl' (a: b: a // b) (regularAttrs s)
        (map flatten (separatelyAddAttrPath (setAttrs s))));
  replace = s: v: mapAttrs (_: _: v) s;
  frozen = src:
    import ("${runCommand ((baseNameOf src) + "-frozen") {
      inherit src;
      buildInputs = [ nix-freeze-files ];
    } "mkdir $out; nix-freeze-files -v $src -o $out;"}"+"/default.nix");
}
