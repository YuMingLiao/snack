let
  #pkgs = import ../nix {};
  overlay = _: pkgs:
      { 
        packages = pkgs.callPackages ../nix/packages.nix {};
      };
  pkgs = import <nixpkgs> { overlays = [overlay]; };
  specJson = pkgs.writeTextFile
    { name = "spec-json";
      #text = builtins.toJSON { inherit (pkgs.sources.nixpkgs) sha256 url; } ;
      text = builtins.toJSON {} ;
      destination = "/spec.json";
    };
  lib64 = pkgs.runCommand "lib64" {}
    ''
      tar -czf lib.tar.gz -C ${../snack-lib} .
      mkdir -p $out
      base64 lib.tar.gz > $out/lib.tar.gz.b64
    '';
in
  { main = "Snack";
    src = ./.;
    dependencies =
      [
        "aeson"
        "file-embed"
        "interpolate"
        "optparse-applicative"
        "shelly"
        "text"
        "unix"
        "unliftio"
      ];
    ghcOpts = [ "-Werror" "-Wall" ] ;

    extra-directories =
      { Snack =
          [ specJson
            lib64
          ];
      };
  }
