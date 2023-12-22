# module related operations
{ lib, callPackage, runCommand, stdenv, glibcLocales, haskellPackages
, symlinkJoin }:

with (callPackage ./files.nix { });
with builtins;
with lib.attrsets;
with lib.debug; rec {
  # Turns a module name to a file
  moduleToFile = mod: (lib.strings.replaceChars [ "." ] [ "/" ] mod) + ".hs";

  # Turns a module name into the filepath of its object file
  # TODO: bad name, this is module _name_ to object
  moduleToObject = mod: (lib.strings.replaceChars [ "." ] [ "/" ] mod) + ".o";

  # Turns a filepath name to a module name
  fileToModule = file:
    lib.strings.removeSuffix ".hs"
    (lib.strings.replaceChars [ "/" ] [ "." ] file);

  # Singles out a given module (by module name) (derivation)
  singleOutModule = base: mod: singleOut base (moduleToFile mod);

  # Singles out a given module (by module name) (path to module file)
  singleOutModulePath = base: mod:
    "${singleOut base (moduleToFile mod)}/${moduleToFile mod}";

  #TODO Maybe hie files helps. Maybe vim can produce an import change notification.
  #TODO ghc-pkg find-module may helps.
  # Generate a list of haskell module names needed by the haskell file
  listModuleImports =
    baseByModuleName: filesByModuleName: dirsByModuleName: depsByModuleName: extsByModuleName: ghcOptsByModuleName: modName:
    builtins.fromJSON (builtins.readFile
      (listAllModuleImportsJSON baseByModuleName filesByModuleName
        dirsByModuleName depsByModuleName extsByModuleName ghcOptsByModuleName modName));

  # Whether the file is a Haskell module or not. It uses very simple
  # heuristics: If the file starts with a capital letter, then yes.
  isHaskellModuleFile = f:
    !(builtins.isNull
      (builtins.match "[a-zA-Z].*[.]hs$" (builtins.baseNameOf f)));

  listModulesInDir = dir:
    map fileToModule (lib.filter isHaskellModuleFile (attrNames (listFilesInDir dir)));
  
  modNamesWithBaseInDir = dir:
    mapAttrs' (n: base: nameValuePair (fileToModule n) base)
    (lib.filterAttrs (n: _: isHaskellModuleFile n) (filesWithBaseInDir dir));

  doesModuleExist = baseByModuleName: modName:
    doesFileExist (baseByModuleName modName) (moduleToFile modName);

  # Lists all module dependencies, not limited to modules existing in this
  # project
  listAllModuleImportsJSON =
    baseByModuleName: filesByModuleName: dirsByModuleName: depsByModuleName: extsByModuleName: ghcOptsByModuleName: modName:
    let
      base = baseByModuleName modName;
      modExtsArgs = lib.strings.escapeShellArgs (map (x: "-X${x}") (extsByModuleName modName));
      deps = (depsByModuleName modName);
      depsArgs = lib.strings.escapeShellArgs (if lib.lists.length deps == 0 then [""] else ["-package "] ++ deps); 
      ghc = haskellPackages.ghcWithPackages (ps: [ ps.ghc ] ++ map (x: ps.${x}) deps); 
      ghcOptsArgs = lib.strings.escapeShellArgs (ghcOptsByModuleName modName);
      importParser = runCommand "import-parser" { buildInputs = [ ghc ]; }
        "ghc --version && ghc -Wall -Werror -package ghc ${./Imports.hs} -o $out";
      # XXX: this command needs ghc in the environment so that it can call "ghc
      # --print-libdir"...
      onlyThisFile = p: validStorePath (onlyThisFile' p);
      onlyThisFile' = f: lib.cleanSourceWith {
	  filter = path: _: (/. + path) == f;
	  src = dirOf f;
	};
    validStorePath = s: /. + "nix/store" + builtins.elemAt (builtins.split "/nix/store" s.outPath) 2;
    dirsWithExtraFiles = map onlyThisFile (filesByModuleName modName);
    in stdenv.mkDerivation {
      __contentAddressed = true;
      name = "${modName}-dependencies-json";
      buildInputs = [ ghc glibcLocales ];
      LANG = "en_US.utf-8";
      src = symlinkJoin {
        name = "${modName}-deps-json-extra-files";
        paths = dirsWithExtraFiles ++ (dirsByModuleName modName);
        __contentAddressed = true;
      };
      phases = [ "unpackPhase" "buildPhase" ];
      #It's just parsing imports. IMO, modExts and ghcOpts should be omitted to avoid recompiling when change.
      # TODO: but to parse macros, gonna need deps, -XCPP, and -fversion-macros if CPP is on.

      buildPhase = ''
        ${importParser} ${
          singleOutModulePath base modName
        } ${modExtsArgs} ${ghcOptsArgs} ${depsArgs} > $out
      '';
    };

    findDep = allDeps: modImport: let
        ghc = haskellPackages.ghcWithPackages (ps: with ps; (map (p: ps.${p}) allDeps));
      in
      builtins.readFile (stdenv.mkDerivation {
      name = "${modImport}-dependency";
      buildInputs = [ghc];
      phases = ["buildPhase"];
      buildPhase = ''
        ${ghc}/bin/ghc-pkg find-module ${modImport} | sed '1d' | awk '{$1=$1};1' | tr -d "()"> tmp
        grep -q "no package" tmp && echo "error: couldn't find package for ${modImport}" && touch $out || sed 's/-[0-9].*//g' tmp | tr -d '\n' > $out 
        echo "${modImport} is in $(cat $out)"
      '';
    });
}
