{-# LANGUAGE OverloadedStrings, FlexibleInstances #-}
module YouDo.Types where

import Control.Applicative ((<$>), (<*>), pure)
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), object, Value(..))
import Data.Aeson.Types (typeMismatch)
import qualified Data.Text.Lazy as LT
import Data.Time (UTCTime)
import Database.PostgreSQL.Simple.FromField (FromField(..))
import Database.PostgreSQL.Simple.FromRow (FromRow(..), field)
import Database.PostgreSQL.Simple.ToField (ToField(..))
import Web.Scotty (Parsable(..))

import YouDo.DB
import YouDo.TimeParser (parseUTCTime)

type Youdo = Versioned YoudoID YoudoData
instance NamedResource YoudoID where
    resourceName = const "youdos"
instance FromRow Youdo where
    fromRow = Versioned <$> (VersionedID <$> field <*> field)
        <*> (YoudoData <$> field <*> field <*> field <*> field <*> field)
instance ToJSON YoudoData where
    toJSON yd = object
        [ "assignerid" .= assignerid yd
        , "assigneeid" .= assigneeid yd
        , "description" .= description yd
        , "duedate" .= duedate yd
        , "completed" .= completed yd
        ]

newtype YoudoID = YoudoID Int deriving (Eq)
instance Show YoudoID where
    show (YoudoID n) = show n
instance FromField YoudoID where
    fromField fld = (fmap.fmap) YoudoID $ fromField fld
instance ToField YoudoID where
    toField (YoudoID n) = toField n
instance ToJSON YoudoID where
    toJSON (YoudoID n) = toJSON n
instance FromJSON YoudoID where
    parseJSON x = YoudoID <$> parseJSON x
instance Parsable YoudoID where
    parseParam x = YoudoID <$> parseParam x

data YoudoData = YoudoData { assignerid :: UserID
                           , assigneeid :: UserID
                           , description :: String
                           , duedate :: DueDate
                           , completed :: Bool
                           } deriving (Show)

data YoudoUpdate = YoudoUpdate { newAssignerid :: Maybe UserID
                               , newAssigneeid :: Maybe UserID
                               , newDescription :: Maybe String
                               , newDuedate :: Maybe DueDate
                               , newCompleted :: Maybe Bool
                               } deriving (Show)

type User = Versioned UserID UserData
instance NamedResource UserID where
    resourceName = const "users"
instance FromRow User where
    fromRow = Versioned <$> (VersionedID <$> field <*> field)
                        <*> (UserData <$> field)
instance ToJSON UserData where
    toJSON yduser = object [ "name" .= name yduser ]

newtype UserID = UserID Int deriving (Show, Eq)
instance FromField UserID where
    fromField fld = (fmap.fmap) UserID $ fromField fld
instance ToField UserID where
    toField (UserID n) = toField n
instance ToJSON UserID where
    toJSON (UserID n) = toJSON n
instance FromJSON UserID where
    parseJSON x = UserID <$> parseJSON x
instance Parsable UserID where
    parseParam x = UserID <$> parseParam x

data UserData = UserData { name :: String }
    deriving (Show, Eq)

data UserUpdate = UserUpdate { newName :: Maybe String } deriving (Show, Eq)

-- This newtype avoids orphan instances.
newtype DueDate = DueDate { toMaybeTime :: Maybe UTCTime } deriving (Eq, Show)
instance Parsable DueDate where
    parseParam "" = Right $ DueDate Nothing
    parseParam t = either (Left . LT.pack)
                          (Right . DueDate . Just)
                          $ parseUTCTime t
instance ToJSON DueDate where
    toJSON (DueDate Nothing) = Null
    toJSON (DueDate (Just t)) = toJSON t
instance FromJSON DueDate where
    parseJSON Null = DueDate <$> pure Nothing
    parseJSON (String t) = either fail return $
        DueDate . Just <$> parseUTCTime (LT.fromStrict t)
    parseJSON x = typeMismatch "String or Null" x

instance FromField DueDate where
    fromField fld = (fmap.fmap) DueDate $ fromField fld
instance ToField DueDate where
    toField (DueDate t) = toField t
