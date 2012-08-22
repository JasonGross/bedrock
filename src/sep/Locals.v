Require Import Ascii Bool String List.
Require Import Word Memory Expr SepExpr SymEval SepIL Env Prover SymEval IL SymIL.
Require Import sep.Array.
Require Import Allocated.
Require Import ListFacts.

Set Implicit Arguments.

Definition vals := string -> W.

Definition toArray (ns : list string) (vs : vals) : list W := map vs ns.

Definition locals (ns : list string) (vs : vals) (avail : nat) (p : W) : HProp :=
  ([| NoDup ns |] * array (toArray ns vs) p * ((p ^+ $(length ns * 4)) =?> avail))%Sep.

Definition ascii_eq (a1 a2 : ascii) : bool :=
  let (b1, c1, d1, e1, f1, g1, h1, i1) := a1 in
  let (b2, c2, d2, e2, f2, g2, h2, i2) := a2 in
    eqb b1 b2 && eqb c1 c2 && eqb d1 d2 && eqb e1 e2
    && eqb f1 f2 && eqb g1 g2 && eqb h1 h2 && eqb i1 i2.

Lemma ascii_eq_true : forall a,
  ascii_eq a a = true.
Proof.
  destruct a; simpl; intuition.
  repeat rewrite eqb_reflx; reflexivity.
Qed.

Lemma ascii_eq_false : forall a b,
  a <> b -> ascii_eq a b = false.
  destruct b, a; simpl; intuition.
  match goal with
    | [ |- ?E = _ ] => case_eq E
  end; intuition.
    repeat match goal with
             | [ H : _ |- _ ] => apply andb_prop in H; destruct H
             | [ H : _ |- _ ] => apply eqb_prop in H
           end; congruence.
Qed.

Fixpoint string_eq (s1 s2 : string) : bool :=
  match s1, s2 with
    | EmptyString, EmptyString => true
    | String a1 s1', String a2 s2' => ascii_eq a1 a2 && string_eq s1' s2'
    | _, _ => false
  end.

Theorem string_eq_true : forall s,  string_eq s s = true.
Proof.
  induction s; simpl; intuition; rewrite ascii_eq_true; assumption.
Qed.

Theorem string_eq_false : forall s1 s2,
  s1 <> s2 -> string_eq s1 s2 = false.
  induction s1; destruct s2; simpl; intuition.
  match goal with
    | [ |- ?E = _ ] => case_eq E
  end; intuition.
  repeat match goal with
           | [ H : _ |- _ ] => apply andb_prop in H; destruct H
           | [ H : _ |- _ ] => apply eqb_prop in H
         end.
  destruct (ascii_dec a a0); subst.
  destruct (string_dec s1 s2); subst.
  tauto.
  apply IHs1 in n; congruence.
  apply ascii_eq_false in n; congruence.
Qed.

Theorem string_eq_correct : forall s1 s2,
  string_eq s1 s2 = true -> s1 = s2.
Proof.
  intros; destruct (string_dec s1 s2); subst; auto.
  apply string_eq_false in n; congruence.
Qed.

Definition sel (vs : vals) (nm : string) : W := vs nm.
Definition upd (vs : vals) (nm : string) (v : W) : vals := fun nm' =>
  if string_eq nm' nm then v else vs nm'.

Definition bedrock_type_string : type :=
  {| Impl := string
   ; Eqb := string_eq
   ; Eqb_correct := string_eq_correct |}.

Definition bedrock_type_listString : type :=
  {| Impl := list string
   ; Eqb := (fun _ _ => false)
   ; Eqb_correct := @ILEnv.all_false_compare _ |}.

Definition bedrock_type_vals : type :=
  {| Impl := vals
   ; Eqb := (fun _ _ => false)
   ; Eqb_correct := @ILEnv.all_false_compare _ |}.

Definition types_r : Env.Repr type :=
  Eval cbv beta iota zeta delta [ Env.listOptToRepr ] in 
    let lst := 
      (@Some type ILEnv.bedrock_type_W) ::
      (@Some type ILEnv.bedrock_type_setting_X_state) ::
      None ::
(*    None :: *)
      None ::
      (@Some type ILEnv.bedrock_type_nat) ::
      None ::
      (@Some type bedrock_type_string) ::
      (@Some type bedrock_type_listString) ::
      (@Some type bedrock_type_vals) ::
      nil
    in Env.listOptToRepr lst EmptySet_type.

Local Notation "'pcT'" := (tvType 0).
Local Notation "'stT'" := (tvType 1).
Local Notation "'wordT'" := (tvType 0).
Local Notation "'natT'" := (tvType 4).
Local Notation "'stringT'" := (tvType 6).
Local Notation "'listStringT'" := (tvType 7).
Local Notation "'valsT'" := (tvType 8).

Local Notation "'wplusF'" := 0.
Local Notation "'wmultF'" := 2.
Local Notation "'natToWF'" := 5.
Local Notation "'nilF'" := 9.
Local Notation "'consF'" := 10.
Local Notation "'selF'" := 11.
Local Notation "'updF'" := 12.

Section parametric.
  Variable types' : list type.
  Definition types := repr types_r types'.
  Variable Prover : ProverT types.

  Definition nil_r : signature types.
    refine {| Domain := nil; Range := listStringT |}.
    exact (@nil _).
  Defined.

  Definition cons_r : signature types.
    refine {| Domain := stringT :: listStringT :: nil; Range := listStringT |}.
    exact (@cons _).
  Defined.

  Definition sel_r : signature types.
    refine {| Domain := valsT :: stringT :: nil; Range := wordT |}.
    exact sel.
  Defined.

  Definition upd_r : signature types.
    refine {| Domain := valsT :: stringT :: wordT :: nil; Range := valsT |}.
    exact upd.
  Defined.

  Definition funcs_r : Env.Repr (signature types) :=
    Eval cbv beta iota zeta delta [ Env.listOptToRepr ] in 
      let lst := 
        Some (ILEnv.wplus_r types) ::
        None ::
        Some (ILEnv.wmult_r types) ::
        None ::
        None ::
        Some (ILEnv.natToW_r types) ::
        None ::
        None ::
        None ::
        Some nil_r ::
        Some cons_r ::
        Some sel_r ::
        Some upd_r ::
        nil
      in Env.listOptToRepr lst (Default_signature _).

  Definition deref (e : expr types) : option (expr types * nat) :=
    match e with
      | Func wplusF (base :: offset :: nil) =>
        match offset with
          | Func natToWF (Const t k :: nil) =>
            match t return tvarD types t -> _ with
              | natT => fun k => match div4 k with
                                   | None => None
                                   | Some k' => Some (base, k')
                                 end
              | _ => fun _ => None
            end k
          | _ => None
        end
      | _ => None
    end.

  Fixpoint listIn (e : expr types) : option (list string) :=
    match e with
      | Func nilF nil => Some nil
      | Func consF (Const tp s :: t :: nil) =>
        match tp return tvarD types tp -> option (list string) with
          | stringT => fun s => match listIn t with
                                  | None => None
                                  | Some t => Some (s :: t)
                                end
          | _ => fun _ => None
        end s
      | _ => None
    end.

  Fixpoint sym_sel (vs : expr types) (nm : string) : expr types :=
    match vs with
      | Func updF (vs' :: Const tp nm' :: v :: nil) =>
        match tp return tvarD types tp -> expr types with
          | stringT => fun nm' =>
            if string_eq nm' nm
              then v
              else sym_sel vs' nm
          | _ => fun _ => Func selF (vs :: Const (types := types) (t := stringT) nm :: nil)
        end nm'
      | _ => Func selF (vs :: Const (types := types) (t := stringT) nm :: nil)
    end.

  Definition sym_read (summ : Prover.(Facts)) (args : list (expr types)) (p : expr types)
    : option (expr types) :=
    match args with
      | ns :: vs :: _ :: p' :: nil =>
        match deref p, listIn ns with
          | Some (base, offset), Some ns =>
            if Prover.(Prove) summ (Equal wordT p' base)
              then match nth_error ns offset with
                     | None => None
                     | Some nm => Some (sym_sel vs nm)
                   end
              else None
          | _, _ => None
        end
      | _ => None
    end.

  Definition sym_write (summ : Prover.(Facts)) (args : list (expr types)) (p v : expr types)
    : option (list (expr types)) :=
    match args with
      | ns :: vs :: avail :: p' :: nil =>
        match deref p, listIn ns with
          | Some (base, offset), Some ns' =>
            if Prover.(Prove) summ (Equal wordT p' base)
              then match nth_error ns' offset with
                     | None => None
                     | Some nm => Some (ns
                       :: Func updF (vs :: Const (types := types) (t := stringT) nm :: v :: nil)
                       :: avail :: p' :: nil)
                   end
              else None
          | _, _ => None
        end
      | _ => None
    end.
End parametric.

Definition MemEval types' : @MEVAL.PredEval.MemEvalPred (types types') :=
  MEVAL.PredEval.Build_MemEvalPred (@sym_read _) (@sym_write _).

Section correctness.
  Variable types' : list type.
  Definition types0 := types types'.

  Definition ssig : SEP.predicate types0 pcT stT.
    refine (SEP.PSig _ _ _ (listStringT :: valsT :: natT :: wordT :: nil) _).
    exact locals.
  Defined.

  Definition ssig_r : Env.Repr (SEP.predicate types0 pcT stT) :=
    Eval cbv beta iota zeta delta [ Env.listOptToRepr ] in 
      let lst := 
        None :: None :: Some ssig :: nil
      in Env.listOptToRepr lst (SEP.Default_predicate _ _ _).

  Variable funcs' : functions types0.
  Definition funcs := Env.repr (funcs_r _) funcs'.

  Variable Prover : ProverT types0.
  Variable Prover_correct : ProverT_correct Prover funcs.

  Ltac deconstruct := repeat deconstruct' idtac.

  Lemma deref_correct : forall uvars vars e w base offset,
    exprD funcs uvars vars e wordT = Some w
    -> deref e = Some (base, offset)
    -> exists wb,
      exprD funcs uvars vars base wordT = Some wb
      /\ w = wb ^+ $(offset * 4).
  Proof.
    destruct e; simpl deref; intuition; try discriminate.
    deconstruct.
    simpl exprD in *.
    match goal with
      | [ _ : context[div4 ?N] |- _ ] => specialize (div4_correct N); destruct (div4 N)
    end; try discriminate.
    deconstruct.
    specialize (H2 _ (refl_equal _)); subst.
    repeat (esplit || eassumption).
    repeat f_equal.
    unfold natToW.
    f_equal.
    omega.
  Qed.

  Lemma listIn_correct : forall uvars vars e ns, listIn e = Some ns
    -> exprD funcs uvars vars e listStringT = Some ns.
  Proof.
    induction e; simpl; intuition; try discriminate.
    repeat match type of H with
             | Forall _ (_ :: _ :: nil) => inversion H; clear H; subst
             | _ => deconstruct' idtac
           end.
    inversion H4; clear H4; subst.
    clear H5.
    deconstruct.
    simpl in *.
    erewrite H2; reflexivity.
  Qed.

  Lemma sym_sel_correct : forall uvars vars nm (vs : expr types0) vsv,
    exprD funcs uvars vars vs valsT = Some vsv
    -> exprD funcs uvars vars (sym_sel vs nm) wordT = Some (sel vsv nm).
  Proof.
    induction vs; simpl; intros; try discriminate.

    destruct (equiv_dec t valsT); congruence.

    rewrite H; reflexivity.

    rewrite H; reflexivity.

    Ltac t := simpl in *; try discriminate; try (deconstruct;
      match goal with
        | [ _ : Range (match ?E with nil => _ | _ => _ end) === _ |- _ ] =>
          destruct E; simpl in *; try discriminate;
            match goal with
              | [ H : Range ?X === _ |- _ ] => destruct X; simpl in *; hnf in H; subst
            end;
            match goal with
              | [ H : _ = _ |- _ ] => rewrite H; reflexivity
            end
      end).
    simpl in *.
  
    do 13 (destruct f; t).

    Focus 2.
    deconstruct.
    hnf in e; subst.
    rewrite H0; reflexivity.

    destruct l; simpl in *; try discriminate.
    destruct l; simpl in *; try discriminate.
    rewrite H0; reflexivity.
    destruct e0; simpl in *; try (rewrite H0; reflexivity).
    do 2 (destruct l; simpl in *; try (rewrite H0; reflexivity)).
    destruct t; simpl in *; try (rewrite H0; reflexivity).
    do 7 (destruct n; simpl in *; try (rewrite H0; reflexivity)).
    inversion H; clear H; subst.
    inversion H4; clear H4; subst.
    inversion H5; clear H5; subst.
    clear H6.
    destruct (string_dec t0 nm); subst.
    rewrite string_eq_true.
    deconstruct.
    unfold sel, upd.
    rewrite string_eq_true; reflexivity.

    rewrite string_eq_false by assumption.
    deconstruct.
    erewrite H3 by reflexivity.
    f_equal; unfold sel, upd.
    rewrite string_eq_false; auto.
  Qed.

  Theorem sym_read_correct : forall args uvars vars cs summ pe p ve m stn,
    sym_read Prover summ args pe = Some ve ->
    Valid Prover_correct uvars vars summ ->
    exprD funcs uvars vars pe wordT = Some p ->
    match 
      applyD (exprD funcs uvars vars) (SEP.SDomain ssig) args _ (SEP.SDenotation ssig)
      with
      | None => False
      | Some p => ST.satisfies cs p stn m
    end ->
    match exprD funcs uvars vars ve wordT with
      | Some v =>
        ST.HT.smem_get_word (IL.implode stn) p m = Some v
      | _ => False
    end.
  Proof.
    simpl; intuition.
    do 5 (destruct args; simpl in *; intuition; try discriminate).
    generalize (deref_correct uvars vars pe); destr idtac (deref pe); intro Hderef.
    destruct p0.
    generalize (listIn_correct uvars vars e); destr idtac (listIn e); intro HlistIn.
    specialize (HlistIn _ (refl_equal _)).
    rewrite HlistIn in *.

    repeat match goal with
             | [ H : Valid _ _ _ _, _ : context[Prove Prover ?summ ?goal] |- _ ] =>
               match goal with
                 | [ _ : context[ValidProp _ _ _ goal] |- _ ] => fail 1
                 | _ => specialize (Prove_correct Prover_correct summ H (goal := goal)); intro
               end
           end; unfold ValidProp in *.
    unfold types0 in *.
    match type of H with
      | (if ?E then _ else _) = _ => destruct E
    end; intuition; try discriminate.
    simpl in H4.
    case_eq (nth_error l n); [ intros ? Heq | intro Heq ]; rewrite Heq in *; try discriminate.
    injection H; clear H; intros; subst.
    generalize (sym_sel_correct uvars vars s e0); intro Hsym_sel.
    destruct (exprD funcs uvars vars e0 valsT); try tauto.
    specialize (Hsym_sel _ (refl_equal _)).
    rewrite Hsym_sel.
    specialize (Hderef _ _ _ H1 (refl_equal _)).
    destruct Hderef as [ ? [ ] ].
    subst.
    unfold types0 in H2.
    unfold types0 in H1.
    case_eq (exprD funcs uvars vars e1 natT); [ intros ? Heq' | intro Heq' ]; rewrite Heq' in *; try tauto.
    case_eq (exprD funcs uvars vars e2 wordT); [ intros ? Heq'' | intro Heq'' ]; rewrite Heq'' in *; try tauto.
    rewrite H in H4.
    specialize (H4 (ex_intro _ _ (refl_equal _))).
    hnf in H4; simpl in H4.
    rewrite Heq'' in H4.
    rewrite H in H4.
    subst.
    Require Import PropXTac.
    apply simplify_fwd in H2.
    destruct H2 as [ ? [ ? [ ? [ ] ] ] ].
    destruct H3 as [ ? [ ? [ ? [ ] ] ] ].
    simpl simplify in H2, H3, H5.
    destruct H5.
    apply simplify_bwd in H6.
    generalize (split_semp _ _ _ H3 H7); intro; subst.
    specialize (smem_read_correct' _ _ _ _ (i := natToW n) H6); intro Hsmem.
    rewrite natToW_times4.
    rewrite wmult_comm.
    unfold natToW in *.
    erewrite split_smem_get_word; eauto.
    left.
    rewrite Hsmem.
    f_equal.

    Lemma array_selN : forall nm vs ns n,
      nth_error ns n = Some nm
      -> Array.selN (toArray ns vs) n = sel vs nm.
    Proof.
      induction ns; destruct n; simpl; intuition; try discriminate.
      injection H; clear H; intros; subst; reflexivity.
    Qed.

    Require Import NArith Nomega.

    unfold Array.sel.
    apply array_selN.
    apply array_bound in H6.
    rewrite wordToNat_natToWord_idempotent; auto.

    apply nth_error_Some_length in Heq.

    Lemma length_toArray : forall ns vs,
      length (toArray ns vs) = length ns.
    Proof.
      induction ns; simpl; intuition.
    Qed.

    rewrite length_toArray in *.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    omega.

    rewrite length_toArray.
    apply Nlt_in.
    repeat rewrite wordToN_nat.
    repeat rewrite Nat2N.id.
    apply array_bound in H6.
    rewrite length_toArray in *.
    repeat rewrite wordToNat_natToWord_idempotent.
    eapply nth_error_Some_length; eauto.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    omega.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    apply nth_error_Some_length in Heq.
    omega.
  Qed.

  Theorem sym_write_correct : forall args uvars vars cs summ pe p ve v m stn args',
    sym_write Prover summ args pe ve = Some args' ->
    Valid Prover_correct uvars vars summ ->
    exprD funcs uvars vars pe wordT = Some p ->
    exprD funcs uvars vars ve wordT = Some v ->
    match
      applyD (@exprD _ funcs uvars vars) (SEP.SDomain ssig) args _ (SEP.SDenotation ssig)
      with
      | None => False
      | Some p => ST.satisfies cs p stn m
    end ->
    match 
      applyD (@exprD _ funcs uvars vars) (SEP.SDomain ssig) args' _ (SEP.SDenotation ssig)
      with
      | None => False
      | Some pr => 
        match ST.HT.smem_set_word (IL.explode stn) p v m with
          | None => False
          | Some sm' => ST.satisfies cs pr stn sm'
        end
    end.
  Proof.
    simpl; intuition.
    do 5 (destruct args; simpl in *; intuition; try discriminate).
    generalize (deref_correct uvars vars pe); destr idtac (deref pe); intro Hderef.
    destruct p0.
    specialize (Hderef _ _ _ H1 (refl_equal _)).
    destruct Hderef as [ ? [ ] ]; subst.
    generalize (listIn_correct uvars vars e); destr idtac (listIn e); intro HlistIn.
    specialize (HlistIn _ (refl_equal _)).
    rewrite HlistIn in *.

    repeat match goal with
             | [ H : Valid _ _ _ _, _ : context[Prove Prover ?summ ?goal] |- _ ] =>
               match goal with
                 | [ _ : context[ValidProp _ _ _ goal] |- _ ] => fail 1
                 | _ => specialize (Prove_correct Prover_correct summ H (goal := goal)); intro
               end
           end; unfold ValidProp in *.
    unfold types0 in *.
    match type of H with
      | (if ?E then _ else _) = _ => destruct E
    end; intuition; try discriminate.
    simpl in H6.
    case_eq (nth_error l n); [ intros ? Heq | intro Heq ]; rewrite Heq in *; try discriminate.
    rewrite H4 in *.
    injection H; clear H; intros; subst.
    unfold applyD.
    rewrite HlistIn.
    simpl exprD.
    destruct (exprD funcs uvars vars e0 valsT); try tauto.
    unfold Provable in H6.
    simpl in H6.
    rewrite H4 in H6.
    destruct (exprD funcs uvars vars e1 natT); try tauto.
    destruct (exprD funcs uvars vars e2 wordT); try tauto.
    rewrite H2.
    specialize (H6 (ex_intro _ _ (refl_equal _))); subst.
    apply simplify_fwd in H3.
    destruct H3 as [ ? [ ? [ ? [ ] ] ] ].
    destruct H3 as [ ? [ ? [ ? [ ] ] ] ].
    simpl in H, H3, H6, H7.
    destruct H6.
    apply simplify_bwd in H7.
    eapply smem_write_correct' in H7.
    destruct H7 as [ ? [ ] ].
    rewrite natToW_times4.
    rewrite wmult_comm.
    generalize (split_semp _ _ _ H3 H8); intro; subst.
    eapply split_set_word in H7.
    destruct H7.
    destruct H; subst.
    rewrite H10.
    unfold locals.
    apply simplify_bwd.
    exists x4; exists x1.
    repeat split; auto.
    exists smem_emp.
    exists x4.
    simpl; intuition.
    apply split_a_semp_a.
    reflexivity.
    apply simplify_fwd.

    Lemma toArray_irrel : forall vs v nm ns,
      ~In nm ns
      -> toArray ns (upd vs nm v) = toArray ns vs.
      induction ns; simpl; intuition.
      f_equal; auto.
      unfold upd.
      rewrite string_eq_false; auto.
    Qed.

    Lemma nth_error_In : forall A (x : A) ls n,
      nth_error ls n = Some x
      -> In x ls.
      induction ls; destruct n; simpl; intuition; try discriminate; eauto.
      injection H; intros; subst; auto.
    Qed.

    Lemma array_updN : forall vs nm v ns,
      NoDup ns
      -> forall n, nth_error ns n = Some nm
        -> Array.updN (toArray ns vs) n v
        = toArray ns (upd vs nm v).
      induction 1; destruct n; simpl; intuition.
      injection H1; clear H1; intros; subst.
      rewrite toArray_irrel by assumption.
      unfold upd; rewrite string_eq_true; reflexivity.
      rewrite IHNoDup; f_equal; auto.
      unfold upd; rewrite string_eq_false; auto.
      intro; subst.
      apply H.
      eapply nth_error_In; eauto.
    Qed.

    unfold Array.upd in H9.
    rewrite wordToNat_natToWord_idempotent in H9.
    erewrite array_updN in H9; eauto.
    apply nth_error_Some_length in Heq.
    apply array_bound in H9.
    Require Import Arrays.
    rewrite updN_length in H9.
    rewrite length_toArray in H9.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    omega.

    destruct H; auto.

    rewrite length_toArray.
    apply Nlt_in.
    repeat rewrite wordToN_nat.
    repeat rewrite Nat2N.id.
    apply array_bound in H7.
    rewrite length_toArray in *.
    repeat rewrite wordToNat_natToWord_idempotent.
    eapply nth_error_Some_length; eauto.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    omega.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    apply nth_error_Some_length in Heq.
    omega.
  Qed.

End correctness.

Definition MemEvaluator types' : MEVAL.MemEvaluator (types types') (tvType 0) (tvType 1) :=
  Eval cbv beta iota zeta delta [ MEVAL.PredEval.MemEvalPred_to_MemEvaluator ] in 
    @MEVAL.PredEval.MemEvalPred_to_MemEvaluator _ (tvType 0) (tvType 1) (MemEval types') 2.

Theorem MemEvaluator_correct types' funcs' preds'
  : @MEVAL.MemEvaluator_correct (Env.repr types_r types') (tvType 0) (tvType 1) 
  (MemEvaluator (Env.repr types_r types')) (funcs funcs') (Env.repr (ssig_r _) preds')
  (IL.settings * IL.state) (tvType 0) (tvType 0)
  (@IL_mem_satisfies (types types')) (@IL_ReadWord (types types')) (@IL_WriteWord (types types')).
Proof.
  intros. eapply (@MemPredEval_To_MemEvaluator_correct (types types')); simpl; intros.
  eapply sym_read_correct; eauto.
  eapply sym_write_correct; eauto.
  reflexivity.
Qed.

Definition pack : MEVAL.MemEvaluatorPackage types_r (tvType 0) (tvType 1) (tvType 0) (tvType 0)
  IL_mem_satisfies IL_ReadWord IL_WriteWord :=

  @MEVAL.Build_MemEvaluatorPackage types_r (tvType 0) (tvType 1) (tvType 0) (tvType 0) 
  IL_mem_satisfies IL_ReadWord IL_WriteWord
  types_r
  funcs_r
  (fun ts => Env.listOptToRepr (None :: None :: Some (ssig ts) :: nil)
    (SEP.Default_predicate (Env.repr types_r ts)
      (tvType 0) (tvType 1)))
  (fun ts => MemEvaluator _)
  (fun ts fs ps => MemEvaluator_correct _ _).


(** * Some additional helpful theorems *)

Theorem sel_upd_eq : forall vs nm v nm',
  nm = nm'
  -> sel (upd vs nm v) nm' = v.
Proof.
  unfold sel, upd; intros; subst; rewrite string_eq_true; reflexivity.
Qed.

Theorem sel_upd_ne : forall vs nm v nm',
  nm <> nm'
  -> sel (upd vs nm v) nm' = sel vs nm'.
Proof.
  unfold sel, upd; intros; subst; rewrite string_eq_false; auto.
Qed.

(*
Require Import PropX.
*)

Ltac simp := cbv beta; unfold In.

(** ** Point-of-view switch at function call sites *)

Theorem Himp_ex_c : forall T (P : T -> _) Q, 
  (exists v, Q ===> (P v)) -> Q ===> (ex P).
  intros; intro cs; apply himp_ex_c; firstorder.
Qed.

Theorem Himp_ex_star : forall T (P : T -> _) Q,
  (star (ex P) Q) ===> (ex (fun x => star (P x) Q)).
  intros; intro cs; apply himp_ex_star.
Qed.

Theorem Himp'_ex : forall T (P : T -> _) Q,
  (forall x, (P x) ===> Q) ->
  ex P ===> Q.
  intros; intro cs; apply himp'_ex; firstorder.
Qed.

Theorem Himp_star_frame : forall P Q R S, 
  P ===> Q -> R ===> S -> (star P R) ===> (star Q S).
  intros; intro cs; apply himp_star_frame; auto.
Qed.

Theorem Himp_star_comm : forall P Q, (star P Q) ===> (star Q P).
  intros; intro cs; apply himp_star_comm.
Qed.

Lemma behold_the_array' : forall p ns,
  NoDup ns
  -> forall offset, allocated p offset (length ns)
    ===> Ex vs, ptsto32m' nil p offset (toArray ns vs).
  induction 1; simpl length; unfold allocated; fold allocated; intros.

  simpl.
  apply Himp_ex_c.
  exists (fun _ => wzero _).
  apply Himp_refl.

  eapply Himp_trans; [ apply Himp_ex_star | ].
  apply Himp'_ex; intro.
  eapply Himp_trans; [ eapply Himp_star_frame | ]; [ apply Himp_refl | apply IHNoDup | ].
  eapply Himp_trans; [ apply Himp_star_comm | ].
  eapply Himp_trans; [ apply Himp_ex_star | ].
  eapply Himp'_ex; intro.
  simpl toArray.
  unfold ptsto32m'; fold ptsto32m'.

  replace (match offset with
             | 0 => p
             | S _ => p ^+ $ (offset)
           end) with (p ^+ $(offset)) by (destruct offset; W_eq).
  
  apply Himp_ex_c; exists (upd x1 x x0).
  eapply Himp_trans; [ apply Himp_star_comm | ].
  apply Himp_star_frame.
  change (upd x1 x x0 x) with (sel (upd x1 x x0) x).
  rewrite sel_upd_eq by reflexivity.
  apply Himp_refl.
  rewrite toArray_irrel by assumption.
  apply Himp_refl.
Qed.

Theorem Himp_star_Emp : forall P,
  Emp * P ===> P.
  intros; intro cs.
  destruct (heq_star_emp_l cs P); auto.
Qed.

Theorem ptsto32m'_out : forall a vs offset,
  ptsto32m' _ a offset vs ===> ptsto32m _ a offset vs.
  induction vs; intros.

  apply Himp_refl.

  unfold ptsto32m', ptsto32m; fold ptsto32m; fold ptsto32m'.
  replace (match offset with
             | 0 => a
             | S _ => a ^+ $ (offset)
           end) with (a ^+ $(offset)) by (destruct offset; W_eq).
  destruct vs.
  simpl ptsto32m'.
  eapply Himp_trans; [ apply Himp_star_comm | ].
  apply Himp_star_Emp.
  apply Himp_star_frame.
  apply Himp_refl.
  auto.
Qed.

Theorem Himp_ex : forall T (P Q : T -> _), 
  (forall v, P v ===> Q v) ->
  ex P ===> ex Q.
  intros; intro cs; apply himp_ex; firstorder.
Qed.

Lemma behold_the_array : forall p ns,
  NoDup ns
  -> forall offset, allocated p offset (length ns)
    ===> Ex vs, ptsto32m nil p offset (toArray ns vs).
  intros.
  eapply Himp_trans; [ apply behold_the_array' | ]; auto.
  apply Himp_ex; intro.
  apply ptsto32m'_out.
Qed.

Theorem Himp_star_pure_c : forall P Q (F : Prop),
  (F -> P ===> Q) -> (star (inj (PropX.Inj F)) P) ===> Q.
  intros; intro; apply himp_star_pure_c; firstorder.
Qed.

Theorem Himp_star_assoc : forall P Q R,
  (star (star P Q) R) ===> (star P (star Q R)).
  intros; intro; apply himp_star_assoc.
Qed.

Theorem Himp_star_assoc' : forall P Q R,
  (star P (star Q R)) ===> (star (star P Q) R).
  intros; intro cs.
  destruct (heq_star_assoc cs P Q R); auto.
Qed.

Theorem Himp_star_Emp' : forall P,
  P ===> Emp * P.
  intros; intro cs.
  destruct (heq_star_emp_l cs P); auto.
Qed.

Theorem Himp_star_pure_cc : forall P Q (p : Prop),
  p ->
  P ===> Q ->
  P ===> (star (inj (PropX.Inj p)) Q).
  intros; intro; eapply himp_star_pure_cc; eauto.
Qed.

Lemma do_call' : forall ns ns' vs avail avail' p p',
  (length ns' <= avail)%nat
  -> avail' = avail - length ns'
  -> p' = p ^+ natToW (4 * length ns)
  -> NoDup ns'
  -> locals ns vs avail p ===> locals ns vs 0 p * Ex vs', locals ns' vs' avail' p'.
Proof.
  intros.
  unfold locals.
  eapply Himp_trans; [ | apply Himp_star_assoc' ]. 
  apply Himp_star_frame.
  apply Himp_refl.

  subst.
  eapply Himp_trans; [ | apply Himp_star_Emp' ].
  eapply Himp_trans; [ apply allocated_split | ]; eauto.
  replace (0 + 4 * length ns') with (length ns' * 4) by omega.
  replace (4 * length ns) with (length ns * 4) by omega.
  eapply Himp_trans.
  eapply Himp_star_frame.
  apply behold_the_array; auto.
  apply Himp_refl.
  eapply Himp_trans; [ apply Himp_ex_star | ].
  apply Himp'_ex; intro vs'.
  apply Himp_ex_c; exists vs'.
  unfold array.  
  eapply Himp_trans; [ | apply Himp_star_assoc' ].
  apply Himp_star_pure_cc; auto.
  apply Himp_star_frame.
  apply Himp_refl.
  apply allocated_shift_base; auto.
  unfold natToW; W_eq.
Qed.

Definition reserved (p : W) (len : nat) := (p =?> len)%Sep.

Ltac words' := repeat (rewrite (Mult.mult_comm 4)
  || rewrite natToW_times4 || rewrite natToW_plus); unfold natToW.
Ltac words := words'; W_eq.

Lemma expose_avail : forall ns vs avail p expose avail',
  (expose <= avail)%nat
  -> avail' = avail - expose
  -> locals ns vs avail p ===> locals ns vs avail' p
  * reserved (p ^+ natToW (4 * (length ns + avail'))) expose.
Proof.
  unfold locals; intros.
  eapply Himp_trans; [ | apply Himp_star_assoc' ]. 
  apply Himp_star_frame.
  apply Himp_refl.  
  subst.
  eapply Himp_trans; [ apply allocated_split | ].
  instantiate (1 := avail - expose); omega.
  apply Himp_star_frame.
  apply Himp_refl.
  apply allocated_shift_base; try omega.
  words.
Qed.

Theorem Himp_refl' : forall P Q,
  P = Q
  -> P ===> Q.
  intros; subst; apply Himp_refl.
Qed.

Theorem do_call : forall ns ns' vs avail avail' p p',
  (length ns' <= avail)%nat
  -> (avail' <= avail - length ns')%nat
  -> p' = p ^+ natToW (4 * length ns)
  -> NoDup ns'
  -> locals ns vs avail p ===>
  locals ns vs 0 p
  * Ex vs', locals ns' vs' avail' p'
  * reserved (p ^+ natToW (4 * (length ns + length ns' + avail')))
  (avail - length ns' - avail').
Proof.
  intros; subst.
  eapply Himp_trans; [ apply do_call' | ]; eauto.
  apply Himp_star_frame; [ apply Himp_refl | ].
  apply Himp_ex; intro.
  eapply Himp_trans; [ apply expose_avail | ].
  instantiate (1 := avail - length ns' - avail'); omega.
  eauto.
  apply Himp_star_frame.
  apply Himp_refl'.
  f_equal; omega.
  apply Himp_refl'.
  f_equal.
  words'.
  replace (avail - Datatypes.length ns' -
    (avail - Datatypes.length ns' - avail'))
    with avail' by omega.
  W_eq.
Qed.

Lemma ptsto32m'_allocated : forall (p : W) (ls : list W) (offset : nat),
  ptsto32m' nil p offset ls ===> allocated p offset (length ls).
  induction ls.

  intros; apply Himp_refl.

  simpl length.
  unfold ptsto32m', allocated; fold ptsto32m'; fold allocated.
  intros.
  replace (match offset with
             | 0 => p
             | S _ => p ^+ $ (offset)
           end) with (p ^+ $(offset)) by (destruct offset; W_eq).
  apply Himp_star_frame.
  apply Himp_ex_c; eexists; apply Himp_refl.
  auto.
Qed.

Theorem ptsto32m'_in : forall a vs offset,
  ptsto32m _ a offset vs ===> ptsto32m' _ a offset vs.
  induction vs; intros.

  apply Himp_refl.

  unfold ptsto32m', ptsto32m; fold ptsto32m; fold ptsto32m'.
  replace (match offset with
             | 0 => a
             | S _ => a ^+ $ (offset)
           end) with (a ^+ $(offset)) by (destruct offset; W_eq).
  destruct vs.
  simpl ptsto32m'.
  eapply Himp_trans; [ | apply Himp_star_comm ].
  apply Himp_star_Emp'.

  apply Himp_star_frame; [ apply Himp_refl | ].
  auto.
Qed.

Lemma ptsto32m_allocated : forall (p : W) (ls : list W) (offset : nat),
  ptsto32m nil p offset ls ===> allocated p offset (length ls).
  intros; eapply Himp_trans.
  apply ptsto32m'_in.
  apply ptsto32m'_allocated.
Qed.

Lemma do_return' : forall ns ns' vs avail avail' p p',
  avail = avail' + length ns'
  -> p' = p ^+ natToW (4 * length ns)
  -> (locals ns vs 0 p * Ex vs', locals ns' vs' avail' p') ===> locals ns vs avail p.
  unfold locals; intros.
  eapply Himp_trans; [ apply Himp_star_assoc | ].
  apply Himp_star_frame; [ apply Himp_refl | ].
  unfold allocated; fold allocated.
  eapply Himp_trans; [ apply Himp_star_Emp | ].
  apply Himp'_ex; intro vs'.
  eapply Himp_trans; [ apply Himp_star_assoc | ].
  apply Himp_star_pure_c; intro.
  subst.
  eapply Himp_trans; [ | apply allocated_join ].
  2: instantiate (1 := length ns'); omega.
  apply Himp_star_frame.
  unfold array.
  words'.
  replace (length ns') with (length (toArray ns' vs')) by apply length_toArray.
  apply ptsto32m_allocated.
  apply allocated_shift_base; try omega.
  words.
Qed.

Lemma unexpose_avail : forall ns vs avail p expose avail',
  (expose <= avail)%nat
  -> avail' = avail - expose
  -> locals ns vs avail' p
  * reserved (p ^+ natToW (4 * (length ns + avail'))) expose
  ===> locals ns vs avail p.
  unfold locals; intros.
  eapply Himp_trans; [ apply Himp_star_assoc | ].
  apply Himp_star_frame; [ apply Himp_refl | ].
  eapply Himp_trans; [ | apply allocated_join ].
  2: instantiate (1 := avail'); omega.
  apply Himp_star_frame; [ apply Himp_refl | ].
  apply allocated_shift_base; try omega.
  subst.
  words.
Qed.

Lemma do_return : forall ns ns' vs avail avail' p p',
  (avail >= avail' + length ns')%nat
  -> p' = p ^+ natToW (4 * length ns)
  -> (locals ns vs 0 p * Ex vs', locals ns' vs' avail' p'
    * reserved (p ^+ natToW (4 * (length ns + length ns' + avail')))
    (avail - length ns' - avail'))
    ===> locals ns vs avail p.
  intros.
  eapply Himp_trans; [ | apply do_return' ].
  3: eassumption.
  Focus 2.
  instantiate (1 := ns').
  instantiate (1 := (avail - avail' - length ns') + avail').
  omega.
  apply Himp_star_frame; [ apply Himp_refl | ].
  apply Himp_ex; intro vs'.
  unfold locals.
  eapply Himp_trans; [ apply Himp_star_assoc | ].
  apply Himp_star_frame; [ apply Himp_refl | ].
  eapply Himp_trans; [ | apply allocated_join ].
  2: instantiate (1 := avail'); omega.
  apply Himp_star_frame; [ apply Himp_refl | ].
  apply allocated_shift_base; try omega.
  subst.
  words.
Qed.


(** ** Point-of-view switch in function preludes *)

Definition agree_on (vs vs' : vals) (ns : list string) :=
  List.Forall (fun nm => sel vs nm = sel vs' nm) ns.

Fixpoint merge (vs vs' : vals) (ns : list string) :=
  match ns with
    | nil => vs'
    | nm :: ns' => upd (merge vs vs' ns') nm (sel vs nm)
  end.

Lemma Forall_weaken : forall A (P P' : A -> Prop),
  (forall x, P x -> P' x)
  -> forall ls, List.Forall P ls
    -> List.Forall P' ls.
Proof.
  induction 2; simpl; intuition.
Qed.

Theorem merge_agree : forall vs vs' ns,
  agree_on (merge vs vs' ns) vs ns.
Proof.
  induction ns; simpl; intuition; constructor.
  unfold sel, upd.
  rewrite string_eq_true; reflexivity.
  eapply Forall_weaken; [ | eassumption ].
  simpl; intros.
  destruct (string_dec a x); subst.
  apply sel_upd_eq; reflexivity.
  rewrite sel_upd_ne; assumption.
Qed.

Theorem prelude_in : forall ns ns' vs avail p,
  (length ns' <= avail)%nat
  -> NoDup (ns ++ ns')
  -> locals ns vs avail p ===>
  Ex vs', locals (ns ++ ns') (merge vs vs' ns) (avail - length ns') p.
Proof. Admitted.
(*  unfold locals, empB, emp, starB, star, exB, ex, injB, inj.
  unfold locals, empB, emp, starB, star, exB, ex, injB, inj.
  intros; hnf; intros; hnf; intros.
  apply Imply_I.
  eapply Exists_E.
  from_hyp.
  simp; intro.
  eapply Exists_E.
  from_hyp.
  simp; intro.
  eapply Exists_E.
  eapply And_E1; eapply And_E2; from_hyp.
  simp; intro.
  eapply Exists_E.
  from_hyp.
  simp; intro.
  pure (split m B B0).
  pure (split B B1 B2).
  pure (semp B1).
  generalize (split_semp _ _ _ H2 H3); intro; subst.
  eapply Exists_E.
  eapply Imply_E.
  apply interp_weaken; apply allocated_split.
  2: from_hyp.
  eassumption.
  simp; intro.
  eapply Exists_E.
  from_hyp.
  simp; intro.
  pure (split B0 B B3).
  eapply Exists_E.
  eapply Imply_E.
  apply interp_weaken; apply behold_the_array.
  2: from_hyp.

  Lemma NoDup_unapp2 : forall A (ls1 ls2 : list A),
    NoDup (ls1 ++ ls2)
    -> NoDup ls2.
  Proof.
    induction ls1; inversion 1; simpl in *; intuition.
  Qed.

  eapply NoDup_unapp2; eauto.
  simp; intro.
  apply Exists_I with B4.
  apply Exists_I with (HT.join B2 B); apply Exists_I with B3.
  repeat apply And_I.
  apply Inj_I.
  assert (disjoint B2 B).
  eapply split_split_disjoint.
  apply split_comm; eassumption.
  eassumption.
  eapply split_assoc in H4.
  rewrite disjoint_join; eauto.
  assumption.

  apply Exists_I with smem_emp; apply Exists_I with (HT.join B2 B).
  repeat apply And_I.
  apply Inj_I; apply split_a_semp_a.
  apply Inj_I; assumption.
  apply Inj_I; reflexivity.
  unfold array.
*)
  Lemma ptsto32m'_merge : forall p vs' ns' ns offset vs vs'',
    NoDup (ns ++ ns')
    -> agree_on vs'' (merge vs vs' ns) (ns ++ ns')
    -> ptsto32m' nil p offset (toArray ns vs)
    * ptsto32m' nil p (offset + 4 * length ns) (toArray ns' vs')
    ===> ptsto32m' nil p offset (toArray (ns ++ ns') vs'').
  Proof. Admitted. (*
    induction ns; simpl app; intros.

    simpl; intro.
    apply himp_star_emp_p.
    apply himp_refl.
    
    Lemma toArray_vals_eq : forall vs vs' ns, agree_on vs vs' ns
      -> toArray ns vs = toArray ns vs'.
    Proof.
      induction ns; simpl; intuition.
      inversion H; clear H; subst.
      f_equal; auto.
    Qed.

    Lemma agree_on_symm : forall vs vs' nm, agree_on vs vs' nm
      -> agree_on vs' vs nm.
    Proof.
      intros; eapply Forall_weaken; [ | eauto ].
      intuition.
    Qed.

    f_equal.
    omega.
    simpl in *.
    apply toArray_vals_eq; auto.
    apply agree_on_symm; auto.

    inversion H; clear H; subst.
    simpl in H0.
    simpl toArray; simpl length.
    unfold ptsto32m'; fold ptsto32m'.
    eapply Himp_trans.
    intro.
    eapply himp_star_assoc.
    intro.
    inversion H0; clear H0; subst.
    rewrite sel_upd_eq in H2 by reflexivity.
    apply himp_star_frame.
    apply himp_refl.
    f_equal.
    auto.
    replace (offset + 4 * S (length ns))
      with ((4 + offset) + 4 * length ns) by omega.
    apply IHns; auto.
    hnf.

    Lemma Forall_weaken' : forall A (P P' : A -> Prop) ls,
      List.Forall P ls
      -> (forall x, In x ls -> P x -> P' x)
      -> List.Forall P' ls.
    Proof.
      induction 1; simpl; intuition.
    Qed.
    
    eapply Forall_weaken'.
    eassumption.
    simpl; intros.
    rewrite H0.
    destruct (string_dec a x); subst.
    tauto.
    rewrite sel_upd_ne by assumption; reflexivity.
  Qed.
*)

  Lemma ptsto32m_merge : forall p vs' ns' ns offset vs vs'',
    NoDup (ns ++ ns')
    -> agree_on vs'' (merge vs vs' ns) (ns ++ ns')
    -> ptsto32m nil p offset (toArray ns vs)
    * ptsto32m nil p (offset + 4 * length ns) (toArray ns' vs')
    ===> ptsto32m nil p offset (toArray (ns ++ ns') vs'').
  Proof.
    intros.
    eapply Himp_trans.
    intro.
    apply himp_star_frame; apply ptsto32m'_in.
    eapply Himp_trans; [ | apply ptsto32m'_out ].
    apply ptsto32m'_merge; auto.
  Qed.
(*
  eapply Imply_E.
  apply interp_weaken; apply ptsto32m_merge; auto.
*)  
  Lemma agree_on_refl : forall vs ns,
    agree_on vs vs ns.
  Proof.
    unfold agree_on; induction ns; simpl; intuition.
  Qed.
(*
  apply agree_on_refl.
  
  do 2 eapply Exists_I.
  repeat apply And_I.
  apply Inj_I.
  apply disjoint_split_join.
  eapply split_split_disjoint in H4.
  eauto.
  apply split_comm; eassumption.
  from_hyp.
  replace (0 + 4 * length ns) with (length ns * 4) by omega.

  Lemma ptsto32m'_shift_base : forall p n ls offset,
    (n <= offset)%nat
    -> ptsto32m' nil (p ^+ $(n)) (offset - n) ls
    ===> ptsto32m' nil p offset ls.
  Proof.
    induction ls.

    simpl; intros; apply Himp_refl.

    unfold ptsto32m'; fold ptsto32m'.
    intros.
    intro; apply himp_star_frame.
    apply himp_refl.
    f_equal.
    rewrite <- wplus_assoc.
    rewrite <- natToW_plus.
    unfold natToW.
    repeat f_equal.
    omega.
    replace (4 + (offset - n)) with ((4 + offset) - n) by omega.
    apply IHls; omega.
  Qed.

  Lemma ptsto32m_shift_base : forall p n ls offset,
    (n <= offset)%nat
    -> ptsto32m nil (p ^+ $(n)) (offset - n) ls
    ===> ptsto32m nil p offset ls.
  Proof.
    intros; eapply Himp_trans.
    apply ptsto32m'_in.
    eapply Himp_trans.
    apply ptsto32m'_shift_base; auto.
    apply ptsto32m'_out.
  Qed.

  eapply Imply_E.
  apply interp_weaken; apply ptsto32m_shift_base.    
  eauto.
  replace (length ns * 4 - length ns * 4) with 0 by omega.
  from_hyp.

  eapply Imply_E.
  apply interp_weaken; apply allocated_shift_base.
  3: from_hyp.
  rewrite (wplus_comm _ (natToW 0)).
  rewrite wplus_unit.
  rewrite plus_O_n.
  rewrite <- wplus_assoc.
  rewrite <- natToWord_plus.
  do 2 f_equal.
  rewrite app_length.
  omega.
  reflexivity.
Qed.
*)

Theorem prelude_out : forall ns ns' vs avail p,
  (length ns' <= avail)%nat
  -> locals (ns ++ ns') vs (avail - length ns') p
  ===> locals ns vs avail p.
Proof. Admitted.
(*
  Lemma ptsto32m'_split : forall p ns' ns offset vs,
    ptsto32m' nil p offset (toArray (ns ++ ns') vs)
    ===> ptsto32m' nil p offset (toArray ns vs)
    * ptsto32m' nil p (offset + 4 * length ns) (toArray ns' vs).
  Proof.
    induction ns.

    simpl.
    intros.
    intro.
    apply himp_star_emp_c.
    apply himp_refl.
    f_equal.
    omega.

    simpl toArray; simpl length.
    unfold ptsto32m'; fold ptsto32m'.
    intros.
    eapply Himp_trans.

    Lemma himp_star_assoc' : forall pcType stateType (cs : codeSpec pcType stateType) (P Q R : hprop pcType stateType nil),
      himp cs (star P (star Q R)) (star (star P Q) R).
    Proof.
      intros; hnf; intros; hnf; intros.
      unfold star.
      apply Imply_I.
      eapply Exists_E.
      from_hyp.
      simp; intro.
      eapply Exists_E.
      from_hyp.
      simp; intro.
      eapply Exists_E.
      do 2 eapply And_E2; from_hyp.
      simp; intro.
      eapply Exists_E.
      from_hyp.
      simp; intro.
      pure (split m B B0).
      pure (split B0 B1 B2).
      apply Exists_I with (HT.join B B1); apply Exists_I with B2.
      repeat apply And_I.
      apply Inj_I.
      assert (disjoint B B1).
      eapply split_split_disjoint; [ | eauto ].
      apply split_comm; eauto.
      eapply split_assoc in H0.
      rewrite disjoint_join; eauto.
      assumption.
      apply Exists_I with B; apply Exists_I with B1.
      repeat apply And_I.
      apply Inj_I.
      apply disjoint_split_join.
      eapply split_split_disjoint; [ | eauto ].
      apply split_comm; eauto.
      from_hyp.
      from_hyp.
      from_hyp.
    Qed.

    eapply Himp_trans; [ | intro; apply himp_star_assoc' ].
    intro; apply himp_star_frame.
    reflexivity.
    apply IHns.
    replace (offset + 4 * S (length ns))
      with ((4 + offset) + 4 * length ns) by omega.
    apply Himp_refl.
  Qed.

  Lemma ptsto32m_split : forall p ns' ns offset vs,
    ptsto32m nil p offset (toArray (ns ++ ns') vs)
    ===> ptsto32m nil p offset (toArray ns vs)
    * ptsto32m nil p (offset + 4 * length ns) (toArray ns' vs).
  Proof.
    intros; eapply Himp_trans.
    apply ptsto32m'_in.
    eapply Himp_trans.
    apply ptsto32m'_split.
    intro; apply himp_star_frame; apply ptsto32m'_out.
  Qed.

  unfold locals, empB, emp, starB, star, exB, ex, injB, inj.
  intros; hnf; intros; hnf; intros.
  apply Imply_I.
  eapply Exists_E.
  from_hyp.
  simp; intro.
  eapply Exists_E.
  from_hyp.
  simp; intro.
  eapply Exists_E.
  eapply And_E1; eapply And_E2; from_hyp.
  simp; intro.
  eapply Exists_E.
  from_hyp.
  simp; intro.
  pure (split m B B0).
  pure (split B B1 B2).
  pure (semp B1).
  generalize (split_semp _ _ _ H1 H2); intro; subst.
  eapply Exists_E.
  eapply Imply_E.
  apply interp_weaken; apply ptsto32m_split.
  from_hyp.
  simp; intro.
  eapply Exists_E.
  from_hyp.
  simp; intro.
  pure (split B2 B B3).
  pure (NoDup (ns ++ ns')).
  apply Exists_I with B; apply Exists_I with (HT.join B0 B3).
  repeat apply And_I.
  apply Inj_I.
  assert (disjoint B0 B3).
  eapply split_split_disjoint.
  eauto.
  apply split_comm; eauto.
  apply split_comm in H3.
  eapply split_assoc in H3.
  rewrite disjoint_join; eauto.
  apply split_comm; eauto.
  apply split_comm; eauto.

  apply Exists_I with smem_emp; apply Exists_I with B;
    repeat apply And_I.
  apply Inj_I; apply split_a_semp_a.

  Lemma NoDup_unapp1 : forall A (ls1 ls2 : list A),
    NoDup (ls1 ++ ls2)
    -> NoDup ls1.
  Proof.
    induction ls1; inversion 1; simpl in *; intuition; subst; constructor.
    intro; apply H2.
    apply in_or_app; auto.
    eauto.
  Qed.

  apply Inj_I; eapply NoDup_unapp1; eassumption.
  apply Inj_I; reflexivity.
  from_hyp.

  eapply Imply_E.
  apply interp_weaken; apply allocated_join.
  eassumption.
  apply Exists_I with B3; apply Exists_I with B0.
  repeat apply And_I.
  apply Inj_I.
  rewrite disjoint_join; eauto.  
  eapply disjoint_split_join.
  apply disjoint_comm.
  eapply split_split_disjoint.
  eauto.
  apply split_comm; eauto.
  eapply split_split_disjoint.
  eauto.
  apply split_comm; eauto.

  erewrite <- (length_toArray ns' vs).
  eapply Imply_E.
  apply interp_weaken.
  apply ptsto32m_allocated.
  eapply Imply_E.
  apply interp_weaken.

  Lemma ptsto32m'_shift_base' : forall p n ls offset,
    (n <= offset)%nat
    -> ptsto32m' nil p offset ls
    ===> ptsto32m' nil (p ^+ $(n)) (offset - n) ls.
  Proof.
    induction ls.

    simpl; intros; apply Himp_refl.

    unfold ptsto32m'; fold ptsto32m'.
    intros.
    intro; apply himp_star_frame.
    apply himp_refl.
    f_equal.
    rewrite <- wplus_assoc.
    rewrite <- natToW_plus.
    unfold natToW.
    repeat f_equal.
    omega.
    replace (4 + (offset - n)) with ((4 + offset) - n) by omega.
    apply IHls; omega.
  Qed.

  Lemma ptsto32m_shift_base' : forall p n ls offset,
    (n <= offset)%nat
    -> ptsto32m nil p offset ls
    ===> ptsto32m nil (p ^+ $(n)) (offset - n) ls.
  Proof.
    intros; eapply Himp_trans.
    apply ptsto32m'_in.
    eapply Himp_trans.
    apply ptsto32m'_shift_base'.
    2: apply ptsto32m'_out.
    auto.
  Qed.

  apply Imply_trans with (ptsto32m nil (p ^+ $ (Datatypes.length ns * 4)) (length ns * 4 - length
    ns * 4) (toArray ns' vs) s B3).
  apply ptsto32m_shift_base'.
  auto.
  apply Imply_I.
  apply Env; simp.
  left; f_equal.
  omega.
  replace (length ns * 4) with (0 + 4 * length ns) by omega.
  from_hyp.
  eapply Imply_E.
  apply interp_weaken; apply allocated_shift_base.
  3: from_hyp.
  rewrite (wplus_comm _ (natToW 0)).
  rewrite wplus_unit.
  rewrite plus_O_n.
  rewrite <- wplus_assoc.
  rewrite <- natToWord_plus.
  do 2 f_equal.
  rewrite app_length.
  omega.
  reflexivity.
Qed.  
*)