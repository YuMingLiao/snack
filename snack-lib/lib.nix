{ lib
}:
with lib.debug;
with lib.lists;
with builtins;
rec {
# All fold functions in this module take a record as follows:
# { f :: elem -> elem'
# , empty :: elem'
# , reduce :: elem' -> elem' -> elem'
# , elemLabel :: elem -> label
# , elemChildren :: elem -> [elem]
# }

# foldDAG1 :: Fold -> elem -> elem'
foldDAG1 = fld: root:
  let acc = foldDAGRec fld {} [root];
  in acc.${fld.elemLabel root};

# foldDAG' :: Fold -> [elem] -> [elem']
foldDAG' = fld: roots:
  let acc = foldDAGRec fld {} roots;
  in map (elem: acc.${fld.elemLabel elem}) roots;

# foldDAG :: Fold -> [elem] -> { label -> elem' }
foldDAG = fld@{f, empty, elemLabel, reduce, elemChildren, purpose}: roots:
  (foldDAGRec fld { traversed = {}; elem' = empty; path = [];} roots).elem';

# foldDAG' :: Fold -> { label -> elem' } -> [elem] -> { label -> elem' }
foldDAGRec =
    fld@{f, empty, elemLabel, reduce, elemChildren, purpose}:
    acc0:
    roots:
  let
    insert = acc@{traversed, elem', path}: elem:
      let
        label = elemLabel elem;
        children = elemChildren elem;
      in
        if builtins.elem label path
        then abort "Module imports go into cycle: ${toString (path ++ [label])}"
        else if lib.attrsets.hasAttr label traversed
        then acc
        else
          let acc' =
              { elem' = reduce elem' (f elem);
                traversed = trace "${purpose}: ${toString (length (attrNames traversed) + 1)}" traversed // { ${label} = null; };
                path = path ++ [label];
              };
              applyN = n: f: x: if (n == 0) then f x
                                else if ( n > 0) then applyN (n - 1) f (f x) else abort "n < 0";
              indent = applyN (length path) (x: x + "  ") "";
          in (foldDAGRec fld acc' children) // {inherit path;};
# (builtins.trace "${toString indent}${label}\n ${if children==[] then "stop" else "fold"}" 
  in lib.foldl insert acc0 roots;

withAttr = obj: attrName: def: f:
  if builtins.hasAttr attrName obj then f (obj.${attrName}) else  def;

optAttr = obj: attrName: def:
  if builtins.hasAttr attrName obj then obj.${attrName} else def;

tap = obj: attrName: f: obj // { "${attrName}" = f (obj.${attrName}) ; };

}
