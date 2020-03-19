# Functions related to module specs
{ lib
, callPackage
}:

with (callPackage ./modules.nix {});
with (callPackage ./package-spec.nix {});
with (callPackage ./lib.nix {});
with builtins;
with lib.debug;
rec {

    makeModuleSpec =
    modName:
    modImports:
    modFiles:
    modDirs:
    modBase:
    modDeps:
    modExts:
    modGhcOpts:
    { moduleName = modName;

      # local module imports, i.e. not part of an external dependency
      moduleImports = modImports;

      moduleFiles = modFiles;
      moduleDirectories = modDirs;
      moduleBase = modBase;
      moduleDependencies =
        if builtins.isList modDeps
        then modDeps
        else abort "module dependencies should be a list";
      moduleGhcOpts = modGhcOpts;
      moduleExtensions = modExts;
    };


    moduleSpecFold =
      { baseByModuleName
      , filesByModuleName
      , dirsByModuleName
      , depsByModuleName
      , extsByModuleName
      , ghcOptsByModuleName
      }:
      result:
    let
      modImportsNames = modName:
        lib.lists.filter
          (modName': ! builtins.isNull (baseByModuleName modName'))
          (listModuleImports baseByModuleName extsByModuleName modName);
    in
      # TODO: DFS instead of Fold
      { f = modName:
          { "${modName}" =
          makeModuleSpec
            modName
            (map (mn: result.${mn}) (modImportsNames modName))
            (filesByModuleName modName)
            (dirsByModuleName modName)
            (baseByModuleName modName)
            (depsByModuleName modName)
            (extsByModuleName modName)
            (ghcOptsByModuleName modName);
          };
        empty = {} ;
        reduce = a: b: a // b;
        elemLabel = lib.id;
        elemChildren = modImportsNames;
      };

/*
  # Returns a list of all modules in the module spec graph
  flattenModuleSpec = modSpec:
    [ modSpec ] ++
      ( lib.lists.concatMap flattenModuleSpec modSpec.moduleImports );
*/
  allTransitiveDeps = allTransitiveLists "moduleDependencies";
  allTransitiveGhcOpts = allTransitiveLists "moduleGhcOpts";
  allTransitiveExtensions = allTransitiveLists "moduleExtensions";
  allTransitiveDirectories = allTransitiveLists "moduleDirectories";
  allTransitiveImports = allTransitiveLists "moduleImports";

  allTransitiveLists = attr: modSpecs:
    lib.lists.unique
    (
    foldDAG
      { f = modSpec:
          lib.lists.foldl
            (x: y: x ++ [y])
            [] modSpec.${attr};
        empty = [];
        elemLabel = modSpec: modSpec.moduleName;
        reduce = a: b: a ++ b;
        elemChildren = modSpec: modSpec.moduleImports;
      }
      modSpecs
    )
      ;
/*
  # overrideDerivation doest not support functors yet.
  modSpecMapFromPackageSpec = pkgSpec: modPkgSpecAndBaseMemo: modName:
      let
        modImportsNames = modName:
         let result =
          lib.lists.filter
            (modName': ! builtins.isNull (baseByModuleName modName'))
            (listModuleImports baseByModuleName extsByModuleName modName); 
         in trace "imports for ${modName}: ${toString result}" result;
        baseByModuleName = modName:
          let res = (modPkgSpecAndBaseMemo ? "${modName}"); 
          in if res then modPkgSpecAndBaseMemo."${modName}".base else null;
        depsByModuleName = modName:
          let res = modPkgSpecAndBaseMemo ? "${modName}"; 
          in if res 
          then modPkgSpecAndBaseMemo."${modName}".packageSpec.packageDependencies modName 
          else (abort "asking dependencies for external module: ${modName}");
        extsByModuleName = modName:
          let res = modPkgSpecAndBaseMemo ? "${modName}"; 
          in if res 
          then modPkgSpecAndBaseMemo."${modName}".packageSpec.packageExtensions 
          else (abort "asking extensions for external module: ${modName}");
        ghcOptsByModuleName = modName:
          let res = modPkgSpecAndBaseMemo ? "${modName}"; 
          in if res 
          then modPkgSpecAndBaseMemo."${modName}".packageSpec.packageGhcOpts
          else (abort "asking ghc options for external module: ${modName}");
     in
      makeModuleSpec
        modName
        (modImportsNames modName)
        (pkgSpec.packageExtraFiles modName)
        (pkgSpec.packageExtraDirectories modName) 
        (baseByModuleName modName) 
        (depsByModuleName modName)
        (extsByModuleName modName)
        (ghcOptsByModuleName modName);
*/
  # to avoid repeated readDir to slow down, make a memo of pkgSpec and base per module.
  modSpecFoldFromPackageSpec' = pkgSpec: modPkgSpecAndBaseMemo:
      let
        baseByModuleName = modName:
          let res = (modPkgSpecAndBaseMemo ? "${modName}"); 
          in if res then modPkgSpecAndBaseMemo."${modName}".base else null;
        depsByModuleName = modName:
          let res = modPkgSpecAndBaseMemo ? "${modName}"; 
          in if res 
          then modPkgSpecAndBaseMemo."${modName}".packageSpec.packageDependencies modName 
          else (abort "asking dependencies for external module: ${modName}");
        extsByModuleName = modName:
          let res = modPkgSpecAndBaseMemo ? "${modName}"; 
          in if res 
          then modPkgSpecAndBaseMemo."${modName}".packageSpec.packageExtensions 
          else (abort "asking extensions for external module: ${modName}");
        ghcOptsByModuleName = modName:
          let res = modPkgSpecAndBaseMemo ? "${modName}"; 
          in if res 
          then modPkgSpecAndBaseMemo."${modName}".packageSpec.packageGhcOpts
          else (abort "asking ghc options for external module: ${modName}");
     in
        moduleSpecFold
          { baseByModuleName = baseByModuleName;
            filesByModuleName = pkgSpec.packageExtraFiles;
            dirsByModuleName = pkgSpec.packageExtraDirectories;
            depsByModuleName = depsByModuleName;
            extsByModuleName = extsByModuleName;
            ghcOptsByModuleName = ghcOptsByModuleName;
          };

  # Takes a package spec and returns (modSpecs -> Fold)
  modSpecFoldFromPackageSpec = pkgSpec:
      let
        baseByModuleName = modName:
          let res = pkgSpecAndBaseByModuleName pkgSpec modName;
          in if res == null then null else res.base;
        depsByModuleName = modName:
          (pkgSpecByModuleName
            pkgSpec
            (abort "asking dependencies for external module: ${modName}")
            modName).packageDependencies
            modName
          ;
        extsByModuleName = modName:
          (pkgSpecByModuleName
            pkgSpec
            (abort "asking extensions for external module: ${modName}")
            modName).packageExtensions;
        ghcOptsByModuleName = modName:
          (pkgSpecByModuleName
            pkgSpec
            (abort "asking ghc options for external module: ${modName}")
            modName).packageGhcOpts;
      in
        moduleSpecFold
          { baseByModuleName = baseByModuleName;
            filesByModuleName = pkgSpec.packageExtraFiles;
            dirsByModuleName = pkgSpec.packageExtraDirectories;
            depsByModuleName = depsByModuleName;
            extsByModuleName = extsByModuleName;
            ghcOptsByModuleName = ghcOptsByModuleName;
          };
}
