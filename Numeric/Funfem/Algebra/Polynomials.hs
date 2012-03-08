{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
---------------------------------------------------------------------------------- 
-- |
-- Module : Numeric.Funfem.Algebra.Polynomials
-- Copyright : (c) Adrien Haxaire 2012
-- Licence : BSD3
--
-- Maintainer : Adrien Haxaire <adrien@funfem.org>
-- Stability : experimental
-- Portabilty : not tested
-- 
-- Multivariate polynomials. Defined to represent shape functions, allowing
-- their exact multiplication, addition and integration. 
-- 
-- A barebone Num instance is provided, but the functions 'add', 'substract'
-- and 'mult' are provided for comodity.
--
module Numeric.Funfem.Algebra.Polynomials (
                                           Polynomial
                                           ,Evaluation
                                           ,mkPolynomial
                                           ,mkEvaluation
                                           ,differentiate
                                           ,integrate
                                           ,evaluate
                                           ,evaluateMat
                                           ,add
                                           ,substract
                                           ,mult
                                           ,multMat
                                           ,variables
                                          ) where

import qualified Data.Map as M
import Data.List (delete, nub, transpose) 
import Data.Maybe

-- | Representation of a multivariate polynomial.
type Polynomial = M.Map String Double

-- | Helper function to create a 'Polynomial' from an association list.
mkPolynomial :: [(String, Double)] -> Polynomial
mkPolynomial = M.fromList 

-- | Type alias to evaluate a 'Polynomial '. See the 'evaluate' function for an example of usage.
type Evaluation = M.Map Char Double

-- | Helper function to create an 'Evaluation' from an association list.
mkEvaluation :: [(Char, Double)] -> Evaluation
mkEvaluation = M.fromList

-- count the occurences of a monomial in a term
occ :: Char -> String -> Double 
occ _ [] = 0.0
occ c (x:xs) = let n = if c == x then 1.0 else 0.0 in n + occ c xs

-- | The 'differentiate' function calculates the derivative of a 'Polynomial' with respect to a given variable.
--
-- > let p = mkPolynomial [("",1.0), ("x",2.0), ("y",3.0), ("xy",4.0), ("xxy",5.0)]
-- > differentiate p 'x' == mkPolynomial [("",2.0),("xy",10.0),("y",4.0)]
-- > differentiate p 'y' == mkPolynomial [("",3.0),("x",4.0),("xx",5.0)]
differentiate :: Polynomial -> Char -> Polynomial
differentiate p c = M.mapKeys (delete c) $
                    M.mapWithKey (\ k v -> (occ c k) * v) $
                    M.filterWithKey (\ k _ -> c `elem` k) p

-- | The 'integrate' function calculates the integral of a 'Polynomial' with respect to a given variable.
--
-- > let p = mkPolynomial [("",1.0), ("x",2.0), ("y",3.0), ("xy",4.0)]
-- > integrate p 'x' == mkPolynomial [("x",1.0),("xx",1.0),("xxy",2.0),("xy",3.0)]
-- > integrate p 'y' == mkPolynomial [("y",1.0),("yx",2.0),("yxy",2.0),("yy",1.5)]
integrate :: Polynomial -> Char -> Polynomial
integrate p c = M.mapKeys (c:) $ M.mapWithKey (\ k v -> v / (occ c k + 1.0)) p

-- | The 'evaluate' function evaluates a 'Polynomial' at a point defined through the 'Evaluation' type alias:
--
-- > let p = mkPolynomial [("",1.0), ("x",2.0), ("y",3.0), ("xy",4.0), ("xxy",5.0)]
-- > let e = mkEvaluation [('x',2.0), ('y',1.0)]
-- > evaluate p e == 36.0
evaluate :: Polynomial -> Evaluation -> Double
evaluate p e = M.foldl (+) 0.0 $ evals p e

evals :: Polynomial -> Evaluation -> Polynomial
evals p e = evals' p e $ M.keys e
    where
      evals' q _ [] = q
      evals' q ev (c:cs) = evals' (eval q ev c) ev cs                 

eval :: Polynomial -> Evaluation -> Char -> Polynomial
eval p e c = M.mapWithKey f p
    where
      f k v = v * (x ** (occ c k))
      x = fromJust $ M.lookup c e

-- | Evaluation of a matrix of 'Polynomial's.
evaluateMat :: [[Polynomial]] -> Evaluation -> [[Double]]
evaluateMat m e = [map (\q -> evaluate q e) p | p <- m]


instance Num Polynomial where
    p + q = add p q
    p * q = mult p q
    negate = M.map negate
    signum = M.map signum 
    fromInteger = undefined         
    abs = M.map abs

-- | Addition of two 'Polynomial's.
--
-- > let p = mkPolynomial [("",1.0), ("x",2.0), ("y",3.0)]
-- > let q = mkPolynomial [("x",2.0), ("xy",4.0)]
-- > add p q == mkPolynomial [("",1.0),("x",4.0),("xy",4.0),("y",3.0)]
add :: Polynomial -> Polynomial -> Polynomial
add p q = M.unionWith (+) p q

-- | Substraction of two 'Polynomial's.
--
-- > let p = mkPolynomial [("",1.0), ("x",2.0), ("y",3.0)] 
-- > let q = mkPolynomial [("x",2.0), ("xy",4.0)]
-- > substract p q == mkPolynomial [("",1.0),("x",0.0),("xy",4.0),("y",3.0)]
substract :: Polynomial -> Polynomial -> Polynomial
substract p q = add p $ M.map negate q

-- | Multiplication of two 'Polynomial's.
--
-- > let p = mkPolynomial [("",1.0), ("x",2.0), ("y",3.0)]
-- > let q = mkPolynomial [("x",2.0), ("xy",4.0)]
-- > mult p q == mkPolynomial [("x",2.0),("xx",4.0),("xxy",8.0),("xy",4.0),("yx",6.0),("yxy",12.0)]
mult :: Polynomial -> Polynomial -> Polynomial
mult p q = mult' p q $ M.keys p
    where
      mult' _ _ [] = mkPolynomial []
      mult' p' q' (key:keys) = add (M.map (* (p' M.! key)) $ M.mapKeys (key ++) q') (mult' p' q' keys)

-- Equivalent of a dot product between two vectors
inner :: [Polynomial] -> [Polynomial] -> Polynomial
inner [] _ = mkPolynomial []
inner _ [] = mkPolynomial []
inner (p:ps) (q:qs) = add (M.unionWith (*) p q) $ inner ps qs


-- | Multiplication of two 'Polynomial' matrices.
multMat :: [[Polynomial]] -> [[Polynomial]] -> [[Polynomial]]
multMat matp matq = map row matp 
    where
      row p = map (inner p) $ transpose matq

-- | The 'variables' function returns the list of variables used to 
-- define a 'Polynomial'.
--
-- > let p = mkPolynomial [("",1.0),("x",4.0),("xy",4.0),("y",3.0)]
-- > variables p == "xy"
variables :: Polynomial -> [Char]
variables = nub . concat . M.keys




