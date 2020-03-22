# This is the entry point of the library, and badly needs documentation.
# TODO: currently single out derivations prepend the PWD to the path
# TODO: make sure that filters for "base" are airtight
# TODO: document the sh*t out of these functions
{ pkgs
, ghc-version ? "ghc864"
, ghcWithPackages ? pkgs.haskell.packages.${ghc-version}.ghcWithPackages
, haskellPackages ? pkgs.haskell.packages.${ghc-version}
, buildInputs ? []
}:

with pkgs;

with (callPackage ./build.nix {customBuildInputs = buildInputs; });
with (callPackage ./files.nix {});
with (callPackage ./ghci.nix {});
with (callPackage ./lib.nix {});
with (callPackage ./modules.nix {});
with (callPackage ./module-spec.nix {});
with (callPackage ./package-spec.nix {});
with (callPackage ./pkgSpecAndBaseMemo.nix {});
with (callPackage ./dag.nix {});
with builtins;
with lib.debug;
with lib.attrsets;
with rec
{
  hpack = callPackage ./hpack.nix { inherit pkgDescriptionsFromPath; };

  # Derivation that creates a binary in a 'bin' folder.
  executable = packageFile:
    let
      specs = specsFromPackageFile packageFile;
      spec =
        if pkgs.lib.length specs == 1
        then pkgs.lib.head specs
        else abort "'executable' can only be called on a single executable";
      exe =
        if spec.packageIsExe
        then buildAsExecutable spec
        else abort "'executable' called on a library";
    in exe.out;


  # Build a package spec as resp. a library and an executable

  buildAsLibrary = pkgSpec:
    buildLibrary ghcWith (libraryModSpecs pkgSpec);

  buildAsExecutable = pkgSpec:
    let
      moduleSpec = executableMainModSpec pkgSpec;
      name = pkgSpec.packageName;
      drv = linkMainModule { inherit moduleSpec name ghcWith; };
    in
      { out = drv.out;
        exe_path = "${drv.out}/${drv.relExePath}";
      };

  ghcWith = deps: ghcWithPackages
    (ps: map (p: ps.${p}) deps);

  # Normal build (libs, exes)

  inferBuild = packageFile:
    mkPackages (specsFromPackageFile packageFile);


  mkPackages = pkgSpecs: writeText "build.json"
    ( builtins.toJSON
      ( builtins.map
          (pkgSpec:
            if pkgSpec.packageIsExe
            then
              { build_type = "executable";
                result = buildAsExecutable pkgSpec;
              }
            else
              { build_type = "library";
                result = buildAsLibrary pkgSpec;
              }
          ) pkgSpecs
      )
    );

  # GHCi build (libs, exes)

  inferGhci = packageFile:
    mkPackagesGhci (specsFromPackageFile packageFile);

  mkPackagesGhci = pkgSpecs: writeText "hpack-ghci-json"
    ( builtins.toJSON (
        builtins.map
          (pkgSpec:
            let
              drv =
                if pkgSpec.packageIsExe
                then ghciWithMain ghcWith (executableMainModSpec pkgSpec)
                else ghciWithModules ghcWith (libraryModSpecs pkgSpec)
                ;
            in
            { build_type = "ghci"; # TODO: need to record the name somewhere
              result = "${drv.out}/bin/ghci-with-files";
              }
          ) pkgSpecs
    ));

  # How to build resp. libraries and executables
  libraryModSpecs = pkgSpec:
    let
      modPkgSpecAndBase = modPkgSpecAndBaseMemoFromPkgSpecs (lib.lists.unique (flattenPackages pkgSpec));
      moduleSpecFold' = modSpecFoldFromPackageSpec' pkgSpec modPkgSpecAndBase;
      modNames = builtins.trace "entering modNames" attrNames modPkgSpecAndBase; 
      fld = builtins.trace "entering moduleSpecFold'" (moduleSpecFold' modSpecs');
      #modSpecs' = builtins.trace "evaluating modSpecs'" (foldDAG fld modNames);
      moduleSpecMap = modSpecMapFromPackageSpec pkgSpec modPkgSpecAndBase;
      modSpecs' = listToAttrs (map (x: nameValuePair x (moduleSpecMap x)) modNames);
      importsDAG = mapAttrs (n: v: dagEntryAfter v.moduleImports v) modSpecs';
      sortedResult = trace (dagTopoSort importsDAG) (dagTopoSort importsDAG);
      sortedModSpecs = if sortedResult ? result 
                       then listToAttrs (map (x: nameValuePair x.name x.data) sortedResult.result)
                       else abort "cycles detected: ${toString sortedResult.cycle}";
      transAttrsAdded = mapAttrs (n: v: v // { moduleAllTransDep = allTransitiveDeps (sortedModSpecs.${modName});
                                               moduleAllTransImports = allTransitiveImports (sortedModSpecs.${modName});} ) sortedModSpecs;
    in transAttrsAdded;
/*
  libraryModSpecs = pkgSpec:
    let
      moduleSpecFold' = builtins.trace "entering modSpecFoldFromPackageSec" (modSpecFoldFromPackageSpec pkgSpec);
      modNames = builtins.trace "entering modNames" (pkgs.lib.concatMap listModulesInDir (lib.debug.traceValSeq pkgSpec.packageSourceDirs));
      fld = builtins.trace "entering moduleSpecFold'" (moduleSpecFold' modSpecs');
      modSpecs' = builtins.trace "evaluating modSpecs'" (foldDAG fld modNames);
      modSpecs = builtins.trace "evaluating modSpec" (builtins.attrValues modSpecs');
    in modSpecs;
*/
  executableMainModSpec = pkgSpec:
    let
      modPkgSpecAndBase = modPkgSpecAndBaseMemoFromPkgSpecs (allTransitivePackages pkgSpec);
      moduleSpecFold' = modSpecFoldFromPackageSpec' pkgSpec modPkgSpecAndBase;
      moduleSpecMap = modSpecMapFromPackageSpec pkgSpec modPkgSpecAndBase;
      modNames = traceValSeq (attrNames modPkgSpecAndBase); 
      mainModName = pkgSpec.packageMain;
      mainModSpec =
        let
          fld = moduleSpecFold' modSpecs;
          modSpecs = listToAttrs (map (x: nameValuePair x (moduleSpecMap x)) modNames); #in order to detect cycles, we need all specs.
          importsDAG = mapAttrs (n: v: dagEntryAfter v.moduleImports v) modSpecs;
          sortedResult = dagTopoSort importsDAG;
          sortedModSpecs = if sortedResult ? result 
                           then map (x: x.data) (trace sortedResult.result sortedResult.result)
                           else abort "cycles detected: ${toString sortedResult.cycle}";
 
          mainImportsDAG = foldDAG 
            { f = mod:
                  { ${mod.moduleName} = dagEntryAfter mod.moduleImports mod; };
              elemLabel = mod: mod.moduleName;
              elemChildren = mod: mod.moduleImports;
              reduce = a: b: a // b;
              empty = {};
              purpose = "buildImportsDAG from mainModSpec";
            }
            [sortedModSpecs.${mainModName}];
          mainSortedResult = dagTopoSort mainImportsDAG;
          mainSortedModSpecs = if traceValSeq (mainSortedResult ? result)
                           then (map (x: x.data) mainSortedResult.result) 
                           else abort "cycles detected: ${toString mainSortedResult.cycle}";
          transAttrsAdded = mapAttrs (n: v: v // { moduleTransDep = allTransitiveDeps (sortedModSpecs.${modName});
                                                   moduleTransImports = allTransitiveImports (sortedModSpecs.${modName});} ) mainSortedModSpecs;
        in transAttrsAdded.${mainModName} // { mainSortedModSpecs = transAttrsAdded; };
    in mainModSpec; 


  # Get a list of package descriptions from a path
  # This can be
  #  - a path, relative or absolute, to a directory that contains either a
  #     package.yaml or a package.nix
  #  - a path, relative or absolute, to a file with either .nix or .yaml or
  #     .yml extension

  pkgDescriptionsFromPath =
    with rec
    {
      pkgDescriptionsFromFile = packageFile:
        with rec
        {
          basename = builtins.baseNameOf packageFile;
          components = pkgs.lib.strings.splitString "." basename;
          ext =
            if pkgs.lib.length components <= 1
            then abort ("File " ++ packageFile ++ " does not have an extension")
            else pkgs.lib.last components;
          fromNix = [(import packageFile)];
          fromHPack = hpack.pkgDescriptionsFromHPack packageFile;
        };
        if ext == "nix" then fromNix
        else if ext == "yaml" then fromHPack
        else if ext == "yml" then fromHPack
        else abort ("Unknown extension " ++ ext ++ " of file " ++ packagePath);
      pkgDescriptionsFromDir = packageDir:
        with rec
        { dirContent = builtins.readDir packageDir;
          hasPackageYaml = builtins.hasAttr "package.yaml" dirContent;
          hasPackageNix = builtins.hasAttr "package.nix" dirContent;
        };
        if hasPackageYaml && hasPackageNix
          then abort "Found both package.yaml and package.nix in ${packageDir}"
        else if ! (hasPackageYaml || hasPackageNix)
          then abort "Couldn't find package.yaml or package.nix in ${packageDir}"
        else if hasPackageYaml
          then pkgDescriptionsFromFile
            "${builtins.toString packageDir}/package.yaml"
        else  pkgDescriptionsFromFile
            "${builtins.toString packageDir}/package.nix";
    };

    packagePath:
    with { pathType = pkgs.lib.pathType packagePath ; } ;
    if pathType == "directory"
      then pkgDescriptionsFromDir packagePath
    else if pathType == "regular"
      then pkgDescriptionsFromFile packagePath
    else abort "Don't know how to load package path of type ${pathType}";

    specsFromPackageFile = packagePath:
      map mkPackageSpec (pkgDescriptionsFromPath packagePath);

    buildHoogle = packagePath:
      let
        concatUnion = lists: 
          let
            sets = map (l: pkgs.lib.genAttrs l (_: null)) lists;
            union = pkgs.lib.foldAttrs (n: a: null) {} sets;
          in
            builtins.attrNames union;
        allDeps = concatUnion (map (spec: spec.packageDependencies {}) (specsFromPackageFile packagePath));
        drv = haskellPackages.hoogleLocal { packages = map (p: haskellPackages.${p}) allDeps; };
      in 
      writeText "hoogle-json"
      ( builtins.toJSON
          { build_type = "hoogle";
            result = {
              exe_path = "${drv.out}/bin/hoogle";
            };
          }
      );

};
{
  inherit
  inferBuild
  inferGhci
  buildAsExecutable
  buildAsLibrary
  executable
  buildHoogle
  ;
}
