module Main where
import Lib
main :: IO ()
#if defined(A) 
main = putStrLn x
#else
main = putStrLn "no A"
#endif
