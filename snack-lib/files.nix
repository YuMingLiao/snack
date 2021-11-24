# file related operations
{ lib, stdenv, writeScript, callPackage }:
with (callPackage ./lib.nix { });
with lib.attrsets;
with builtins; rec {
  # Takes a (string) filepath and creates a derivation for that file (and for
  # that file only)
  singleOut = base: file:
    let
      basePrefix = (builtins.toString base) + "/";
      pred = path: type:
        let
          actual = lib.strings.removePrefix basePrefix path;
          expected = file;
        in (expected == actual)
        || (type == "directory" && (lib.strings.hasPrefix actual expected));
      # TODO: even though we're doing a lot of cleaning, there's still some
      # 'does-file-exist' happening
      src = lib.cleanSourceWith {
        filter = pred;
        src = lib.cleanSource base;
      };
      name = # Makes the file name derivation friendly
        lib.stringAsChars (x:
          if x == "/" then
            "_"
          else if builtins.isNull (builtins.match "[a-zA-Z0-9.+=-_?]" x) then
            ""
          else
            x) file;

    in stdenv.mkDerivation {
      inherit name src;
      builder = writeScript (name + "-single-out")
      # TODO: make sure the file actually exists and that there's only one
        ''
          source $stdenv/setup
          mkdir -p $out
          mkdir -p $(dirname $out/${file})
          cp $src/${file} $out/${file}
        '';
    };

  doesFileExist = base: filename: lib.lists.elem filename (listFilesInDir base);

  /* listFilesInDir = dir:
     let
       go = dir: dirName:
         lib.lists.concatLists
         (
           lib.attrsets.mapAttrsToList
             (path: ty:
               if ty == "directory"
               then
                 go "${dir}/${path}" "${dirName}${path}/"
               else
                 [ "${dirName}${path}" ]
             )
             (builtins.readDir dir)
         );
     in go dir "";
  */
  listFilesInDir = dir:
    dfsDAG {
      f = info@{ dir, dirName }:
        _:
        mapAttrs (path: _: { "${dirName}${path}" = dir; })
        (filterAttrs (path: ty: ty != "directory") (readDir dir));
      elemLabel = info@{ dir, dirName }: dirName;
      elemChildren = info@{ dir, dirName }:
        mapAttrsToList (path: _: {
          dir = "${dir}/${path}";
          dirName = "${dirName}${path}/";
        }) (filterAttrs (path: ty: ty == "directory") (readDir dir));
      reduce = a: b: a // b;
      empty = { };
    } [{
      dir = dir;
      dirName = "";
    }];

  filesWithBaseInDir = base:
    dfsDAG {
      f = info@{ dir, dirName }:
        _:
        mapAttrs' (path: _: nameValuePair "${dirName}${path}" base)
        (filterAttrs (path: ty: ty != "directory") (readDir dir));
      elemLabel = info@{ dir, dirName }: dirName;
      elemChildren = info@{ dir, dirName }:
        mapAttrsToList (path: _: {
          dir = "${dir}/${path}";
          dirName = "${dirName}${path}/";
        }) (filterAttrs (path: ty: ty == "directory") (readDir dir));
      reduce = a: b: a // b;
      empty = { };
    } [{
      dir = base;
      dirName = "";
    }];

}
