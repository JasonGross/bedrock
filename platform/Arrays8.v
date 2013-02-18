Require Import AutoSep Bootstrap.


Hint Rewrite roundTrip_0 : N.

Lemma zero_le : forall w : W, natToW 0 <= w.
  intros; nomega.
Qed.

Hint Immediate zero_le.

Lemma length_upd' : forall v bs p,
  length (Array8.updN bs p v) = length bs.
  induction bs; simpl; intuition.
  destruct p; simpl; intuition.
Qed.

Lemma length_upd : forall p v bs,
  length (Array8.upd bs p v) = length bs.
  intros; apply length_upd'.
Qed.

Hint Rewrite length_upd : sepFormula.

Lemma next' : forall (i : W),
  (exists len' : W, (wordToNat i < wordToNat len')%nat)
  -> wordToNat (i ^+ $(1)) = wordToNat i + 1.
  destruct 1; erewrite next; eauto.
  instantiate (1 := x); nomega.
Qed.

Hint Rewrite next' using (eexists; eassumption) : N.

Lemma next : forall (i : W),
  (exists len' : W, i < len')
  -> wordToNat (i ^+ $(1)) = wordToNat i + 1.
  destruct 1; eapply next'; eauto.
  pre_nomega; eauto.
Qed.

Hint Rewrite next using (eexists; eassumption) : sepFormula.

Lemma increment : forall (i len len' : W),
  i < len
  -> len = len'
  -> i ^+ $1 <= len'.
  intros; subst; pre_nomega; nomega.
Qed.

Hint Immediate increment.

Lemma wordToNat_eq : forall sz (u v : word sz),
  wordToNat u = wordToNat v
  -> u = v.
  intros; apply (f_equal (@natToWord sz)) in H;
    repeat rewrite natToWord_wordToNat in H; auto.
Qed.

Lemma squeeze : forall (len i len' : W),
  len <= i
  -> len = len'
  -> i <= len'
  -> len' = i.
  intros; subst; apply wordToNat_eq; nomega.
Qed.

Hint Rewrite wordToNat_natToWord_idempotent using assumption : sepFormula.

Lemma selN_updN_eq : forall v ls p,
  (p < length ls)%nat
  -> Array8.selN (Array8.updN ls p v) p = v.
  induction ls; simpl; intuition.
  destruct p; simpl; intuition.
Qed.

Lemma selN_updN_ne : forall v ls p p',
  (p < length ls)%nat
  -> p <> p'
  -> Array8.selN (Array8.updN ls p v) p' = Array8.selN ls p'.
  induction ls; simpl; intuition.
  destruct p, p'; simpl; intuition.
Qed.

Lemma selN_upd_eq : forall v ls p,
  goodSize (length ls)
  -> p < natToW (length ls)
  -> Array8.selN (Array8.upd ls p v) (wordToNat p) = v.
  unfold Array8.upd; intros; apply selN_updN_eq; nomega.
Qed.

Lemma selN_upd_ne : forall v ls p p',
  goodSize (length ls)
  -> p < natToW (length ls)
  -> wordToNat p <> p'
  -> Array8.selN (Array8.upd ls p v) p' = Array8.selN ls p'.
  unfold Array8.upd; intros; apply selN_updN_ne; auto; nomega.
Qed.

Hint Resolve selN_upd_ne selN_upd_eq.

Lemma selN_oob : forall ls i,
  (i >= length ls)%nat
  -> Array8.selN ls i = wzero _.
  induction ls; simpl; intuition.
  destruct i; simpl; intuition.
Qed.

Lemma materialize_array8'' : forall p v,
  p =*> v ===> Ex b1, p =8> b1 * Ex b2, (p ^+ $1) =8> b2 * Ex b3, (p ^+ $2) =8> b3 * Ex b4, (p ^+ $3) =8> b4.
  intros; hnf; unfold himp; intros.
  unfold ptsto32, ptsto8, hptsto.
  apply injL; intuition.
  propxFo.
  unfold smem_get_word, H.footprint_w in *.
  
  Require Import Bootstrap.

  repeat match type of H0 with
           | match ?E with None => _ | _ => _ end = _ => case_eq E; intros;
             match goal with
               | [ H : _ = _ |- _ ] => rewrite H in *
             end; try discriminate
         end.
  do 4 esplit.
  apply split_put_clear; [ apply split_a_semp_a | apply H ].
  Local Hint Resolve get_put_eq get_put_ne get_emp.
  intuition eauto.
  rewrite get_put_ne; auto.
  do 4 esplit.
  apply split_put_clear; [ apply split_a_semp_a | ].
  rewrite get_clear_ne; apply H2 || W_neq.
  intuition eauto.
  rewrite get_put_ne; auto.
  do 4 esplit.
  apply split_put_clear; [ apply split_a_semp_a | ].
  rewrite get_clear_ne.
  rewrite get_clear_ne; try apply H3.
  W_neq.
  W_neq.
  intuition eauto.
  rewrite get_put_ne; auto.
  do 2 esplit.
  rewrite get_clear_ne.
  rewrite get_clear_ne.
  rewrite get_clear_ne; try apply H4.
  W_neq.
  W_neq.
  W_neq.
  intros.
  destruct (weq p' (p ^+ $2)); subst.
  apply get_clear_eq.
  rewrite get_clear_ne by auto.
  destruct (weq p' (p ^+ $1)); subst.
  apply get_clear_eq.
  rewrite get_clear_ne by auto.
  destruct (weq p' p); subst.
  apply get_clear_eq.
  rewrite get_clear_ne; eauto.
Qed.

Lemma materialize_array8' : forall p sz offset,
  allocated p offset sz ===> Ex bs, array8 bs (p ^+ $(offset)) * [| (length bs = sz * 4)%nat |].
  induction sz; simpl; intuition.
  
  sepLemma.
  instantiate (1 := nil); auto.
  sepLemma.

  sepLemmaLhsOnly.
  destruct offset.
  etransitivity; [ eapply himp_star_frame; [ apply IHsz | apply materialize_array8'' ] | ].
  sepLemmaLhsOnly.
  fold (@length B) in *.
  apply himp_ex_c; exists (x3 :: x2 :: x1 :: x0 :: x4).
  sepLemma.
  etransitivity; [ eapply himp_star_frame; [ apply IHsz | apply materialize_array8'' ] | ].
  sepLemmaLhsOnly.
  fold (@length B) in *.
  apply himp_ex_c; exists (x3 :: x2 :: x1 :: x0 :: x4).
  sepLemma.
  match goal with
    | [ |- himp _ (array8 _ ?X) (array8 _ ?Y) ] => replace Y with X; try reflexivity
  end.
  rewrite (natToW_S (S (S (S (S offset))))).
  rewrite (natToW_S (S (S (S offset)))).
  rewrite (natToW_S (S (S offset))).
  rewrite (natToW_S (S offset)).
  rewrite (natToW_S offset).
  words.
Qed.

Theorem materialize_array8 : forall p sz,
  p =?> sz ===> Ex bs, array8 bs p * [| (length bs = sz * 4)%nat |].
  intros; eapply Himp_trans; [ apply materialize_array8' | ].
  replace (p ^+ $0) with p by words.
  apply Himp_refl.
Qed.

Lemma decomission_array8'' : forall p b1 b2 b3 b4,
  (p =8> b1 * (p ^+ $1) =8> b2 * (p ^+ $2) =8> b3 * (p ^+ $3) =8> b4) ===> Ex w, p =*> w.
  intros; hnf; unfold himp; intros.
  unfold ptsto32, ptsto8, hptsto.
  repeat ((apply existsL; intro) || (apply andL; (apply injL; intro) || (apply swap; apply injL; intro))).
  apply injL; intuition.
  propxFo.
  do 2 esplit.
  unfold smem_get_word, H.footprint_w.
  repeat (erewrite split_smem_get; [ | | eauto ]).
  eauto.
  eauto.
  eapply split_assoc.
  apply split_comm; eauto.
  eauto.
  eapply split_assoc.
  apply split_comm; eauto.
  eapply split_assoc.
  apply split_comm; eauto.
  eauto.
  eapply split_assoc.
  apply split_comm; eauto.
  eapply split_assoc.
  apply split_comm; eauto.
  apply split_comm; eauto.
  intuition idtac.
  unfold split in *; intuition subst.
  repeat rewrite join_None; eauto.
Qed.

Lemma decomission_array8' : forall p sz bs offset sz',
  length bs = sz' * 4
  -> (sz' < sz)%nat
  -> array8 bs (p ^+ $(offset)) ===> allocated p offset sz'.
  induction sz; simpl; intuition.

  destruct bs; simpl in *.
  destruct sz'; simpl in *; try discriminate.
  sepLemma.

  destruct sz'; simpl in *; try discriminate.
  do 3 (destruct bs; simpl in *; try discriminate).
  replace (p ^+ $(offset) ^+ $1 ^+ $1 ^+ $1) with (p ^+ $(offset) ^+ $3) by words.
  replace (p ^+ $(offset) ^+ $1 ^+ $1) with (p ^+ $(offset) ^+ $2) by words.

  Lemma pull_out : forall P Q R S T,
    P * (Q * (R * (S * T))) ===> (P * Q * R * S) * T.
    sepLemma.
  Qed.

  eapply Himp_trans; [ apply pull_out | ].
  apply Himp_star_frame.
  eapply Himp_trans; [ apply decomission_array8'' | ].
  destruct offset; sepLemma.
  eapply Himp_trans; [ | apply IHsz ]; auto.
  match goal with
    | [ |- array8 _ ?X ===> array8 _ ?Y ] => replace Y with X; try apply Himp_refl
  end.
  change ($ (S (S (S (S offset))))) with (natToW (S (S (S (S offset))))).
  rewrite (natToW_S (S (S (S offset)))).
  rewrite (natToW_S (S (S offset))).
  rewrite (natToW_S (S offset)).
  rewrite (natToW_S offset).
  unfold natToW.
  W_eq.
  congruence.
Qed.

Lemma decomission_array8 : forall p bs sz,
  length bs = sz * 4
  -> array8 bs p ===> p =?> sz.
  intros; eapply Himp_trans; [ | eapply decomission_array8' ].
  replace (p ^+ $0) with p by words; apply Himp_refl.
  auto.
  constructor.
Qed.

Inductive please_materialize (sz : nat) : Prop := PleaseMaterialize.
Hint Constructors please_materialize.

Theorem materialize_array8_tagged : forall p sz,
  please_materialize sz
  -> p =?> sz ===> Ex bs, array8 bs p * [| (length bs = sz * 4)%nat |].
  intros; apply materialize_array8.
Qed.

Definition array8_decomission (sz : nat) := array8.

Definition decomission_ok (sz : nat) (bs : list B) :=
  length bs = sz * 4.

Lemma decomission_array8_tagged : forall p bs sz,
  decomission_ok sz bs
  -> array8_decomission sz bs p ===> p =?> sz.
  intros; apply decomission_array8; auto.
Qed.
