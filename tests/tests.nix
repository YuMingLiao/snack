with import ../nix {};
let
  any-paths = stdenv.mkDerivation rec {
    requiredSystemFeatures = [ "recursive-nix" ];
    name = "any-paths";
    src = ./any-paths;
    buildPhase = builtins.readFile ./any-paths/test;
    #buildPhase = "cd .. && ls . > $out";
    buildInputs = [ packages.snack-exe nix ];
    #LANG = "en_US.UTF-8";
  };
in any-paths
