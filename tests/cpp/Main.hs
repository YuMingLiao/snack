{-# LANGUAGE CPP #-}
module Main where
#if MIN_VERSION_base(4,9,1)
main :: IO ()
main = putStrLn "hello base(4,9,1)"
#else
main :: IO ()
main = putStrLn "hello"
#endif



