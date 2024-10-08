{ runCommand, lib, callPackage, stdenv, symlinkJoin, xorg, pkgs}:

with (callPackage ./modules.nix { });
with (callPackage ./lib.nix { });
with (callPackage ./module-spec.nix { });
with lib.attrsets;
with lib.strings;
with builtins;
with lib.debug;
let lndir = xorg.lndir;
    rsync = pkgs.rsync;
in rec {

  # Returns an attribute set where the keys are all the built module names and
  # the values are the paths to the object files.
  # mainModSpec: a "main" module
  buildMain = ghcWith: mainModSpec:
    let
      traversed = buildModulesRec ghcWith { } mainModSpec.moduleImports;
      #TODO check if removeSuffix is useless
      builtDeps = attrValues (mapAttrs (n: v: removeSuffix "${moduleToObject n}" v) traversed);
      #objList = map (x: traversed.${x.moduleName}) mainModSpec.moduleImports;
      # XXX: the main modules need special handling regarding the object name
    in traversed // {
      "${mainModSpec.moduleName}" =
        "${buildModule ghcWith mainModSpec builtDeps}/Main.o";
    };

  # returns a attrset where the keys are the module names and the values are
  # the modules' object file path
  buildLibrary = ghcWith: modSpecs: buildModulesRec ghcWith { } modSpecs;

  linkMainModule = { ghcWith, moduleSpec # The module to build
    , name # The name to give the executable
    }:
    let
      objAttrs = buildMain ghcWith moduleSpec;
      #shareList = attrValues (mapAttrs (_: v: dirOf v) objAttrs);
      mainShare = attrValues (mapAttrs (_: v: dirOf v) (filterAttrs (_: v: baseNameOf v == "Main.o") objAttrs));
      objList = attrValues objAttrs;
      deps = allTransitiveDeps [ moduleSpec ];
      ghc = ghcWith deps;
      ghcOptsArgs = lib.strings.escapeShellArgs (moduleSpec.moduleGhcOpts ++ (if pkgs.stdenv.targetPlatform.isMusl then staticLinkingArgs else []));
      exts = moduleSpec.moduleExtensions;
      packageList = map (p: "-package ${p}") deps;
      relExePath = "bin/${name}";
      cbits = lib.lists.findFirst (x: baseNameOf x == "cbits") null
        moduleSpec.moduleDirectories;
      copyCBitsFiles = if cbits != null then "cp ${cbits}/* ." else "";
      linkCBitsCode = if cbits != null then "*.c" else "";
      staticLinkingArgs = [
            "-optl-static"
            "-L${pkgs.ncurses.override { enableStatic = true; }}/lib"
            "-L${pkgs.gmp6.override { withStatic = true; }}/lib"
            "-L${pkgs.zlib.static}/lib"
            "-L${pkgs.libffi.overrideAttrs (old: { dontDisableStatic = true; })}/lib"
          ];
      symlinkShare = if lib.lists.length mainShare >= 1 then ''
        for fromdir in ${
          lib.strings.escapeShellArgs mainShare
        }; 
        do 
          rsync -ar $fromdir/* $out/share 
        done''
      else
        "";

      src = symlinkJoin {
        name = "${name}-extra-files";
        paths = moduleSpec.moduleDirectories;
        __contentAddressed = true;
      };
 

        drv = runCommand name { buildInputs = [ lndir rsync]; } ''
        echo "Start linking Main Module...${moduleSpec.moduleName} to ${name}"
        mkdir -p $out/bin
        mkdir -p $out/share
        cp ${src}/* .
        ${ghc}/bin/ghc \
          ${lib.strings.escapeShellArgs packageList} \
          ${lib.strings.escapeShellArgs objList} \
          ${linkCBitsCode} \
          ${ghcOptsArgs} \
          -o $out/${relExePath}
        ${symlinkShare} 
      '';
    in {
      out = drv;
      relExePath = relExePath;
    };

  # Build the given modules (recursively) using the given accumulator to keep
  # track of which modules have been built already
  # XXX: doesn't work if several modules in the DAG have the same name
  buildModulesRec = ghcWith: empty: modSpecs:
    dfsDAG {
      f = mod: traversed:
        let
          builtDeps = map (x:
            removeSuffix "${moduleToObject x.moduleName}"
            traversed.${x.moduleName}) (allTransitiveImports [ mod ]);
        in {
          "${mod.moduleName}" =
            "${buildModule ghcWith mod builtDeps}/${
              moduleToObject mod.moduleName
            }";
        };
      elemLabel = mod: mod.moduleName;
      elemChildren = mod: mod.moduleImports;
      reduce = a: b: a // b;
      empty = empty;
    } modSpecs;

  buildModule = ghcWith: modSpec: builtDeps:
    let
      packageList = map (p: "-package ${p}") (lib.lists.remove "attoparsec" deps);
      ghc = ghcWith deps;
      deps = allTransitiveDeps [ modSpec ];
      exts = modSpec.moduleExtensions;
      ghcOpts = modSpec.moduleGhcOpts ++ (map (x: "-X${x}") exts);
      ghcOptsArgs = lib.strings.escapeShellArgs ghcOpts;
      objectName = modSpec.moduleName;
      base = modSpec.moduleBase;
      
      makeSymtree = if lib.lists.length builtDeps >= 1 then
        # TODO: ln .o here is not necessary.
        "for fromdir in ${
          lib.strings.escapeShellArgs builtDeps
        }; do lndir $fromdir . &> /dev/null ; done"
      else
        "";
      #seems ghc Main.o bring all lib.hie to main folder, causing duplication.
      makeHiToOut = if lib.lists.length builtDeps >= 1 then ''
        for fromdir in ${lib.strings.escapeShellArgs builtDeps}; 
        do
          rsync -ar --include="*/" --include="*.hi" --include="*.o" --include="*.hie" --exclude="*" . $out; 
        done''
      else
        "";

      makeSymModule =
        "lndir ${singleOutModule base modSpec.moduleName} . &> /dev/null;";
      pred = file: path: type:
        let
          topLevel = (builtins.toString base) + "/";
          actual = (lib.strings.removePrefix topLevel path);
          expected = file;
        in (expected == actual)
        || (type == "directory" && (lib.strings.hasPrefix actual expected));

      extraFiles = builtins.filterSource (p: t:
        lib.lists.length (let
          topLevel = (builtins.toString base) + "/";
          actual = lib.strings.removePrefix topLevel p;
        in lib.filter (expected:
          (expected == actual)
          || (t == "directory" && (lib.strings.hasPrefix actual expected)))
        modSpec.moduleFiles) >= 1) base;
    in stdenv.mkDerivation {
      name = objectName;
      src = symlinkJoin {
        name = "${objectName}-extra-files";
        paths = [ extraFiles ] ++ modSpec.moduleDirectories;
      };
      phases = [ "unpackPhase" "buildPhase" ];

      # echo "objList: ${lib.strings.concatStringsSep "\n"  objList}"
      # echo "builtDeps: \n  ${lib.strings.concatStringsSep "\n" builtDeps}"
      # echo "Creating dependencies symtree for module ${modSpec.moduleName}"
      # echo "Make hi to out"
      # echo "Creating module symlink for module ${modSpec.moduleName}"
      # echo "Compiling module ${modSpec.moduleName}: ${moduleToFilePath modSpec.moduleName}"
      # echo "Done building module ${modSpec.moduleName}"
      buildPhase = ''
        mkdir -p $out
        mkdir -p tmp
        echo "makeSymTree"
        ${makeSymtree}
        echo "makeSymModule"
        ${makeSymModule}
        echo "makeHiToOut"
        ${makeHiToOut}
        echo "compiling"
        ghc ${lib.strings.escapeShellArgs packageList} \
          -tmpdir tmp/ \
          ${moduleToFilePath modSpec.moduleName} -c\
          -outputdir $out/ \
          ${ghcOptsArgs} \
          2>&1
      '';

      #            ${lib.strings.escapeShellArgs objList} \
      buildInputs = [ ghc lndir rsync];
    };
}
