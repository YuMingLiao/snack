TODO
- [x] check if it still works.
- [] let nix compile project-m36 by snack. Agile development of big haskell dependency.
- [x] understand what to do when you in the middle of development while your upstream updated.
- [] a nix build that auto detect packages needed in a hs file is probably a good start.
- [] import parser doesn't use ghc with all packages, so -fversion-macros failed.

#developer's thought log

look into ghc code? why where is a ghc_2.h?
Or see if I can figure out relationships between module trees and redefined warnings?

tmpdir or not is irrelavant.
delete tmp dir or not is irrelavant.

something is wrong in dfsDAG roots.
if import another root, it fails.
maybe i should build a importDAG and get a toposort first.
Now it seems works right.

I use symLinkJoin to bring cabal_macros.h, is it related to the warning?

It turns out I don't need cabal_macros.h now. ghc_??.h has it. What a surprise!

#find package by imports

Well, while hoogle get packages names in stackage, I still need to manually add a package I want to try and ghcWith to make the module I am trying to compile. So auto-find-package-by-module cannot totally work.

#ca-derivations

stderr: error: unrecognised flag '--experimental-features 'ca-derivations''
Try '/run/current-system/sw/bin/nix-build --help' for more information.

maybe add import-parser to nix-freeze-files will acclerate `snack build`


#nonsense
module drv can't be one between one edit.


--

ghc-pkg find-module only works if you have decisive package list.
