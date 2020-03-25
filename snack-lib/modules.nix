# module related operations
{ lib
, callPackage
, runCommand
, stdenv
, glibcLocales
, haskellPackages
, symlinkJoin
}:

with (callPackage ./files.nix {});
with builtins;
with lib.attrsets;
rec {
  # Turns a module name to a file
  moduleToFile = mod:
    (lib.strings.replaceChars ["."] ["/"] mod) + ".hs";

  # Turns a module name into the filepath of its object file
  # TODO: bad name, this is module _name_ to object
  moduleToObject = mod:
    (lib.strings.replaceChars ["."] ["/"] mod) + ".o";

  # Turns a filepath name to a module name
  fileToModule = file:
    lib.strings.removeSuffix ".hs"
      (lib.strings.replaceChars ["/"] ["."] file);

  # Singles out a given module (by module name) (derivation)
  singleOutModule = base: mod: singleOut base (moduleToFile mod);

  # Singles out a given module (by module name) (path to module file)
  singleOutModulePath = base: mod:
    "${singleOut base (moduleToFile mod)}/${moduleToFile mod}";

  # Generate a list of haskell module names needed by the haskell file
  listModuleImports = baseByModuleName: filesByModuleName: dirsByModuleName: extsByModuleName: ghcOptsByModuleName: modName:
    builtins.fromJSON
     (builtins.readFile (listAllModuleImportsJSON baseByModuleName filesByModuleName dirsByModuleName extsByModuleName ghcOptsByModuleName modName))
    ;

  # Whether the file is a Haskell module or not. It uses very simple
  # heuristics: If the file starts with a capital letter, then yes.
  isHaskellModuleFile = f:
    ! (builtins.isNull (builtins.match "[a-zA-Z].*[.]hs$" (builtins.baseNameOf f)));

  listModulesInDir = dir:
    map fileToModule
      (lib.filter isHaskellModuleFile
      (listFilesInDir dir));

  modNamesWithBaseInDir = dir:
    mapAttrs' (n: base: nameValuePair (fileToModule n) base)
      (lib.filterAttrs (n: _: isHaskellModuleFile n)
      (filesWithBaseInDir dir));



  doesModuleExist = baseByModuleName: modName:
    doesFileExist (baseByModuleName modName) (moduleToFile modName);

  # Lists all module dependencies, not limited to modules existing in this
  # project
  listAllModuleImportsJSON = baseByModuleName: filesByModuleName: dirsByModuleName: extsByModuleName: ghcOptsByModuleName: modName:
    let
      base = baseByModuleName modName;
      exts = extsByModuleName modName;
      modExts =
        lib.strings.escapeShellArgs
          (map (x: "-X${x}") exts);
      ghc = haskellPackages.ghcWithPackages (ps: [ ps.ghc ]);
      ghcOpts = (ghcOptsByModuleName modName); 
      ghcOptsArgs = lib.strings.escapeShellArgs ghcOpts;
      importParser = runCommand "import-parser"
        { buildInputs = [ ghc ];
        } "ghc -Wall -Werror -package ghc ${./Imports.hs} -o $out" ;
    # XXX: this command needs ghc in the environment so that it can call "ghc
    # --print-libdir"...
    in stdenv.mkDerivation
      {   name = "dependencies-json";
          buildInputs = [ ghc glibcLocales ];
          LANG="en_US.utf-8";
          src = symlinkJoin
          { name = "extra-files";
            paths = [ (filesByModuleName modName)] ++ (dirsByModuleName modName);
          };
          phases =
            [ "unpackPhase" "buildPhase" ];
          buildPhase = 
        ''
          ${importParser} ${singleOutModulePath base modName} ${modExts} ${ghcOptsArgs} ${if elem "CPP" exts then "-optP-include -optP./cabal_macros.h" else ""} > $out
        '';
      };
}
