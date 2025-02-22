--------------------------------------------------------------------------------
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TemplateHaskell            #-}
module Patat.Presentation.Internal
    ( Breadcrumbs
    , Presentation (..)
    , PresentationSettings (..)
    , defaultPresentationSettings

    , Margins (..)
    , marginsOf

    , ExtensionList (..)
    , defaultExtensionList

    , ImageSettings (..)

    , EvalSettingsMap
    , EvalSettings (..)

    , Slide (..)
    , Instruction.Fragment (..)
    , Index

    , getSlide
    , numFragments

    , ActiveFragment (..)
    , getActiveFragment
    ) where


--------------------------------------------------------------------------------
import           Control.Monad                  (mplus)
import qualified Data.Aeson.Extended            as A
import qualified Data.Aeson.TH.Extended         as A
import qualified Data.Foldable                  as Foldable
import qualified Data.HashMap.Strict            as HMS
import           Data.List                      (intercalate)
import           Data.Maybe                     (fromMaybe, listToMaybe)
import qualified Data.Text                      as T
import qualified Patat.Presentation.Instruction as Instruction
import qualified Patat.Theme                    as Theme
import           Prelude
import qualified Text.Pandoc                    as Pandoc
import           Text.Read                      (readMaybe)


--------------------------------------------------------------------------------
type Breadcrumbs = [(Int, [Pandoc.Inline])]


--------------------------------------------------------------------------------
data Presentation = Presentation
    { pFilePath       :: !FilePath
    , pTitle          :: ![Pandoc.Inline]
    , pAuthor         :: ![Pandoc.Inline]
    , pSettings       :: !PresentationSettings
    , pSlides         :: [Slide]
    , pBreadcrumbs    :: [Breadcrumbs]  -- One for each slide.
    , pActiveFragment :: !Index
    } deriving (Show)


--------------------------------------------------------------------------------
-- | These are patat-specific settings.  That is where they differ from more
-- general metadata (author, title...)
data PresentationSettings = PresentationSettings
    { psRows             :: !(Maybe (A.FlexibleNum Int))
    , psColumns          :: !(Maybe (A.FlexibleNum Int))
    , psMargins          :: !(Maybe Margins)
    , psWrap             :: !(Maybe Bool)
    , psTheme            :: !(Maybe Theme.Theme)
    , psIncrementalLists :: !(Maybe Bool)
    , psAutoAdvanceDelay :: !(Maybe (A.FlexibleNum Int))
    , psSlideLevel       :: !(Maybe Int)
    , psPandocExtensions :: !(Maybe ExtensionList)
    , psImages           :: !(Maybe ImageSettings)
    , psBreadcrumbs      :: !(Maybe Bool)
    , psEval             :: !(Maybe EvalSettingsMap)
    } deriving (Show)


--------------------------------------------------------------------------------
instance Semigroup PresentationSettings where
    l <> r = PresentationSettings
        { psRows             = psRows             l `mplus` psRows             r
        , psColumns          = psColumns          l `mplus` psColumns          r
        , psMargins          = psMargins          l <>      psMargins          r
        , psWrap             = psWrap             l `mplus` psWrap             r
        , psTheme            = psTheme            l <>      psTheme            r
        , psIncrementalLists = psIncrementalLists l `mplus` psIncrementalLists r
        , psAutoAdvanceDelay = psAutoAdvanceDelay l `mplus` psAutoAdvanceDelay r
        , psSlideLevel       = psSlideLevel       l `mplus` psSlideLevel       r
        , psPandocExtensions = psPandocExtensions l `mplus` psPandocExtensions r
        , psImages           = psImages           l `mplus` psImages           r
        , psBreadcrumbs      = psBreadcrumbs      l `mplus` psBreadcrumbs      r
        , psEval             = psEval             l <>      psEval             r
        }


--------------------------------------------------------------------------------
instance Monoid PresentationSettings where
    mappend = (<>)
    mempty  = PresentationSettings
                    Nothing Nothing Nothing Nothing Nothing Nothing Nothing
                    Nothing Nothing Nothing Nothing Nothing


--------------------------------------------------------------------------------
defaultPresentationSettings :: PresentationSettings
defaultPresentationSettings = PresentationSettings
    { psRows             = Nothing
    , psColumns          = Nothing
    , psMargins          = Just defaultMargins
    , psWrap             = Nothing
    , psTheme            = Just Theme.defaultTheme
    , psIncrementalLists = Nothing
    , psAutoAdvanceDelay = Nothing
    , psSlideLevel       = Nothing
    , psPandocExtensions = Nothing
    , psImages           = Nothing
    , psBreadcrumbs      = Nothing
    , psEval             = Nothing
    }


--------------------------------------------------------------------------------
data Margins = Margins
    { mLeft  :: !(Maybe (A.FlexibleNum Int))
    , mRight :: !(Maybe (A.FlexibleNum Int))
    } deriving (Show)


--------------------------------------------------------------------------------
instance Semigroup Margins where
    l <> r = Margins
        { mLeft  = mLeft  l `mplus` mLeft  r
        , mRight = mRight l `mplus` mRight r
        }


--------------------------------------------------------------------------------
instance Monoid Margins where
    mappend = (<>)
    mempty  = Margins Nothing Nothing


--------------------------------------------------------------------------------
defaultMargins :: Margins
defaultMargins = Margins
    { mLeft  = Nothing
    , mRight = Nothing
    }


--------------------------------------------------------------------------------
marginsOf :: PresentationSettings -> (Int, Int)
marginsOf presentationSettings =
    (marginLeft, marginRight)
  where
    margins    = fromMaybe defaultMargins $ psMargins presentationSettings
    marginLeft  = fromMaybe 0 (A.unFlexibleNum <$> mLeft margins)
    marginRight = fromMaybe 0 (A.unFlexibleNum <$> mRight margins)


--------------------------------------------------------------------------------
newtype ExtensionList = ExtensionList {unExtensionList :: Pandoc.Extensions}
    deriving (Show)


--------------------------------------------------------------------------------
instance A.FromJSON ExtensionList where
    parseJSON = A.withArray "FromJSON ExtensionList" $
        fmap (ExtensionList . mconcat) . mapM parseExt . Foldable.toList
      where
        parseExt = A.withText "FromJSON ExtensionList" $ \txt -> case txt of
            -- Our default extensions
            "patat_extensions" -> return (unExtensionList defaultExtensionList)

            -- Individuals
            _ -> case readMaybe ("Ext_" ++ T.unpack txt) of
                Just e  -> return $ Pandoc.extensionsFromList [e]
                Nothing -> fail $
                    "Unknown extension: " ++ show txt ++
                    ", known extensions are: " ++
                    intercalate ", "
                        [ show (drop 4 (show e))
                        | e <- [minBound .. maxBound] :: [Pandoc.Extension]
                        ]


--------------------------------------------------------------------------------
defaultExtensionList :: ExtensionList
defaultExtensionList = ExtensionList $
    Pandoc.readerExtensions Pandoc.def `mappend` Pandoc.extensionsFromList
    [ Pandoc.Ext_yaml_metadata_block
    , Pandoc.Ext_table_captions
    , Pandoc.Ext_simple_tables
    , Pandoc.Ext_multiline_tables
    , Pandoc.Ext_grid_tables
    , Pandoc.Ext_pipe_tables
    , Pandoc.Ext_raw_html
    , Pandoc.Ext_tex_math_dollars
    , Pandoc.Ext_fenced_code_blocks
    , Pandoc.Ext_fenced_code_attributes
    , Pandoc.Ext_backtick_code_blocks
    , Pandoc.Ext_inline_code_attributes
    , Pandoc.Ext_fancy_lists
    , Pandoc.Ext_four_space_rule
    , Pandoc.Ext_definition_lists
    , Pandoc.Ext_compact_definition_lists
    , Pandoc.Ext_example_lists
    , Pandoc.Ext_strikeout
    , Pandoc.Ext_superscript
    , Pandoc.Ext_subscript
    ]


--------------------------------------------------------------------------------
data ImageSettings = ImageSettings
    { isBackend :: !T.Text
    , isParams  :: !A.Object
    } deriving (Show)


--------------------------------------------------------------------------------
instance A.FromJSON ImageSettings where
    parseJSON = A.withObject "FromJSON ImageSettings" $ \o -> do
        t <- o A..: "backend"
        return ImageSettings {isBackend = t, isParams = o}


--------------------------------------------------------------------------------
type EvalSettingsMap = HMS.HashMap T.Text EvalSettings


--------------------------------------------------------------------------------
data EvalSettings = EvalSettings
    { evalCommand  :: !T.Text
    , evalReplace  :: !Bool
    , evalFragment :: !Bool
    } deriving (Show)


--------------------------------------------------------------------------------
instance A.FromJSON EvalSettings where
    parseJSON = A.withObject "FromJSON EvalSettings" $ \o -> EvalSettings
        <$> o A..: "command"
        <*> o A..:? "replace" A..!= False
        <*> o A..:? "fragment" A..!= True


--------------------------------------------------------------------------------
data Slide
    = ContentSlide (Instruction.Instructions Pandoc.Block)
    | TitleSlide   Int [Pandoc.Inline]
    deriving (Show)


--------------------------------------------------------------------------------
-- | Active slide, active fragment.
type Index = (Int, Int)


--------------------------------------------------------------------------------
getSlide :: Int -> Presentation -> Maybe Slide
getSlide sidx = listToMaybe . drop sidx . pSlides


--------------------------------------------------------------------------------
numFragments :: Slide -> Int
numFragments (ContentSlide instrs) = Instruction.numFragments instrs
numFragments (TitleSlide _ _)      = 1


--------------------------------------------------------------------------------
data ActiveFragment
    = ActiveContent Instruction.Fragment
    | ActiveTitle Pandoc.Block
    deriving (Show)


--------------------------------------------------------------------------------
getActiveFragment :: Presentation -> Maybe ActiveFragment
getActiveFragment presentation = do
    let (sidx, fidx) = pActiveFragment presentation
    slide <- getSlide sidx presentation
    pure $ case slide of
        TitleSlide lvl is -> ActiveTitle $
            Pandoc.Header lvl Pandoc.nullAttr is
        ContentSlide instrs -> ActiveContent $
            Instruction.renderFragment fidx instrs


--------------------------------------------------------------------------------
$(A.deriveFromJSON A.dropPrefixOptions ''Margins)
$(A.deriveFromJSON A.dropPrefixOptions ''PresentationSettings)

