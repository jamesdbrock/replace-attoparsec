{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE CPP #-}

module TestByteString ( tests ) where

import Distribution.TestSuite as TestSuite
import Data.Attoparsec.ByteString as A
import Data.Attoparsec.Combinator
import qualified Data.ByteString as B
import Data.ByteString.Internal (c2w)
import "parsers" Text.Parser.Token
import Replace.Attoparsec.ByteString
import Control.Applicative

findAllCap' :: Parser a -> Parser [Either B.ByteString (B.ByteString, a)]
findAllCap' sep = sepCap (match sep)

tests :: IO [Test]
tests = return
    [ Test $ runParserTest "findAllCap upperChar"
        (findAllCap' upperChar)
        ("aBcD" :: B.ByteString)
        [Left "a", Right ("B", c2w 'B'), Left "c", Right ("D", c2w 'D')]
    -- check that sepCap can progress even when parser consumes nothing
    -- and succeeds.
    , Test $ runParserTest "zero-consumption parser"
        (sepCap (many upperChar))
        ("aBcD" :: B.ByteString)
        [Left "a", Right [c2w 'B'], Left "c", Right [c2w 'D']]
    , Test $ runParserTest "scinum"
        (sepCap scinum)
        ("1E3")
        ([Right (1,3)])
    , Test $ runParserTest "monad fail"
        (sepCap (fail "" :: Parser ()))
        ("xxx")
        ([Left "xxx"])
#if MIN_VERSION_GLASGOW_HASKELL(8,6,0,0)
    , Test $ runParserTest "read fail"
        (sepCap (return (read "a" :: Int) :: Parser Int))
        ("a")
        ([Left "a"])
#endif
    , Test $ runParserFeed "const string"
        (sepCap (string "aa"))
        (" a") ("a ")
        ([Left " ",Right"aa",Left" "])
    , Test $ runParserTest "empty input" (sepCap (fail "" :: Parser ())) "" []
    , Test $ streamEditTest "x to o" (string "x") (const "o") "x x x" "o o o"
    , Test $ streamEditTest "x to o inner" (string "x") (const "o") " x x x " " o o o "
    , Test $ streamEditTest "ordering" (string "456") (const "ABC") "123456789" "123ABC789"
    , Test $ streamEditTest "empty input" (match (fail "")) (fst) "" ""
    , Test $ breakCapTest "basic" upperChar "aAa" (Just ("a", c2w 'A', "a"))
    , Test $ breakCapTest "first" upperChar "Aa" (Just ("", c2w 'A', "a"))
    , Test $ breakCapTest "last" upperChar "aA" (Just ("a", c2w 'A', ""))
    , Test $ breakCapTest "fail" upperChar "aaa" Nothing
    , Test $ breakCapTest "match" (match upperChar) "aAa" (Just ("a", ("A",c2w 'A'), "a"))
    , Test $ breakCapTest "zero-width" (lookAhead upperChar) "aAa" (Just ("a", c2w 'A', "Aa"))
    , Test $ breakCapTest "empty input" upperChar "" Nothing
    , Test $ breakCapTest "empty input zero-width" (return () :: Parser ()) "" (Just ("", (), ""))
    ]

  where
    runParserTest nam p input expected = TestInstance
            { run = do
                case parseOnly p input of
                    Left e -> return (Finished $ TestSuite.Fail $ show e)
                    Right output ->
                        if (output == expected)
                            then return (Finished Pass)
                            else return (Finished $ TestSuite.Fail
                                        $ "got " <> show output <> " expected " <> show expected)
            , name = "parseOnly sepCap " <> nam
            , tags = []
            , options = []
            , setOption = \_ _ -> Left "no options supported"
            }

    runParserFeed nam p input1 input2 expected = TestInstance
            { run = do
                case parse p input1 of
                    A.Fail _i _ e -> return (Finished $ TestSuite.Fail $ show e)
                    A.Partial cont1 -> case cont1 input2 of
                        A.Fail _i _ e -> return (Finished $ TestSuite.Fail $ show e)
                        A.Partial cont2 -> case cont2 "" of
                            A.Fail _i _ e -> return (Finished $ TestSuite.Fail $ show e)
                            A.Partial _ -> return (Finished $ TestSuite.Fail $ "Should not ask for more input")
                            A.Done _i output ->
                                if (output == expected)
                                    then return (Finished Pass)
                                    else return (Finished $ TestSuite.Fail
                                                $ "got " <> show output <> " expected " <> show expected)
                        A.Done _i _output -> return (Finished $ TestSuite.Fail $ "Should ask for more input")
                    A.Done _i _output -> return (Finished $ TestSuite.Fail $ "Should ask for more input")
            , name = "parse Partial sepCap " <> nam
            , tags = []
            , options = []
            , setOption = \_ _ -> Left "no options supported"
            }

    streamEditTest nam sep editor input expected = TestInstance
            { run = do
                let output = streamEdit sep editor input
                if (output == expected)
                    then return (Finished Pass)
                    else return (Finished $ TestSuite.Fail
                                $ show output ++ " ≠ " ++ show expected)
            , name = "streamEdit " ++ nam
            , tags = []
            , options = []
            , setOption = \_ _ -> Left "no options supported"
            }

    breakCapTest nam sep input expected = TestInstance
            { run = do
                let output = breakCap sep input
                if (output == expected)
                    then return (Finished Pass)
                    else return (Finished $ TestSuite.Fail
                                $ "got " <> show output <> " expected " <> show expected)
            , name = "breakCap " ++ nam
            , tags = []
            , options = []
            , setOption = \_ _ -> Left "no options supported"
            }

    scinum :: Parser (Double, Integer)
    scinum = do
        m <- (fromIntegral :: Integer -> Double) <$> decimal
        _ <- string "E"
        e <- decimal
        return (m, e)

    upperChar = satisfy $ \c -> c >= c2w 'A' && c <= c2w 'Z'

