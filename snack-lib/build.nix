{ runCommand
, lib
, callPackage
, stdenv
, rsync
, symlinkJoin
}:

with (callPackage ./modules.nix {});
with (callPackage ./lib.nix {});
with (callPackage ./module-spec.nix {});
with lib.attrsets;
with lib.strings;
with builtins;
rec {

  # Returns an attribute set where the keys are all the built module names and
  # the values are the paths to the object files.
  # mainModSpec: a "main" module
  buildMain = ghcWith: mainModSpec:
    let traversed = buildModulesRec ghcWith {} mainModSpec.moduleImports;
        builtDeps = attrValues (mapAttrs (n: v: removeSuffix "${moduleToObject n}" v) traversed);
        objList = map (x: traversed.${x.moduleName}) mainModSpec.moduleImports;
    in
      # XXX: the main modules need special handling regarding the object name
      traversed // { "${mainModSpec.moduleName}" =
        "${buildModule ghcWith mainModSpec builtDeps objList}/Main.o";};

  # returns a attrset where the keys are the module names and the values are
  # the modules' object file path
  buildLibrary = ghcWith: modSpecs:
    trace "buildLibrary" (buildModulesRec ghcWith {} modSpecs);

  linkMainModule =
      { ghcWith
      , moduleSpec # The module to build
      , name # The name to give the executable
      }:
    let
      objAttrs = buildMain ghcWith moduleSpec;
      objList = lib.attrsets.mapAttrsToList (x: y: y) objAttrs;
      deps = allTransitiveDeps [moduleSpec];
      ghc = ghcWith deps;
      ghcOptsArgs = lib.strings.escapeShellArgs moduleSpec.moduleGhcOpts;
      packageList = map (p: "-package ${p}") deps;
      relExePath = "bin/${name}";
      drv = runCommand name {}
        ''
          mkdir -p $out/bin
          echo "trace: ghc ${lib.strings.escapeShellArgs objList}"

          ${ghc}/bin/ghc \
            ${lib.strings.escapeShellArgs packageList} \
            ${lib.strings.escapeShellArgs objList} \
            ${ghcOptsArgs} \
            -o $out/${relExePath}
        '';
    in
      {
        out = drv;
        relExePath = relExePath;
      };

  # Build the given modules (recursively) using the given accumulator to keep
  # track of which modules have been built already
  # XXX: doesn't work if several modules in the DAG have the same name
  buildModulesRec = ghcWith: empty: modSpecs:
    dfsDAG
    { f = mod: traversed: 
          let builtDeps = map (x: removeSuffix "${moduleToObject x.moduleName}" traversed.${x.moduleName} ) (allTransitiveImports [mod]);
              objList = map (x: traversed.${x.moduleName}) mod.moduleImports;
          in 
          # trace "f ${mod.moduleName} ${toString (attrNames traversed)}"
          { "${mod.moduleName}" =
            # need to give it imported modules's obj info.
            "${buildModule ghcWith mod builtDeps objList}/${moduleToObject mod.moduleName}";
          };
        elemLabel = mod: mod.moduleName;
        elemChildren = mod: mod.moduleImports;
        reduce = a: b: a // b;
        empty = empty;
    }
    modSpecs;

  buildModule = ghcWith: modSpec: builtDeps: objList:
    let
#      objAttrs = lib.foldl (a: b: a // b) {} (map (mod: {"${mod.moduleName}" = "${buildModule ghcWith mod}/${moduleToObject mod.moduleName}";}) modSpec.moduleImports);
#      objList = lib.attrsets.mapAttrsToList (x: y: y) objAttrs;
      packageList = map (p: "-package ${p}") deps;
      ghc = ghcWith deps;
      deps = allTransitiveDeps [modSpec];
      exts = modSpec.moduleExtensions;
      ghcOpts = modSpec.moduleGhcOpts ++ (map (x: "-X${x}") exts); #++ (if elem "CPP" exts then ["-optP-include -optPcabal_macros.h"] else []);
      ghcOptsArgs = lib.strings.escapeShellArgs ghcOpts;
      objectName = modSpec.moduleName;
      #builtDeps = map (buildModule ghcWith) (allTransitiveImports [modSpec]);
      #depsDirs = map (x: x + "/") builtDeps;
      base = modSpec.moduleBase;
      makeSymtree =
        if lib.lists.length builtDeps >= 1
        # TODO: symlink instead of copy
        then "rsync -r ${lib.strings.escapeShellArgs builtDeps} ."
        else "";
      makeSymModule =
        # TODO: symlink instead of copy
        "rsync -r ${singleOutModule base modSpec.moduleName}/ .";
      pred = file: path: type:
        let
          topLevel = (builtins.toString base) + "/";
          actual = (lib.strings.removePrefix topLevel path);
          expected = file;
      in
        (expected == actual) ||
        (type == "directory" && (lib.strings.hasPrefix actual expected));

      extraFiles = builtins.filterSource
        (p: t:
          lib.lists.length
            (
            let
              topLevel = (builtins.toString base) + "/";
              actual = lib.strings.removePrefix topLevel p;
            in
              lib.filter (expected:
                (expected == actual) ||
                (t == "directory" && (lib.strings.hasPrefix actual expected))
                )
                modSpec.moduleFiles
            ) >= 1
        ) base;
    in stdenv.mkDerivation
    { name = objectName;
      src = symlinkJoin
        { name = "extra-files";
          paths = [ extraFiles ] ++ modSpec.moduleDirectories;
        };
      phases =
        [ "unpackPhase" "buildPhase" ];

      imports = map (mmm: mmm.moduleName) modSpec.moduleImports;
      buildPhase =
        ''
          echo "Building module ${modSpec.moduleName}"
          echo "Local imports are:"
          for foo in $imports; do
            echo " - $foo"
          done

          mkdir -p $out
          echo "Creating dependencies symtree for module ${modSpec.moduleName}"
          ${makeSymtree}
          echo "Creating module symlink for module ${modSpec.moduleName}"
          ${makeSymModule}
          echo "Compiling module ${modSpec.moduleName}"
          # Set a tmpdir we have control over, otherwise GHC fails, not sure why
          mkdir -p tmp
          echo "trace: buildModule: ghc 
                ${lib.strings.escapeShellArgs objList} \
                -tmpdir tmp/ ${moduleToFile modSpec.moduleName} -c \
                -outputdir $out \
                ${ghcOptsArgs} \
                2>&1"
          ghc ${lib.strings.escapeShellArgs packageList} \
            ${lib.strings.escapeShellArgs objList} \
            -tmpdir tmp/ ${moduleToFile modSpec.moduleName} -c \
            -outputdir $out \
            ${ghcOptsArgs} \
            2>&1

          ls $out
          echo "Done building module ${modSpec.moduleName}"
        '';

      buildInputs =
        [ ghc
          rsync
        ];
    };
}
