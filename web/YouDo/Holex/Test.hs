module YouDo.Holex.Test where
import Control.Applicative ((<$>), (<*>))
import Control.Monad.Writer.Lazy (runWriter)
import Distribution.TestSuite
import Data.Monoid (Sum(..))
import YouDo.Holex

tests :: IO [Test]
tests = return
    [ plainTest "evaluate Holex" $
        let expr :: Holex String Int Int
            expr = (+) <$> Hole "a" id
                       <*> Hole "b" id
            result = case runHolex expr [("a", 3), ("b", 2)] of
                        Left errs -> Fail (show errs)
                        Right n -> n ~= 5
        in return result
    , plainTest "Holex fill1" $
        let expr :: Holex String Int Int
            expr = (+) <$> Hole "a" id
                       <*> ((*) <$> Hole "b" id <*> Hole "a" id)
            result = map (getSum . snd . runWriter . (\k -> fill1 expr k 3))
                         ["a","b","c"]
                     ~= [2,1,0]
        in return result
    ]

(~=) :: (Eq a, Show a) => a -> a -> Result
x ~= y = if x == y then Pass else Fail $ (show x) ++ " /= " ++ (show y)

plainTest :: String -> IO Result -> Test
plainTest testName f = Test $ TestInstance
    { run = Finished <$> f
    , name = testName
    , tags = []
    , options = []
    , setOption = \_ _ -> Left "no options supported"
    }
