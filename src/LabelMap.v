(* Finite maps for labels *)

Require Import Ascii NArith String Structures.OrderedType FMapAVL.

Require Import Nomega IL.

Local Open Scope string_scope.
Local Open Scope N_scope.


Definition ascii_lt (a1 a2 : ascii) := N_of_ascii a1 < N_of_ascii a2.

Fixpoint string_lt (s1 s2 : string) : bool :=
  match s1, s2 with
    | "", String _ _ => true
    | String _ _, "" => false
    | String a1 s1', String a2 s2' => match (N_of_ascii a1) ?= (N_of_ascii a2) with
                                        | Datatypes.Lt => true
                                        | Gt => false
                                        | Datatypes.Eq => string_lt s1' s2'
                                      end
    | _, _ => false
  end.

Section CompSpec.
  Variables (A : Type) (eq lt : A -> A -> Prop) 
    (x y : A) (c : comparison).

  Hypothesis H : CompSpec eq lt x y c.

  Theorem Comp_eq : (forall z, lt z z -> False)
    -> x = y -> c = Datatypes.Eq.
    inversion H; intros; subst; auto; elimtype False; eauto.
  Qed.

  Theorem Comp_lt : (forall z z', lt z z' -> eq z z' -> False)
    -> (forall z z', lt z z' -> lt z' z -> False)
    -> lt x y -> c = Datatypes.Lt.
    inversion H; intros; subst; auto; elimtype False; eauto.
  Qed.

  Theorem Comp_gt : (forall z z', lt z' z -> eq z z' -> False)
    -> (forall z z', lt z z' -> lt z' z -> False)
    -> lt y x -> c = Datatypes.Gt.
    inversion H; intros; subst; auto; elimtype False; eauto.
  Qed.
End CompSpec.

Implicit Arguments Comp_eq [A eq0 lt x y c].
Implicit Arguments Comp_lt [A eq0 lt x y c].
Implicit Arguments Comp_gt [A eq0 lt x y c].

Theorem Nlt_irrefl' : forall n : N, n < n -> False.
  exact Nlt_irrefl.
Qed.

Theorem Nlt_irrefl'' : forall n n' : N, n = n' -> n < n' -> False.
  intros; subst; eapply Nlt_irrefl'; eauto.
Qed.

Theorem Nlt_notboth : forall x y, x < y -> y < x -> False.
  intros; eapply Nlt_irrefl'; eapply Nlt_trans; eauto.
Qed.

Hint Immediate Nlt_irrefl' Nlt_irrefl'' Nlt_notboth.

Ltac rewr' := eauto; congruence || eapply Nlt_trans; eassumption.

Ltac rewr := repeat match goal with
                      | [ _ : context[?X ?= ?Y] |- _ ] => specialize (Ncompare_spec X Y); destruct (X ?= Y); inversion 1
                    end; simpl in *; (rewrite (Comp_eq (@Ncompare_spec _ _)); rewr')
  || (rewrite (Comp_lt (@Ncompare_spec _ _)); rewr')
    || (rewrite (Comp_gt (@Ncompare_spec _ _)); rewr').

Theorem string_lt_trans : forall s1 s2 s3, string_lt s1 s2 = true
  -> string_lt s2 s3 = true
  -> string_lt s1 s3 = true.
  induction s1; simpl; intuition; destruct s2; destruct s3; simpl in *; try congruence; rewr.
Qed.

Section hide_hints.
  Hint Resolve string_lt_trans.

  Theorem string_lt_irrel : forall s, string_lt s s = false.
    induction s; simpl; intuition rewr.
  Qed.

  Hint Rewrite string_lt_irrel : LabelMap.

  Lemma string_tail_neq : forall a1 a2 s1 s2,
    N_of_ascii a1 = N_of_ascii a2
    -> (String a1 s1 = String a2 s2 -> False)
    -> (s1 = s2 -> False).
    intros.
    apply (f_equal ascii_of_N) in H.
    repeat rewrite ascii_N_embedding in H.
    congruence.
  Qed.

  Hint Immediate string_tail_neq.

  Theorem string_lt_sym : forall s1 s2, s1 <> s2
    -> string_lt s1 s2 = false
    -> string_lt s2 s1 = true.
    induction s1; destruct s2; simpl; intuition; rewr.
  Qed.
    
  Hint Resolve string_lt_sym.

  Definition label'_lt (l1 l2 : label') : bool :=
    match l1, l2 with
      | Global _, Local _ => true
      | Local _, Global _ => false
      | Global s1, Global s2 => string_lt s1 s2
      | Local n1, Local n2 => match n1 ?= n2 with
                                | Datatypes.Lt => true
                                | _ => false
                              end
    end.

  Theorem label'_lt_trans : forall l1 l2 l3, label'_lt l1 l2 = true
    -> label'_lt l2 l3 = true
    -> label'_lt l1 l3 = true.
    induction l1; simpl; intuition; destruct l2; destruct l3; simpl in *; try congruence; eauto; rewr.
  Qed.

  Hint Immediate label'_lt_trans.

  Theorem label'_lt_irrel : forall l, label'_lt l l = false.
    induction l; simpl; intuition; autorewrite with LabelMap; auto; rewr.
  Qed.

  Hint Rewrite label'_lt_irrel : LabelMap.

  Theorem label'_lt_sym : forall l1 l2, l1 <> l2
    -> label'_lt l1 l2 = false
    -> label'_lt l2 l1 = true.
    induction l1; destruct l2; simpl; intuition.
    eapply string_lt_sym; eauto; congruence.
    rewr.
  Qed.

  Hint Resolve label'_lt_sym.

  Definition label'_eq : forall x y : label', {x = y} + {x <> y}.
    decide equality; apply string_dec || apply N_eq_dec.
  Defined.
End hide_hints.

Module LabelKey.
  Definition t := label.

  Definition eq := @eq t.
  Definition lt (l1 l2 : label) := string_lt (fst l1) (fst l2) = true
    \/ (fst l1 = fst l2 /\ label'_lt (snd l1) (snd l2) = true).

  Theorem eq_refl : forall x : t, eq x x.
    congruence.
  Qed.

  Theorem eq_sym : forall x y : t, eq x y -> eq y x.
    congruence.
  Qed.

  Theorem eq_trans : forall x y z : t, eq x y -> eq y z -> eq x z.
    congruence.
  Qed.

  Section hide_hints.
    Hint Resolve string_lt_trans.
    Hint Rewrite string_lt_irrel : LabelMap.
    Hint Immediate string_tail_neq.
    Hint Resolve string_lt_sym.
    Hint Immediate label'_lt_trans.
    Hint Rewrite label'_lt_irrel : LabelMap.
    Hint Resolve label'_lt_sym.
    Hint Rewrite string_lt_irrel label'_lt_irrel : LabelMap.

    Theorem lt_trans : forall x y z : t, lt x y -> lt y z -> lt x z.
      unfold lt; intuition (congruence || eauto).
    Qed.

    Theorem lt_not_eq : forall x y : t, lt x y -> ~ eq x y.
      unfold lt, eq; intuition; subst; autorewrite with LabelMap in *; discriminate.
    Qed.

    Definition compare' (x y : t) : comparison :=
      if string_lt (fst x) (fst y)
        then Datatypes.Lt
        else if string_dec (fst x) (fst y)
          then if label'_lt (snd x) (snd y)
            then Datatypes.Lt
            else if label'_eq (snd x) (snd y)
              then Datatypes.Eq
              else Gt
          else Gt.
    
    Lemma label_eq : forall x y : label, fst x = fst y
      -> snd x = snd y
      -> x = y.
      destruct x; destruct y; simpl; congruence.
    Qed.

    Hint Immediate label_eq.

    Definition compare (x y : t) : Compare lt eq x y.
      refine (match compare' x y as c return c = compare' x y -> Compare lt eq x y with
                | Datatypes.Lt => fun _ => LT _ _
                | Datatypes.Eq => fun _ => EQ _ _
                | Gt => fun _ => GT _ _
              end (refl_equal _)); abstract (unfold compare', eq, lt in *;
                repeat match goal with
                         | [ H : context[if ?E then _ else _] |- _ ] => let Heq := fresh "Heq" in case_eq E; (intros ? Heq || intro Heq);
                           rewrite Heq in H; try discriminate
                       end; intuition).
    Defined.

    Definition eq_dec x y : { eq x y } + { ~ eq x y }.
      refine (if string_dec (fst x) (fst y)
        then if label'_eq (snd x) (snd y)
          then left _
          else right _
        else right _); abstract (unfold eq in *; destruct x; destruct y; simpl in *; congruence).
    Defined.
  End hide_hints.
End LabelKey.


Module LabelMap := FMapAVL.Make(LabelKey).

Require FMapFacts.
Module LabelFacts := FMapFacts.WFacts_fun(LabelKey)(LabelMap).
