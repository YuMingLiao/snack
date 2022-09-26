TODO
- [x] check if it still works.
- [x] understand what to do when you in the middle of development while your upstream updated.
- [x] import parser doesn't use ghc with all packages, so -fversion-macros failed.
- [x] my main is Tutoriald.tutd. exe is tutoriald.tutd. wierd.
- [] content-addressed readDir may replace nix-freeze-files
#refactoring
- [] DO I really need memo to speed up? I am confused. I just want to run base path first, once and for all. It seems not fit in lazy nix.
- [] baseAndPkgSpec ... it seems PkgSpec are the same.
- Q. Do I really need transitive dependencies to compile a non-leaf module?

# multi-exes
- [] check multi roots in a dfsDAG
- [] project-m36 put files by module hierarchy, but relatedness. file name with a big case may be main files.
- [] It seems that tutd.nix and websocket.nix can't share compiled lib. Why? They are in the same src. Well, pkgSepc is not the same. So Maybe multi main in a package.nix is a good idea.

#recursive-nix
- [] let nix compile project-m36 by snack. Agile development of big haskell dependency.
- [] haskellPackages.incremental-project-m36 for lib and exe (seems achievable)

#find package by imports
- [] a nix build that auto detect packages needed in a hs file is probably a good start.
Well, while hoogle get packages names in stackage, I still need to manually add a package I want to try and ghcWith to make the module I am trying to compile. So auto-find-package-by-module cannot totally work.

#optimization
- [] maybe add import-parser to nix-freeze-files will acclerate `snack build`

