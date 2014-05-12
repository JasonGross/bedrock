(* FastString -- speedy versions of string functions from String

This library defines tail-recursive, unverified versions of some of the
functions in String.  It's intended to be used in unverified applications
(e.g., the Bedrock assembly generator) where speed is important. *)

Require Import Ascii List.
Require Export String.

Section Local.

  Fixpoint foldString {A} (f : A -> ascii -> A) (str : string) (zero : A) : A :=
    match str with
      | EmptyString => zero
      | String character str' => foldString f str' (f zero character)
    end.

  Definition prependReversed : string -> string -> string :=
    foldString (fun char str => String str char).

End Local.

Definition reverse str := prependReversed str "".

Definition concat (strs : list string) : string :=
  reverse (fold_left (fun x y => prependReversed y x) strs ""%string).

Definition append x y := concat (x :: y :: nil).
Infix "++" := append : string_scope.
