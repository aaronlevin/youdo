{-# LANGUAGE MultiParamTypeClasses #-}
module YouDo.DB.Mock where

import Prelude hiding (id)
import Control.Applicative ((<$>))
import Control.Concurrent.MVar (MVar, withMVar, modifyMVar, newMVar)
import Data.Function (on)
import Data.List (nubBy)
import Data.Maybe (listToMaybe)
import YouDo.Types

data BareMockDB = BareMockDB
    { youdos :: [Youdo]
    , users :: [User]
    , lasttxn :: TransactionID
    }
data MockDB = MockDB { mvar :: MVar BareMockDB }

newtype MockYoudoDB = MockYoudoDB { ymock :: MockDB }
instance DB YoudoID YoudoData YoudoUpdate IO MockYoudoDB where
    get ydid db = withMVar (mvar $ ymock db) $ \db' ->
        return $ one $ [yd | yd<-youdos db', thingid (version yd) == ydid]
    getVersions ydid db = withMVar (mvar $ ymock db) $ \db' ->
        return $ some $ [yd | yd<-youdos db', thingid (version yd) == ydid]
    getVersion ydver db = withMVar (mvar $ ymock db) $ \db' ->
        return $ one $ [yd | yd<-youdos db', version yd == ydver]
    getAll db = withMVar (mvar $ ymock db) $ \db' ->
        return $ GetResult $ Result $ Right
               $ nubBy ((==) `on` thingid . version) $ youdos db'
    post yd db = modifyMVar (mvar $ ymock db) $ \db' -> do
        let newid = YoudoID $
                1 + case thingid . version <$> (listToMaybe $ youdos db') of
                        Nothing -> 0
                        Just (YoudoID n) -> n
            newtxn = TransactionID $
                1 + case lasttxn db' of TransactionID n -> n
            newy = Versioned (VersionedID newid newtxn) yd
        return ( db' { youdos = newy : (youdos db')
                     , lasttxn = newtxn
                     }
               , PostResult $ Result $ Right $ newy
               )
    update upd db = modifyMVar (mvar $ ymock db) $ \db' -> do
        let oldyd = listToMaybe
                [yd | yd<-youdos db'
                    , thingid (version yd) == thingid (oldVersion upd)]
        case oldyd of
            Nothing -> return (db', UpdateResult $ Result $ Left $ SpecialError $ NotFound_Upd)
            Just theyd -> if version theyd /= oldVersion upd
                            then return (db', UpdateResult $ Result $ Left $ SpecialError
                                              $ NewerVersion $ theyd)
                            else let newyd = Versioned
                                        (VersionedID (thingid (version theyd)) newtxn)
                                        (doUpdate upd (thing theyd))
                                     newtxn = TransactionID $
                                         1 + case lasttxn db' of TransactionID n -> n
                                 in return (db' { youdos = newyd : (youdos db')
                                                , lasttxn = newtxn
                                                }
                                           , UpdateResult $ Result $ Right $ newyd
                                           )

newtype MockUserDB = MockUserDB { umock :: MockDB }
instance DB UserID UserData UserUpdate IO MockUserDB where
    get uid db = withMVar (mvar $ umock db) $ \db' ->
        return $ one $ [u | u<-users db', thingid (version u) == uid]
    getVersion verid db = withMVar (mvar $ umock db) $ \db' ->
        return $ one $ [u | u<-users db', version u == verid]
    getVersions verid db = withMVar (mvar $ umock db) $ \db' ->
        return $ some $ [u | u<-users db', thingid (version u) == verid]
    post ud db = modifyMVar (mvar $ umock db) $ \db' -> do
        let newid = UserID $
                1 + case thingid . version <$> (listToMaybe $ users db') of
                        Nothing -> 0
                        Just (UserID n) -> n
            newtxn = TransactionID $
                1 + case lasttxn db' of TransactionID n -> n
            newu = Versioned (VersionedID newid newtxn) ud
        return ( db' { users = newu : (users db')
                     , lasttxn = newtxn
                     }
               , PostResult $ Result $ Right newu
               )
    update upd db = modifyMVar (mvar $ umock db) $ \db' -> do
        let oldu = listToMaybe
                [u | u<-users db'
                    , thingid (version u) == thingid (oldUserVersion upd)]
        case oldu of
            Nothing -> return (db', UpdateResult $ Result $ Left $ SpecialError NotFound_Upd)
            Just theu -> if version theu /= oldUserVersion upd
                            then return (db', UpdateResult $ Result $ Left $ SpecialError
                                              $ NewerVersion $ theu)
                            else let newu = Versioned
                                        (VersionedID (thingid (version theu)) newtxn)
                                        (doUpdate upd (thing theu))
                                     newtxn = TransactionID $
                                         1 + case lasttxn db' of TransactionID n -> n
                                 in return (db' { users = newu : (users db')
                                                , lasttxn = newtxn
                                                }
                                           , UpdateResult $ Result $ Right $ newu
                                           )

class Updater u d where
    doUpdate :: u -> d -> d
instance Updater YoudoUpdate YoudoData where
    doUpdate upd yd =
        (\yd -> case newAssignerid upd of
                    Nothing -> yd
                    Just assigner -> yd { assignerid = assigner })
        $ (\yd -> case newAssigneeid upd of
                    Nothing -> yd
                    Just assignee -> yd { assigneeid = assignee })
        $ (\yd -> case newDescription upd of
                    Nothing -> yd
                    Just descr -> yd { description = descr })
        $ (\yd -> case newDuedate upd of
                    Nothing -> yd
                    Just dd -> yd { duedate = dd })
        $ (\yd -> case newCompleted upd of
                    Nothing -> yd
                    Just c -> yd { completed = c })
        yd
instance Updater UserUpdate UserData where
    doUpdate upd u = case newName upd of
        Nothing -> u
        Just n -> u { name = n }

empty :: IO MockDB
empty = do
    mv <- newMVar $ BareMockDB
            { youdos = []
            , users = [Versioned (VersionedID (UserID 0)
                                              (TransactionID 0))
                                 (UserData "yddb")]
            , lasttxn = TransactionID 0
            }
    return $ MockDB mv
