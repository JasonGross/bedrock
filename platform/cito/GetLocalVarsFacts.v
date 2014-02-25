Set Implicit Arguments.

Require Import Equalities.
Require Import StringSet.
Module Import SS := StringSet.
Require Import SetFacts.
Require Import FSetFacts1.
Module SK_as_UDT := Make_UDT StringKey.
Require Import FSetFacts1.
Module Import SF1 := UWFacts_fun SK_as_UDT SS.
Import P FM.

Section TopSection.

  Require Import GetLocalVars.
  Require Import FreeVars.

  Lemma get_local_vars_cardinal : forall s1 s2 argvars retvar, Subset (free_vars s1) (free_vars s2) -> length (get_local_vars s1 argvars retvar) <= length (get_local_vars s2 argvars retvar).
    intros.
    unfold get_local_vars.
    repeat rewrite <- SS.cardinal_1.
    eapply subset_cardinal.
    eapply diff_s_m.
    eapply add_s_m; eauto.
    unfold Basics.flip.
    eapply subset_refl.
  Qed.

  Require Import String.
  Require Import List.
  Require Import GeneralTactics2.
  Require Import SetoidListFacts.

  Lemma get_local_vars_subset : forall stmt argvars retvar, Subset (free_vars stmt) (of_list (argvars ++ get_local_vars stmt argvars retvar)).
    unfold get_local_vars.
    unfold Subset; intros.
    eapply of_list_spec.
    destruct (List.In_dec string_dec a argvars).
    eapply in_or_app; eauto.
    eapply in_or_app; right.
    eapply InA_eq_List_In.
    eapply elements_iff.
    eapply diff_iff.
    split.
    eapply add_iff; eauto.
    not_not.
    eapply of_list_spec; eauto.
  Qed.

End TopSection.