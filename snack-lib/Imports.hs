{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE MagicHash #-}

module Main (main) where

import Control.Monad.IO.Class
import Data.List (stripPrefix)
#if __GLASGOW_HASKELL__ >= 804
#else
import Data.Semigroup
#endif
import System.Environment
import Control.Exception
import qualified GHC
#if __GLASGOW_HASKELL__ <= 808
import qualified ErrUtils
#endif

import qualified GHC.IO.Handle.Text as Handle

#if __GLASGOW_HASKELL__ >= 810
import qualified GHC.Hs.ImpExp as HsImpExp
#else
import qualified HsImpExp
#endif

#if __GLASGOW_HASKELL__ >= 810
import qualified GHC.Hs as HsSyn
#else
import qualified HsSyn
#endif


#if __GLASGOW_HASKELL__ >= 902
import qualified GHC.Parser.Errors.Ppr
import qualified GHC.Driver.Config 
import qualified GHC.Parser.Lexer as Lexer
import qualified GHC.Unit.Module.Name as Module
import qualified GHC.Utils.Outputable as Outputable
import qualified GHC.Parser as Parser 
import qualified GHC.Driver.Pipeline as DriverPipeline
import qualified GHC.Data.Bag as Bag 
import qualified GHC.Data.StringBuffer as StringBuffer
import qualified GHC.Data.FastString as FastString
import qualified GHC.Driver.Session as DynFlags
import qualified GHC.Types.SourceError as HscTypes
import qualified GHC.Types.SrcLoc as SrcLoc
#else
import qualified HscTypes
import qualified Lexer
import qualified Module
import qualified Outputable
import qualified Parser
import qualified SrcLoc
import qualified StringBuffer
import qualified Bag
import qualified FastString
import qualified DriverPipeline
import qualified DynFlags
#endif
import qualified System.Process as Process
import System.IO (stderr)

main :: IO ()
main = do
    (fp:exts) <- getArgs >>= \case
      args@(_:_) -> pure args
      [] -> fail "Please provide at least one argument (got none)"

    -- Read the output of @--print-libdir@ for 'runGhc'
    (_,Just ho1, _, hdl) <- Process.createProcess
      (Process.shell "ghc --print-libdir"){Process.std_out=Process.CreatePipe}
    libdir <- filter (/= '\n') <$> Handle.hGetContents ho1
    _ <- Process.waitForProcess hdl

    -- Some gymnastics to make the parser happy
    res <- GHC.runGhc (Just libdir)
      $ do

        -- We allow passing some extra extensions to be parsed by GHC.
        -- Otherwise modules that have e.g. @RankNTypes@ enabled will fail to
        -- parse. Note: if anybody gets rid of this: even without this it /is/
        -- necessary to run getSessionFlags/setSessionFlags at least once,
        -- otherwise GHC parsing fails with the following error message:
        --    <command line>: unknown package: rts
        dflags0 <- GHC.getSessionDynFlags
        (dflags1, _leftovers, _warns) <-
          DynFlags.parseDynamicFlagsCmdLine dflags0 (map (SrcLoc.mkGeneralLocated "on the commandline") exts)
        _ <- GHC.setSessionDynFlags dflags1

        hsc_env <- GHC.getSession


        -- XXX: We need to preprocess the file so that all extensions are
        -- loaded
#if __GLASGOW_HASKELL__ >= 808
        (dflags2, fp2) <- liftIO $
          either (\x -> error (show (Bag.bagToList x))) id <$> DriverPipeline.preprocess hsc_env fp Nothing Nothing
#else
        (dflags2, fp2) <- liftIO $
          DriverPipeline.preprocess hsc_env (fp, Nothing)
#endif
        _ <- GHC.setSessionDynFlags dflags2

        -- Read the file that we want to parse
        str <- liftIO $ filterBOM <$> readFile fp2

        runParser fp2 str Parser.parseModule >>= \case
          Lexer.POk _ (SrcLoc.L _ res) -> pure res
#if __GLASGOW_HASKELL__ >= 810
          Lexer.PFailed pState  -> liftIO $ do
            let spn = Lexer.last_loc pState -- ?
            let e   = undefined
#elif __GLASGOW_HASKELL__ >= 804 
          Lexer.PFailed _ spn e -> liftIO $ do
#else
          Lexer.PFailed spn e -> liftIO $ do
#endif
            Handle.hPutStrLn stderr $ unlines
              [ "Could not parse module: "
              , fp2
              , " (originally " <> fp <> ")"
              , " because " <> Outputable.showSDocUnsafe e
              , " src span "
              , show spn
              ]
            throwIO $ HscTypes.mkSrcErr $
#if __GLASGOW_HASKELL__ >= 902
              GHC.Parser.Errors.Ppr.pprError <$> (Lexer.getErrorMessages pState) 
#elif __GLASGOW_HASKELL__ >= 810
              Lexer.getErrorMessages pState dflags2 
#else
              Bag.unitBag $ ErrUtils.mkPlainErrMsg dflags2 spn e
#endif
    -- Extract the imports from the parsed module
    let imports' =
          map (\(SrcLoc.L _ idecl) ->
                  let SrcLoc.L _ n = HsImpExp.ideclName idecl
                  in Module.moduleNameString n) (HsSyn.hsmodImports res)

    -- here we pretend that @show :: [String] -> String@ outputs JSON
    print imports'

-- | Filter out the Byte Order Mark to avoid the following error:
-- lexical error at character '\65279'
filterBOM :: String -> String
filterBOM = \case
    [] -> []
    str@(x:xs) -> case stripPrefix "\65279" str of
      Just str' -> filterBOM str'
      Nothing -> x : filterBOM xs

runParser :: FilePath -> String -> Lexer.P a -> GHC.Ghc (Lexer.ParseResult a)
runParser filename str parser = do
    dynFlags <- DynFlags.getDynFlags
    pure $ Lexer.unP parser (parseState (GHC.Driver.Config.initParserOpts dynFlags))
  where
    location = SrcLoc.mkRealSrcLoc (FastString.mkFastString filename) 1 1
    buffer = StringBuffer.stringToStringBuffer str
#if __GLASGOW_HASKELL__ >= 902
    -- TODO: not DynFlags anymore. It's ParserOpts now. What's the relationship?
    parseState flags = Lexer.initParserState flags buffer location
#else
    parseState flags = Lexer.mkPState flags buffer location
#endif

