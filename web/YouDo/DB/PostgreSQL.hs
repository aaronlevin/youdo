{-# LANGUAGE OverloadedStrings, MultiParamTypeClasses #-}
module YouDo.DB.PostgreSQL where
import Control.Applicative ((<$>))
import Database.PostgreSQL.Simple (query, query_, execute, withTransaction,
    Only(..), Connection, Query)
import YouDo.Types

newtype PostgresYoudoDB = PostgresYoudoDB Connection
instance DB YoudoID YoudoData YoudoUpdate IO PostgresYoudoDB where
    get ydid (PostgresYoudoDB conn) =
        one <$> query conn
              "select id, txnid, assignerid, assigneeid, description, duedate, completed \
              \from youdo where id = ?"
              (Only ydid)
    getAll (PostgresYoudoDB conn) = GetResult <$> Result <$> Right <$> query_ conn
        "select id, assignerid, assigneeid, description, duedate, completed \
        \from youdo"
    post yd (PostgresYoudoDB conn) = do
        withTransaction conn $ do
            _ <- execute conn
                    ("insert into transaction (yd_userid, yd_ipaddr, yd_useragent) \
                    \values (?, ?, ?)"::Query)
                    (0::Int, "127.0.0.1"::String, "some agent"::String)
            ids <- query conn
                "insert into youdo \
                \(assignerid, assigneeid, description, duedate, completed) \
                \values (?, ?, ?, ?, ?) returning id"
                (assignerid yd, assigneeid yd, description yd,
                duedate yd, completed yd)
                :: IO [Only YoudoID]
            return $ fromOnly $ head ids
newtype PostgresUserDB = PostgresUserDB Connection
instance DB UserID UserData UserUpdate IO PostgresUserDB where
    get uid (PostgresUserDB conn) =
        one <$> query conn
              "select id, name from yd_user where id = ?"
              (Only uid)
