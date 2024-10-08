# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a
Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- This CHANGELOG file to track changes to the command line and library APIs.
- Support for custom GHC version, `ghcWithPackages` and `pkgs`.
- Support for more than one directory in `src` (and HPack's `source-dirs`).
- Allow empty `source-dirs` in `package.yaml`; defaults to `./.`

### Changed
- The `snack run` function to accept arguments that will be passed to the built
  executable.
- The `snack.nix` now describes the build environment and packages are
  described through `package.nix` (i.e. to migrate: rename `snack.nix` to
  `package.nix`).
- The same flag (`-p`) is used for specifying both a YAML or Nix file. When
  none is provided snack tries to use either `./package.yaml` or
  `./package.nix`.
- The flag `-s` is used to specify a `snack.nix`. By default `./snack.nix` is
  used.
- The `--cores` was replaced with `--jobs`
- The default GHC version is now 8.4.4.
- The default GHC version is now 8.6.4.
- The default GHC version is now 9.6.5.

### Fixed
- The module import parsing when the CPP extension is enabled.
- The module import parsing when a BOM is present.
- The matching on Haskell files. Any file in any subdirectory ending in `.hs` will be matched, both lower- and uppercase filenames are accepted.

[Unreleased]: https://github.com/nmattia/snack/compare/51987daf76cffc31289e6913174dfb46b93df36b...HEAD
