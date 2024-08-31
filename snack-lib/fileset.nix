{pkgs}:
with builtins;
with pkgs;
with pkgs.lib.attrsets;
with pkgs.stdenv;
with rec {
  deepReadDir = path:
    let 
      attrset = readDir path;
      go = name: value:
        if value == "directory" then
          deepReadDir (path + "/${name}")
        else
          path + "/${name}";
    in mapAttrs go attrset;

  freezeFiles = path: freezeFileSet (deepReadDir path);

  freezeFileSet = attrset: mapAttrsRecursive go attrset;

  go = _: filepath: "${filepath}"; 

  # deprecated, since nix has built-in syntax.
  go' = _: filepath:
    builtins.path {
      path = filepath;
      sha256 = narHash filepath;
    };
  

  narHash = p:
    builtins.convertHash {
      hash =
        #hashFile "sha256" p; # it is flat while nix-freeze-files uses recursive.
        readFile (hashPath p);
      toHashFormat = "nix32";
      hashAlgo = "sha256";
    };
  hashPath = p:
    mkDerivation {
      __contentAddressed = true;
      name = baseNameOf p + "-hashPath";
      src = dirOf p;
      buildInputs = [ nix ];
      buildPhase = ''
        touch $out
        nix-hash --type sha256 --base32 ${baseNameOf p} | tr -d "\n" > $out
      '';
    };
}; {
  inherit freezeFiles;
}
