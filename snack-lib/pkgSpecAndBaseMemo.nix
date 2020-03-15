{lib}: 
with builtins;
with lib.attrsets;
with lib.strings;
with lib.lists;
let 
   pipe = val: functions:
      let reverseApply = x: f: f x;
      in builtins.foldl' reverseApply val functions;
    onlyDir = base: path: value: 
      if value == "directory" 
      then exploreR base path
      else value;
    exploreR = base: path: 
    let explored = readDir further;
        further = base + ("/" + (concatStrings path));
        noDirsAnymore = (filterAttrsRecursive (n: v: v == "directory") explored) == {};
    in 
      if noDirsAnymore then explored
      else mapAttrsRecursive (onlyDir further) explored;
    isHaskellModuleFile = f:
      ! (isNull (match "[a-zA-Z].*[.]hs$" (baseNameOf f)));
    pathToModuleName = path:
      removeSuffix ".hs"
        (concatStringsSep "." path);
in
rec {
  #  applyEveryLeaf = f: set: mapAttrsRecursiveCond (as: true) (n: v: f v) set; # == mapAttrsRecursive
  #may stack overflow while infinite recursion
  topPkgSpec2 =   
    { packageIsExe = false; 
      packageName = "snack-hello";
      packageSourceDirs = [./src ./app];
      packageGhcOpts = [];
      packageExtensions = [];
      packageDependencies = [];
      packageExtraFiles = [];
      packageExtraDirectories = [];
      packagePackages = []; 
    };

  topPkgSpec1 =   
    { packageIsExe = true; 
      packageName = "snack";
      packageSourceDirs = [/root/snack/bin];
      packageGhcOpts = [];
      packageExtensions = [];
      packageDependencies = [];
      packageExtraFiles = [];
      packageExtraDirectories = [];
      packagePackages = []; 
    };
  getFileTree = path: mapAttrsRecursive (onlyDir path) (readDir path);
  # isAttrs v is needed here to filter recursively
  leaveHaskellModuleFile = set: filterAttrsRecursive (n: v: isHaskellModuleFile n || isAttrs v) set;
  removeEmptyDirConvergely = set: lib.converge (filterAttrsRecursive (n: v: v!={})) set;
  collectModule = set: collect (s: typeOf s != "set") (mapAttrsRecursive (n: v: pathToModuleName n) set);
  mkInfo = pkgSpec: dir: pipe dir [getFileTree leaveHaskellModuleFile removeEmptyDirConvergely collectModule (mkBaseMemo pkgSpec dir)]; 
  mkBaseMemo = pkgSpec: base: mods:
    listToAttrs (map (mod: nameValuePair mod base ) mods);
  mkPkgSpecMemo = pkgSpec: mods:
    listToAttrs (map (mod: nameValuePair mod pkgSpec ) mods);
  zipKeepExactOne = zipAttrsWith (n: vs: if (lib.length vs) == 1 then lib.lists.head vs else abort ("Module " + n + " is not found exactly once: " + toString (lib.length vs)));
  merge = pkgSpecMemo: baseMemo: zipAttrsWith (name: vs: {packageSpec = head vs; base = last vs;}) [pkgSpecMemo baseMemo]; 

  modBaseMemoFromPkgSpec = pkgSpec: 
    zipKeepExactOne (map (mkInfo pkgSpec) pkgSpec.packageSourceDirs);
  modPkgSpecAndBaseMemoFromPkgSpecs = pkgSpecs:
  zipKeepExactOne (map (pkgSpec: let baseMemo = modBaseMemoFromPkgSpec pkgSpec;
                                     mods = attrNames baseMemo;
                                     pkgSpecMemo = mkPkgSpecMemo pkgSpec mods; 
                                 in  merge pkgSpecMemo baseMemo) pkgSpecs);   
  modulesInPkgSpec = pkgSpec: attrNames (modBaseMemoFromPkgSpec pkgSpec);
}
