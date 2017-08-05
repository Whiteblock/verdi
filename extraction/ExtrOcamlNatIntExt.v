Require Import PeanoNat.
Require Extraction.

Extract Inlined Constant Nat.max => "Pervasives.max".
Extract Inlined Constant Nat.min => "Pervasives.min".

Extract Inlined Constant Nat.ltb => "(<)".
