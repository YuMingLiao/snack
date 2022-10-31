{ lib, callPackage }:

with (callPackage ./modules.nix { });
with (callPackage ./lib.nix { });
with lib.attrsets;
with lib; rec {

  mkPackageSpec = packageDescr@{ src ? [ ], name ? null, main ? null
    , ghcOpts ? [ ], dependencies ? [ ], extensions ? [ ], extra-files ? [ ]
    , extra-directories ? [ ], packages ? [ ] }:
    with rec {
      isExe = !builtins.isNull main;
      pName = if isExe && builtins.isNull name then
        lib.strings.toLower main
      else
        if !builtins.isNull name then name else "unknown-package-name";
    }; {
      packageIsExe = !builtins.isNull main;
      packageName = pName;
      packageMain = main;
      packageSourceDirs = if builtins.isList src then src else [ src ];
      packageGhcOpts = mkPerModuleAttr ghcOpts;
      packageExtensions = extensions;
      packageDependencies = mkPerModuleAttr dependencies;

      # TODO: merge extra files and extra dirs together
      packageExtraFiles = mkPerModuleAttr extra-files;
      packageExtraDirectories = mkPerModuleAttr extra-directories;

      packagePackages = map mkPackageSpec packages;
    };

  mkPerModuleAttr = attr:
    if builtins.isList attr then
      (_: attr)
    else if builtins.isAttrs attr then
      (x: if builtins.hasAttr x attr then attr.${x} else [ ])
    else if builtins.isFunction attr then
      attr
    else
      abort "Unknown type for per module attributes: ${builtins.typeOf attr}";

  flattenPackages = topPkgSpec:
    [ topPkgSpec ]
    ++ lib.lists.concatMap (flattenPackages) topPkgSpec.packagePackages;

  # Traverses all transitive packages and returns the first package spec that
  # contains a module with given name. If none is found, returns the supplied
  # default value.
  pkgSpecAndBaseByModuleName = topPkgSpec: modName:
    let
      foo = pkgSpec:
        lib.findFirst (base: lib.lists.elem modName (listModulesInDir base))
        null pkgSpec.packageSourceDirs;
      bar = lib.concatMap (pkgSpec:
        let base = foo pkgSpec;
        in if base == null then [ ] else [{ inherit pkgSpec base; }])
        (flattenPackages topPkgSpec);
    in if lib.length bar <= 0 then
      null
    else if lib.length bar == 1 then
      lib.head bar
    else
      abort
      "Refusing to return base, module name was found more than once: ${modName}";

  pkgSpecByModuleName = topPkgSpec: def: modName:
    let res = pkgSpecAndBaseByModuleName topPkgSpec modName;
    in if res == null then def else res.pkgSpec;

  # Traverses all transitive packages and returns all the module specs in this topPkgSpec with base and pkg info.
  # contains a module with given name.
  # caveat: main candidate files in subdirectories can be seen in this attribute set. eq. set `main = "TutorialD.tutd"` in package.nix
  baseAndPkgSpecPerModName = topPkgSpec:
    dfsDAG {
      f = pkgSpec: _:
        mapAttrs' (name: base:
          nameValuePair name {
            base = base;
            pkgSpec = pkgSpec;
          }) (modNamesWithBaseFromPkgSpec pkgSpec);
      elemLabel = pkgSpec: pkgSpec.packageName;
      elemChildren = pkgSpec: pkgSpec.packagePackages;
      reduce = a: b: a // b;
      empty = { };
    } [ topPkgSpec ];

  modNamesWithBaseFromPkgSpec = pkgSpec:
    let reduce = a: b: a // b;
    in foldl reduce { } (map modNamesWithBaseInDir pkgSpec.packageSourceDirs);

}
