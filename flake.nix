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
        overlay = prev: pkgs: {
          packages = pkgs.callPackages nix/packages.nix { };
        };
        pkgs = import nixpkgs { inherit system overlays; };
      in
      with pkgs;
      {
        devShells.default = import ./shell.nix { inherit pkgs; };
        packages.default = self.checks.${system}.check-download;
        checks = {
          my-check = import ./tests/tests.nix { inherit pkgs; };
          check-snack-package-file-arg = stdenv.mkDerivation {
            requiredSystemFeatures = [ "recursive-nix" ];
            name = "check-snack-package-file-arg";
            src = ./.;
            buildInputs = [
              packages.snack-exe
              nix
            ];
            LOCALE_ARCHIVE = "${glibcLocales}/lib/locale/locale-archive";
            LANG = "en_US.UTF-8";
            NIX_PATH = "nixpkgs=${nixpkgs}";
            buildPhase = ''
              export HOME=$(pwd)
              echo $NIX_PATH
              cd tests/any-paths/
              snack --package-file ./package.yaml run '';
          };
          check-download = stdenv.mkDerivation {
            name = "check-download";
            src = ./.;
            requiredSystemFeatures = [ "recursive-nix" ];
            buildInputs = [nix];
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
