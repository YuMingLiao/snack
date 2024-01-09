# Functions related to module specs
{ lib, callPackage }:

with (callPackage ./modules.nix { });
with (callPackage ./package-spec.nix { });
with (callPackage ./lib.nix { });
with builtins; rec {
  makeModuleSpec =
    modName: modImports: modFiles: modDirs: modBase: modDeps: modExts: modGhcOpts: {
      moduleName = modName;

      # local module imports, i.e. not part of an external dependency
      moduleImports = modImports;

      moduleFiles = modFiles;
      moduleDirectories = modDirs;
      moduleBase = modBase;
      moduleDependencies = if builtins.isList modDeps then
        modDeps
      else
        abort "module dependencies should be a list";
      moduleGhcOpts = modGhcOpts;
      moduleExtensions = modExts;
    };

  # use by-module-name functions to create a Fold 
  moduleSpecFold = { baseByModuleName, filesByModuleName, dirsByModuleName
    , depsByModuleName, extsByModuleName, ghcOptsByModuleName }:
    let
      importedModules = modName: listModuleImports baseByModuleName filesByModuleName dirsByModuleName depsByModuleName extsByModuleName ghcOptsByModuleName modName;
      modImportsNames = modName:
        lib.lists.filter
        (modName': !builtins.isNull (baseByModuleName modName')) (importedModules modName);
      modExternalImportsNames = modName: lib.lists.filter (modName': builtins.isNull (baseByModuleName modName')) (importedModules modName);
      externalDepsByImports = modName: 
      (lib.lists.remove "base" 
      (lib.lists.remove "" 
      (lib.lists.unique 
      (map (findDep (depsByModuleName modName)) (modExternalImportsNames modName))))) ++ depsByModuleName modName; #still needs customized deps
    in {
      # make a module spec so that a module spec graph can be created. 
      f = modName: traversedModSpecs: {
        "${modName}" = makeModuleSpec modName
          (map (mn: traversedModSpecs.${mn}) (modImportsNames modName))
          (filesByModuleName modName) (dirsByModuleName modName)
          (baseByModuleName modName) (externalDepsByImports modName)  
          (extsByModuleName modName) (ghcOptsByModuleName modName);
      };
      empty = { };
      reduce = a: b: a // b;
      elemLabel = lib.id;
      elemChildren = modImportsNames;
    };

  # Returns a list of all modules in the module spec graph
  flattenModuleSpec = modSpec:
    [ modSpec ]
    ++ (lib.lists.concatMap flattenModuleSpec modSpec.moduleImports);

  allTransitiveDeps = allTransitiveLists "moduleDependencies";
  allTransitiveGhcOpts = allTransitiveLists "moduleGhcOpts";
  allTransitiveExtensions = allTransitiveLists "moduleExtensions";
  allTransitiveDirectories = allTransitiveLists "moduleDirectories";
  allTransitiveFiles = allTransitiveLists "moduleFiles";
  allTransitiveImports = allTransitiveLists "moduleImports";
  
  # use moduleImports in modSpec to find all elements in one transitive attribute.
  allTransitiveLists = attr: modSpecs:
    lib.lists.unique (dfsDAG {
      f = modSpec: _: lib.lists.foldl (x: y: x ++ [ y ]) [ ] modSpec.${attr};
      empty = [ ];
      elemLabel = modSpec: modSpec.moduleName;
      reduce = a: b: a ++ b;
      elemChildren = modSpec: modSpec.moduleImports;
    } modSpecs);

  # turn package spec into module specs
  modSpecFoldFromPackageSpec = pkgSpec:
    let
      baseByModuleName = modName:
        let res = pkgSpecAndBaseByModuleName pkgSpec modName;
        in if res == null then null else res.base;
      depsByModuleName = modName:
        (pkgSpecByModuleName pkgSpec
          (abort "asking dependencies for external module: ${modName}")
          modName).packageDependencies modName;
      extsByModuleName = modName:
        (pkgSpecByModuleName pkgSpec
          (abort "asking extensions for external module: ${modName}")
          modName).packageExtensions;
      ghcOptsByModuleName = modName:
        (pkgSpecByModuleName pkgSpec
          (abort "asking ghc options for external module: ${modName}")
          modName).packageGhcOpts modeName;
    in moduleSpecFold {
      baseByModuleName = baseByModuleName;
      filesByModuleName = pkgSpec.packageExtraFiles;
      dirsByModuleName = pkgSpec.packageExtraDirectories;
      depsByModuleName = depsByModuleName;
      extsByModuleName = extsByModuleName;
      ghcOptsByModuleName = ghcOptsByModuleName;
    };
  # a module spec Fold
  # memo, which is baseAndPkgSpecPerModName pkgSpec 
  modSpecDFS = pkgSpec: memo:
    let
      baseByModuleName = modName:
        if memo ? ${modName} == false then null else memo.${modName}.base;
      depsByModuleName = modName:
        if memo ? ${modName} == false then
          (abort "asking dependencies for external module: ${modName}")
        else
          memo.${modName}.pkgSpec.packageDependencies modName;
      extsByModuleName = modName:
        if memo ? ${modName} == false then
          (abort "asking extensions for external module: ${modName}")
        else
          memo.${modName}.pkgSpec.packageExtensions;
      ghcOptsByModuleName = modName:
        if memo ? ${modName} == false then
          (abort "asking ghc options for external module: ${modName}")
        else
          memo.${modName}.pkgSpec.packageGhcOpts modName;
    in moduleSpecFold {
      baseByModuleName = baseByModuleName;
      filesByModuleName = pkgSpec.packageExtraFiles;
      dirsByModuleName = pkgSpec.packageExtraDirectories;
      depsByModuleName = depsByModuleName;
      extsByModuleName = extsByModuleName;
      ghcOptsByModuleName = ghcOptsByModuleName;
    };

}
