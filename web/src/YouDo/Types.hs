{-# LANGUAGE OverloadedStrings, FlexibleInstances, FlexibleContexts,
    MultiParamTypeClasses #-}
module YouDo.Types where

import Control.Applicative ((<$>), (<*>), pure)
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), object, Value(..))
import Data.Aeson.Types (typeMismatch)
import Data.Default
import Data.Maybe (fromMaybe)
import Data.String
import qualified Data.Text.Lazy as LT
import Data.Time (UTCTime)
import Database.PostgreSQL.Simple.FromField (FromField(..))
import Database.PostgreSQL.Simple.FromRow (FromRow(..), field)
import Database.PostgreSQL.Simple.ToField (ToField(..))
import Web.Scotty (Parsable(..))

import YouDo.DB
import YouDo.Holex
import YouDo.TimeParser (parseUTCTime)
import YouDo.Web (parse, ParamValue, BasedToJSON(..))

data ( DB YoudoID YoudoData YoudoUpdate IO yd
     , DB UserID UserData UserUpdate IO ud
     ) => YoudoDatabase yd ud = YoudoDatabase { youdos :: yd, users :: ud }

type Youdo = Versioned YoudoID YoudoData
instance NamedResource YoudoID where
    resourceName = const "youdos"
instance FromRow Youdo where
    fromRow = Versioned <$> (VersionedID <$> field <*> field)
        <*> (YoudoData <$> field <*> field <*> field <*> field <*> field)
instance BasedToJSON YoudoData where
    basedToJSON yd = do
        assigner <- basedToJSON $ assignerid yd
        assignee <- basedToJSON $ assigneeid yd
        return $ object
            [ "assigner" .= assigner
            , "assignee" .= assignee
            , "description" .= description yd
            , "duedate" .= duedate yd
            , "completed" .= completed yd
            ]

newtype YoudoID = YoudoID Int deriving (Eq)
instance Show YoudoID where
    show (YoudoID n) = show n
instance BasedToJSON YoudoID where
    basedToJSON = idjson
instance FromField YoudoID where
    fromField fld = (fmap.fmap) YoudoID $ fromField fld
instance ToField YoudoID where
    toField (YoudoID n) = toField n
instance FromJSON YoudoID where
    parseJSON x = YoudoID <$> parseJSON x
instance Parsable YoudoID where
    parseParam x = YoudoID <$> parseParam x
instance (IsString k, Eq k) => Default (Holex k ParamValue YoudoID) where
    def = parse "id"

data YoudoData = YoudoData { assignerid :: UserID
                           , assigneeid :: UserID
                           , description :: String
                           , duedate :: DueDate
                           , completed :: Bool
                           } deriving (Show)
instance (IsString k, Eq k) => Default (Holex k ParamValue YoudoData) where
    def = YoudoData <$> parse "assignerid"
                    <*> parse "assigneeid"
                    <*> defaultTo "" (parse "description")
                    <*> defaultTo (DueDate Nothing) (parse "duedate")
                    <*> defaultTo False (parse "completed")

data YoudoUpdate = YoudoUpdate { newAssignerid :: Maybe UserID
                               , newAssigneeid :: Maybe UserID
                               , newDescription :: Maybe String
                               , newDuedate :: Maybe DueDate
                               , newCompleted :: Maybe Bool
                               } deriving (Show)
instance (IsString k, Eq k)
         => Default (Holex k ParamValue (Versioned YoudoID YoudoUpdate)) where
    def = Versioned <$> (VersionedID <$> parse "id"
                                     <*> parse "txnid")
                    <*> (YoudoUpdate <$> optional (parse "assignerid")
                                     <*> optional (parse "assigneeid")
                                     <*> optional (parse "description")
                                     <*> optional (parse "duedate")
                                     <*> optional (parse "completed"))

instance Updater YoudoUpdate YoudoData where
    doUpdate upd yd =
        yd { assignerid = fromMaybe (assignerid yd) (newAssignerid upd)
           , assigneeid = fromMaybe (assigneeid yd) (newAssigneeid upd)
           , description = fromMaybe (description yd) (newDescription upd)
           , duedate = fromMaybe (duedate yd) (newDuedate upd)
           , completed = fromMaybe (completed yd) (newCompleted upd)
           }

type User = Versioned UserID UserData
instance NamedResource UserID where
    resourceName = const "users"
instance FromRow User where
    fromRow = Versioned <$> (VersionedID <$> field <*> field)
                        <*> (UserData <$> field)
instance BasedToJSON UserData where
    basedToJSON yduser = return $ object [ "name" .= name yduser ]

newtype UserID = UserID Int deriving (Eq)
instance Show UserID where
    show (UserID n) = show n
instance BasedToJSON UserID where
    basedToJSON = idjson
instance FromField UserID where
    fromField fld = (fmap.fmap) UserID $ fromField fld
instance ToField UserID where
    toField (UserID n) = toField n
instance FromJSON UserID where
    parseJSON x = UserID <$> parseJSON x
instance Parsable UserID where
    parseParam x = UserID <$> parseParam x
instance (IsString k, Eq k) => Default (Holex k ParamValue UserID) where
    def = parse "id"

data UserData = UserData { name :: String }
    deriving (Show, Eq)
instance (IsString k, Eq k) => Default (Holex k ParamValue UserData) where
    def = UserData <$> parse "name"

data UserUpdate = UserUpdate { newName :: Maybe String } deriving (Show, Eq)

instance (IsString k, Eq k) => Default (Holex k ParamValue (Versioned UserID UserUpdate)) where
    def = Versioned <$> (VersionedID <$> parse "id"
                                      <*> parse "txnid")
                    <*> (UserUpdate <$> optional (parse "name"))

instance Updater UserUpdate UserData where
    doUpdate upd u = case newName upd of
        Nothing -> u
        Just n -> u { name = n }

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
