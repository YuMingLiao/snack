{ lib
}:
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
foldDAG = fld@{f, empty, elemLabel, reduce, elemChildren}: roots:
  (foldDAGRec fld { traversed = {}; elem' = empty;} roots).elem';

# foldDAG' :: Fold -> { label -> elem' } -> [elem] -> { label -> elem' }
foldDAGRec =
    fld@{f, empty, elemLabel, reduce, elemChildren}:
    acc0:
    roots:
  let
    insert = acc@{traversed, elem'}: elem:
      let
        label = elemLabel elem;
        children = elemChildren elem;
      in
        if lib.attrsets.hasAttr label traversed
        then acc
        else
          let acc' =
              { elem' = reduce elem' (f elem);
                traversed = traversed // { ${label} = null; };
              };
          in foldDAGRec fld acc' children;
  in lib.foldl insert acc0 roots;

# dfsDAG :: DFS -> [elem] -> { label -> elem' }
dfsDAG = dfs@{f, empty, elemLabel, reduce, elemChildren, ...}: roots:
  (dfsDAGRec dfs {traversed = []; path = []; elem' = empty; } roots).elem';


# dfsDAGRec :: DFS -> { label -> elem' } -> [elem] -> { label -> elem' }
dfsDAGRec =
    dfs@{f, empty, elemLabel, reduce, elemChildren, ...}:
    acc0:
    roots:
  let
    insert = acc@{traversed, path, elem'}: elem:
      let
        label = elemLabel elem;
        children = elemChildren elem;
      in
        if lib.lists.elem label path
        then abort "cycle: ${toString (path++[label])}"
        else if lib.lists.elem label traversed 
        then acc
        else
          let acc' =
              { inherit elem' traversed;
                path = path ++ [label];
              };
              acc'' = dfsDAGRec dfs acc' children;
              acc''' = 
              { elem' = reduce acc''.elem' (f elem acc''.elem');
                inherit path;
                traversed = acc''.traversed ++ [label];
              };
          in acc''';
  in lib.foldl insert acc0 roots;




withAttr = obj: attrName: def: f:
  if builtins.hasAttr attrName obj then f (obj.${attrName}) else  def;

optAttr = obj: attrName: def:
  if builtins.hasAttr attrName obj then obj.${attrName} else def;

tap = obj: attrName: f: obj // { "${attrName}" = f (obj.${attrName}) ; };

}
