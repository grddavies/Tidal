{-
    Sequence.hs - core representation of Tidal sequences
    Copyright (C) 2022 Alex McLean and contributors

    This library is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this library.  If not, see <http://www.gnu.org/licenses/>.
-}

{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Avoid lambda" #-}
{-# OPTIONS_GHC -Wno-incomplete-patterns #-}

module Sound.Tidal.Sequence where

import Data.List(inits)
import Prelude hiding (span)
import Data.Ratio
import Sound.Tidal.Bjorklund

data Strategy = JustifyLeft
              | JustifyRight
              | JustifyBoth
              | Expand
              | TruncateMax
              | TruncateMin
              | RepeatLCM
              | Centre
              | Squeeze
              deriving Show

data Sequence a = Atom Rational a
                | Gap Rational
                | Sequence [Sequence a]
                | Stack [Sequence a]
              deriving Show



instance Functor Sequence where
  fmap f (Atom x y) = Atom x (f y)
  fmap f (Gap x) = Gap x
  fmap f (Sequence x) = Sequence $ map (fmap f) x
  fmap f (Stack y) = Stack (map (fmap f) y)

instance Applicative Sequence where
  pure x = Atom 1 x
  (Atom x f) <*> something =
    let (p,q) = forTwo (Atom x f) something
        c = reAlign p q
        d = Sequence $ unwrap $ map (fmap f) c
    in d
  Gap x <*> something =
    let (p,q) = forTwo (Gap x) something
    in Sequence $ unwrap p
  Sequence f <*> something =
    let (p,q) = forTwo (Sequence f) something
        c = unwrap $ reAlign p q
        d = Sequence$unwrap  $ funcMap p c
    in d
  Stack f <*> something =
    let d = map (<*> something) f
    in Stack d

instance Monad Sequence where
  return x = Atom 1 x
  Atom x y >>= f = f y
  Gap x >>= f = Gap x
  Sequence x >>= f = Sequence $ map (>>= f) x
  Stack y >>= f = Stack (map (>>= f) y)

-- | Takes sequence of functions and a sequence which have been aligned and applies the functions at the corresponding time points
funcMap :: [Sequence (a->b)] -> [Sequence a] -> [Sequence b]
funcMap [] _ = []
funcMap ((Atom x f):xs) y =
  let t = seqSpan (Atom x f)
      p = takeWhile (\q -> sum(map seqSpan q) <= t) $ inits y
      pTill = last p
      q = map (\x -> fmap f x) pTill
  in q ++ funcMap xs (drop (length pTill) y)
funcMap (Gap x:xs) y=
  let t = seqSpan (Gap x)
      p = takeWhile (\q -> sum(map seqSpan q) <= t) $ inits y
      pTill = last p
      q = Gap (sum $ map seqSpan pTill)
  in q : funcMap xs (drop (length pTill) y)

-- | Takes two sequences, which have been obtained using stratApply, or forTwo, and then splits the second sequence with respect
-- to the break points of the first
reAlign:: [Sequence a] -> [Sequence b] -> [Sequence b]
reAlign [] _ = []
reAlign a@((Gap x):xs) y =
  let t = seqSpan (Gap x)
      p  = takeWhile (\q -> sum (map seqSpan q) <=t ) $ inits y
      pTill = last p
      l = length pTill
      tTill = sum (map seqSpan pTill)
      (a,b) = if tTill == t then (Gap 0, drop l y)  else
        let (m,n) =  getPartition (y!!l) (t - tTill)
        in (m, n :drop (l+1) y)
  in if tTill == t then pTill ++ reAlign xs b else (pTill ++ [a]) ++ reAlign xs b
reAlign a@((Atom x s):xs) y =
  let t = seqSpan (Atom x s)
      p  = takeWhile (\q -> sum (map seqSpan q) <=t ) $ inits y
      pTill = last p
      l = length pTill
      tTill = sum (map seqSpan pTill)
      (a,b) = if tTill == t then (Gap 0, drop l y)  else
        let (m,n) =  getPartition (y!!l) (t - tTill)
        in (m, n :drop (l+1) y)
  in (pTill ++ [a]) ++ reAlign xs b

-- | Function to partition an event in a sequence
getPartition::Sequence a-> Rational -> (Sequence a, Sequence a)
getPartition (Atom x s) t = (Atom t s, Atom (x-t) s)
getPartition (Gap x) t = (Gap t, Gap (x - t))
getPartition (Sequence y) t =
  let p = takeWhile (\q -> sum (map seqSpan q) <=t ) $ inits y
      pTill = last p
      l = length pTill
      tTill = sum (map seqSpan pTill)
      (a,b) = if tTill == t then (Gap 0, drop l y)  else
        let (m,n) =  getPartition (y!!l) (t - tTill)
        in (m, n :drop (l+1) y)
  in (Sequence $ pTill ++ [a], Sequence b)

-- | Given two sequences of different types, this function uses the LCM method to align those two sequences
forTwo :: Sequence a1 -> Sequence a2 -> ([Sequence a1], [Sequence a2])
forTwo a b =
  let p = lcmRational (seqSpan a) (seqSpan b)
  in (unwrap $ replicate (fromIntegral  $ numerator $ p/seqSpan a) a, unwrap $ replicate (fromIntegral $ numerator $ p/seqSpan b) b)


-- | Unwrapping a sequence referes to removing the redundancies that are present in the code
unwrap:: [Sequence a] -> [Sequence a]
unwrap [] = []
unwrap [Sequence x] = unwrap x
unwrap (Sequence x :xs) = unwrap x ++ unwrap xs
unwrap (Atom x s:xs) = Atom x s : unwrap xs
unwrap (Gap x:xs) = if x ==0 then unwrap xs else Gap x: unwrap xs

rev :: Sequence a -> Sequence a
rev (Sequence bs) = Sequence $ reverse $ map rev bs
rev (Stack bs) = Stack $ map rev bs
rev b = b

cat :: [Sequence a] -> Sequence a
cat [] = Gap 0
cat [b] = b
cat bs = Sequence bs

ply :: Int -> Sequence a -> Sequence a
ply n (Atom d v) = Sequence $ replicate n $ Atom (d / toRational n) v

seqSpan :: Sequence a -> Rational
seqSpan (Atom s _) = s
seqSpan (Gap s) = s
seqSpan (Sequence bs) = sum $ map seqSpan bs
seqSpan (Stack []) = 0
seqSpan (Stack x) = seqSpan $ head x

lcmRational :: Rational->Rational-> Rational
lcmRational a b = lcm (f a) (f b) % d
  where d = lcm (denominator a) (denominator b)
        f x = numerator x * (d `div` denominator x)

-- | stratApply takes a list of sequences, a strategy, and then aligns all those sequences according to these strategies
stratApply::Strategy -> [Sequence a] ->Sequence a
stratApply JustifyLeft bs =
  let a = maximum $ map seqSpan bs
      b = map (\x -> Sequence (x: [Gap (a - seqSpan x)])) bs
  in Stack b

stratApply JustifyRight bs =
  let a = maximum $ map seqSpan bs
      b = map (\x -> Sequence (Gap (a - seqSpan x) : [x])) bs
  in Stack b

stratApply Centre bs =
  let a = maximum $ map seqSpan bs
      b = map( \x -> Sequence ([Gap ((a - seqSpan x)/2)] ++ [x] ++ [Gap ((a - seqSpan x)/2)])) bs
  in Stack b

stratApply RepeatLCM bs@(x:xs) =
  let a = foldr (lcmRational . seqSpan) (seqSpan x) xs
      b = map (\x ->  Sequence $ unwrap $  replicate (fromIntegral $ numerator $ a/seqSpan x) x) bs
  in Stack b

stratApply Expand bs =
  let a = maximum $ map seqSpan bs
      b = map (\x -> expand x $ a/seqSpan x) bs
  in Stack b

stratApply Squeeze bs =
  let a = minimum $ map seqSpan bs
      b = map (\x -> expand x $ a/seqSpan x) bs
  in Stack b

stratApply JustifyBoth bs =
  let a = maximum $ map seqSpan bs
      b = map (`expand'` a) bs
  in Stack b

stratApply TruncateMin bs =
  let a = minimum $ map seqSpan bs
      b = map (`cutShort` a) bs
  in Stack b

stratApply TruncateMax bs =
  let a = maximum $ map seqSpan bs
      b = map (\x -> Sequence $ unwrap $ replicate (floor $ a/seqSpan x) x ++ let Sequence p = cutShort x (realToFrac (a - floor (a/seqSpan x)%1 * seqSpan x)) in p) bs
  in Stack b

-- Return a segment of a sequence
cutShort::Sequence a->Rational->Sequence a
cutShort (Atom x s) r = Atom r s
cutShort (Gap x) r = Gap r
cutShort (Sequence x) r =
  let p = takeWhile (\q -> sum (map seqSpan q) <=r ) $ inits x
      pTill = last p
      l = length pTill
      tTill = sum (map seqSpan pTill)
      (a,b) = if tTill == r then (Gap 0, drop l x)  else
        let (m,n) =  getPartition (x!!l) (r - tTill)
        in (m, n :drop (l+1) x)
  in if tTill == r then Sequence pTill else Sequence $ pTill ++ [fst (getPartition (x!!l) (r - tTill))]
cutShort (Stack x) r = Stack $ map (`cutShort` r) x

-- | Expand a sequence to a particular length, while not modifying the length of that sequence
expand'::Sequence a -> Rational -> Sequence a
expand' (Atom x s) r = expand (Atom x s) $ r/seqSpan (Atom x s)
expand' (Gap x) r = expand (Gap x) $ r/seqSpan (Gap x)
expand' (Sequence [x]) r = Sequence [expand x (r/seqSpan x)]
expand' (Sequence x) r =
  let Sequence y = (expand (Sequence $ init x) $ (r- seqSpan (last x))/ seqSpan (Sequence $ init x))
  in Sequence (y++ [last x])
expand' (Stack x) r = Stack $ map (`expand'` r) x

-- | Expand a sequence to a particular length
expand::Sequence a-> Rational -> Sequence a
expand (Atom x s) r = Atom (x*r) s
expand (Gap x) r = Gap (x*r)
expand (Sequence x) r = Sequence $ map (`expand` r) x
expand (Stack x) r = Stack $ map (`expand` r) x

-- | Reduce a Sequence of sequences by using reduce
reduceSeq ::Eq a=> Sequence a -> Sequence a
reduceSeq (Sequence x) = Sequence $ reduce x

-- | Reduce a list of sequences by removing redundancies
reduce::Eq a=>[Sequence a] -> [Sequence a]
reduce ((Atom x1 s1):(Atom x2 s2):xs) = if s1==s2 then reduce $ Atom (x1+x2) s1:xs else Atom x1 s1:reduce ( Atom x2 s2:  xs)
reduce (Gap x1:Gap x2:xs) =reduce $ Gap (x1+x2):xs
reduce (Sequence x:xs) = Sequence (reduce x):reduce xs
reduce (Stack x:xs) = Stack (reduce x):reduce xs
reduce (x:xs) = x:reduce xs
reduce [] = []

-- | Speed up the sequence
fast::Rational->Sequence a-> Sequence a
fast n (Atom x s) = Atom (x/n) s
fast n (Gap x) = Gap (x/n)
fast n (Sequence s) = Sequence $ map (\y -> fast n y) s
fast n (Stack x) = Stack $ map(\y -> fast n y) x

-- | Slow down the sequence
slow::Rational->Sequence a->Sequence a
slow n = fast (1/n)

-- | Repeat the sequence a desired number of times without changing duration
rep::Eq a=>Int -> Sequence a-> Sequence a
rep n (Atom x s) = Atom (realToFrac n * x) s
rep n (Gap x) = Gap (realToFrac  n*x)
rep n (Sequence s) = Sequence $ reduce $  concat $ replicate n s
rep n (Stack s) = Stack $ map (\x-> rep n x) s

-- | Repeat sequence desired number of times, and squeeze it into the duration of the original sequence
repSqueeze::Eq a=>Int -> Sequence a-> Sequence a
repSqueeze n s = fast (realToFrac n) $ rep n s

-- | Takes a list of sequences, and if aligned returns a stack. Otherwise applies default method and returns
stack::[Sequence a] -> Sequence a
stack s =
  let a = foldl (\acc x->if seqSpan x==acc then acc else -1) (seqSpan $ head s) s
  in if a == (-1) then stratApply Expand s else Stack s

-- | Obtain a euclidean pattern
euclid::(Int, Int)-> Sequence String
euclid (a,b)  =
  let x = bjorklund (a, b)
      y = map (\t -> if t then Atom 1 "x" else Gap 1) x
  in Sequence $ reduce y

{-
   EXISTING STUFF IN TIDAL
   Method for showing
   [] -> Play in to fit that measure - I think this is actually the same as Sequence [Sequence a]
   *n -> plays it n times within the step - replaced by repSqueeze 
   /m -> Plays only once in m steps
   !n -> Repeat it n times -Replaced by rep
   [,] -> Overlays(Polyrhythm) - JustifyBoth does this
   {,} -> Polymeter - repeatLCM does this
   < > Plays one among for each iteration
   () -> Euclidean structures
   -}

{-
  New stuff that I would like to add
  * Method which takes an integer and splits sequence recursively at those intervals (fitToTime)
  * 
-}