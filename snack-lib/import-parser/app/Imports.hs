{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use <$>" #-}

module Main (main) where

import Control.Monad.IO.Class
import Data.List (stripPrefix)

import System.Environment
import Control.Exception
import qualified GHC
import qualified GHC.IO.Handle.Text as Handle
import qualified GHC.Hs.ImpExp as HsImpExp
import qualified GHC.Hs as HsSyn
import GHC.Data.Bag (bagToList)
import qualified GHC.Parser.Lexer as Lexer
import qualified GHC.Unit.Module.Name as Module
import qualified GHC.Parser as Parser
import qualified GHC.Driver.Pipeline as DriverPipeline
import qualified GHC.Driver.Config.Parser as Config
import qualified GHC.Data.Bag as Bag
import qualified GHC.Data.StringBuffer as StringBuffer
import qualified GHC.Data.FastString as FastString
import qualified GHC.Driver.Session as DynFlags
import qualified GHC.Types.SourceError as HscTypes
import qualified GHC.Types.SrcLoc as SrcLoc
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

        (dflags2, fp2) <- liftIO $
          either (error . show) id <$> DriverPipeline.preprocess hsc_env fp Nothing Nothing

        _ <- GHC.setSessionDynFlags dflags2

        dflags3 <- GHC.getSessionDynFlags
        -- Read the file that we want to parse
        str <- liftIO $ filterBOM <$> readFile fp2

        runParser dflags3 fp2 str Parser.parseModule >>= \case
          Lexer.POk _ (SrcLoc.L _ res) -> pure res

          Lexer.PFailed pState  -> liftIO $ do
            let spn = Lexer.last_loc pState
            let e   = Lexer.errors pState

            Handle.hPutStrLn stderr $ unlines
              [ "Could not parse module: "
              , fp2
              , " (originally " <> fp <> ")"
              , " because "  <> (show . bagToList $ fmap diagnosticMessage e)
              , " src span ", show spn
              ]
            throwIO $ HscTypes.mkSrcErr $
              diagnosticMessage <$> Lexer.getPsMessages pState
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

runParser :: DynFlags.DynFlags -> FilePath -> String -> Lexer.P a -> Lexer.ParseResult a
runParser dynFlags filename str parser = do
    Lexer.unP parser (parseState (Config.initParserOpts dynFlags))
  where
    location = SrcLoc.mkRealSrcLoc (FastString.mkFastString filename) 1 1
    buffer = StringBuffer.stringToStringBuffer str

    -- TODO: not DynFlags anymore. It's ParserOpts now. What's the relationship?
    parseState flags = Lexer.initParserState flags buffer location




