{ lib }:
with lib.lists;
with lib.attrsets;
with builtins;
with lib.strings;
with lib;
rec {
  names = ["a" "b" "c"];

  #{ a = { moduleName = "a"; }; b = { moduleName = "b"; }; c = { moduleName = "c"; }; }   
  specs = listToAttrs (map (x: nameValuePair x { moduleName = x; }) names);

  addAttrBy = name: f: attr: sets: mapAttrs (n: v: addAttr name (f v.${attr}) v) sets;
  addAttr = name: value: set: set // { ${name} = value; }; 
}
