{ makeWrapper, symlinkJoin, lib, callPackage, writeScriptBin }:

with (callPackage ./module-spec.nix {});
with (callPackage ./modules.nix {});
with builtins;
rec {

  # Write a new ghci executable that loads all the modules defined in the
  # module spec
  ghciWithMain = ghcWith: mainModSpec:
    let
      imports = allTransitiveImports [mainModSpec];
      modSpecs = [mainModSpec] ++ imports;
    in ghciWithModules ghcWith modSpecs;

  ghciWithModules = ghcWith: modSpecs:
    let
      exts = allTransitiveExtensions modSpecs;
      ghcOpts = allTransitiveGhcOpts modSpecs
      #  ++ (if elem "CPP" exts then ["-optP-include -optPcabal_macros.h"] else [])
        ++ (map (x: "-X${x}") exts) ++ (map (x: "-package ${x}") deps);
      deps = allTransitiveDeps modSpecs;
      ghc = ghcWith deps;
      ghciArgs = ghcOpts ++ absoluteModuleFiles;
      absoluteModuleFiles =
        map
          (mod:
            builtins.toString (mod.moduleBase) +
              "/${moduleToFile mod.moduleName}"
          )
          modSpecs;

      dirs = allTransitiveDirectories modSpecs;
    in
      # This symlinks the extra dirs to $PWD for GHCi to work
      writeScriptBin "ghci-with-files"
        ''
        #!/usr/bin/env bash
        set -euo pipefail

        TRAPS=""
        for i in ${lib.strings.escapeShellArgs dirs}; do
          if [ "$i" != "$PWD" ]; then
          for j in $(find "$i" ! -path "$i"); do
            file=$(basename $j)
            echo "Temporarily symlinking $j to $file..."
            ln -s $j $file
            TRAPS="rm $file ; $TRAPS"
            trap "$TRAPS" EXIT
            echo "done."
          done
          fi
        done
        echo ${lib.strings.escapeShellArgs ghcOpts}
        ${ghc}/bin/ghci -optP-include -optPcabal_macros.h ${lib.strings.escapeShellArgs ghciArgs}
        '';
}
