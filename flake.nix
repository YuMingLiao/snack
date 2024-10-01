{
  inputs = {
    #    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    #    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ overlay ];
        overlay = final: prev: {
          packages = prev.callPackages nix/packages.nix { };
        };
        #pkgs = nixpkgs.legacyPackages.${system}.extend overlay;
        pkgs = import nixpkgs { inherit system overlays; };
      in
      with pkgs;
      {
        devShells.default = import ./shell.nix {  };

        packages.default = self.checks.${system}.check-download;

        checks = {
          check-snack-package-file-arg = stdenv.mkDerivation {
            # for nix-build in snack
            requiredSystemFeatures = [ "recursive-nix" ];
            name = "check-snack-package-file-arg";
            src = ./.;
            buildInputs = [
              packages.snack-exe
              nix
            ];
            # for hGetContent in Snack.hs 
            LOCALE_ARCHIVE = "${glibcLocales}/lib/locale/locale-archive";
            LANG = "en_US.UTF-8";
            # for nix-build in sanck 
            NIX_PATH = "nixpkgs=${nixpkgs}";
            buildPhase = ''
              HOME=$(pwd)
              cd tests/any-paths/
              snack --package-file ./package.yaml run '';
          };
          check-download = stdenv.mkDerivation {
            name = "check-download";
            src = ./.;
            requiredSystemFeatures = [ "recursive-nix" ];
            buildInputs = [nix];
            # for nix/ downloads, also trusted-user and --no-sandbox
            NIX_SSL_CERT_FILE= "/etc/ssl/certs/ca-certificates.crt";
            buildPhase = ''
              HOME=$(pwd)
              nix-build -E 'with import ./nix; builtins.readDir ./.'
              echo "OK" > $out
              '';
            };
        };
      }
    );
}
