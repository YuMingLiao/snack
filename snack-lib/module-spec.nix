# Functions related to module specs
{ lib
, callPackage
}:

with (callPackage ./modules.nix {});
with (callPackage ./package-spec.nix {});
with (callPackage ./lib.nix {});
with builtins;
with lib.debug;
with lib.lists;
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
    modAllTransDeps:
    modAllTransImports:
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
      moduleAllTransDeps = modAllTransDeps;
      moduleAllTransImports = modAllTransImports;
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

#  allTransitiveDeps = allTransitiveLists "moduleDependencies";
  allTransitiveGhcOpts = allTransitiveLists "moduleGhcOpts";
  allTransitiveExtensions = allTransitiveLists "moduleExtensions";
  allTransitiveDirectories = allTransitiveLists "moduleDirectories";
#  allTransitiveImports = allTransitiveLists "moduleImports";


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
        purpose = "allTransitive ${attr}";
      }
      modSpecs
    )
      ;

  allTransitiveDeps = topModSpec: lib.lists.unique (topModSpec.moduleDependencies ++ concatMap (x: x.moduleAllTransDeps) topModSpec.moduleImports);
  allTransitiveImports = topModSpec: lib.lists.unique (topModSpec.moduleImports ++ concatMap (x: x.moduleAllTransImports) topModSpec.moduleImports);



  modSpecMapFromPackageSpec = pkgSpec: modPkgSpecAndBaseMemo: modName:
      let
        moduleSpecMap = modSpecMapFromPackageSpec pkgSpec modPkgSpecAndBaseMemo;
        modImportsNames = modName:
          lib.lists.filter
            (modName': ! builtins.isNull (baseByModuleName modName'))
            (listModuleImports baseByModuleName extsByModuleName modName); 
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
        allTransDepByModuleName = modName:
          let res = modPkgSpecAndBaseMemo ? "${modName}"; 
          in if res 
          then allTransitiveDeps (moduleSpecMap modName) 
          else (abort "asking all transitive dependencies for external module: ${modName}");
        allTransImportsByModuleName = modName:
          let res = modPkgSpecAndBaseMemo ? "${modName}"; 
          in if res 
          then allTransitiveImports (moduleSpecMap modName)
          else (abort "asking all transitive imports for external module: ${modName}");
 
     in
      makeModuleSpec
        modName
        (map moduleSpecMap (modImportsNames modName))
        (pkgSpec.packageExtraFiles modName)
        (pkgSpec.packageExtraDirectories modName) 
        (baseByModuleName modName) 
        (depsByModuleName modName)
        (extsByModuleName modName)
        (ghcOptsByModuleName modName)
        (allTransDepByModuleName modName)
        (allTransImportsByModuleName modName);

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
