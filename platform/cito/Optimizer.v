Require Import Syntax.
Require Import Semantics.
Import SemanticsExpr.
Import Safety.
Require Import GeneralTactics.
Import WDict.
Import WMake.

Set Implicit Arguments.

Inductive Outcome := 
  | Done : st -> Outcome
  | ToCall : W -> W -> Statement -> st -> Outcome.
                   
Inductive Step : Statement -> st -> Outcome -> Prop :=
  | Skip : forall v, Step Syntax.Skip v (Done v)
  | Seq1 : forall v v' v'' a b,
      Step a v (Done v') -> 
      Step b v' v'' -> 
      Step (Syntax.Seq a b) v v''
  | Seq2 : forall v v' a b f x s,
      Step a v (ToCall f x s v') -> 
      Step (Syntax.Seq a b) v (ToCall f x (Syntax.Seq s b) v')
  | Calling : forall vs arrs f arg,
      let v := (vs, arrs) in
      let f_v := exprDenote f vs in
      let arg_v := exprDenote arg vs in
      Step (Syntax.Call f arg) v (ToCall f_v arg_v Syntax.Skip v)
  | IfTrue : forall v v' cond t f, 
      wneb (exprDenote cond (fst v)) $0 = true -> 
      Step t v v' -> 
      Step (Conditional cond t f) v v'
  | IfFalse : forall v v' cond t f, 
      wneb (exprDenote cond (fst v)) $0 = false -> 
      Step f v v' -> 
      Step (Conditional cond t f) v v'
  | WhileFalse : forall v cond body, 
      wneb (exprDenote cond (fst v)) $0 = false -> 
      Step (Loop cond body) v (Done v)
  | WhileTrue1 : forall v v' v'' cond body, 
      let loop := Loop cond body in
      wneb (exprDenote cond (fst v)) $0 = true -> 
      Step body v (Done v') -> 
      Step loop v' v'' -> 
      Step loop v v''
  | WhileTrue2 : forall cond body v f x s' v', 
      let loop := Loop cond body in
      wneb (exprDenote cond (fst v)) $0 = true -> 
      Step body v (ToCall f x s' v') -> 
      Step loop v (ToCall f x (Syntax.Seq s' loop) v')
  | Assign : forall var value vs arrs, 
      let v := (vs, arrs) in
      let value_v := exprDenote value vs in
      Step (Syntax.Assignment var value) v (Done (Locals.upd vs var value_v, arrs))
  | Read : forall var arr idx vs (arrs : arrays),
      let v := (vs, arrs) in
      let arr_v := exprDenote arr vs in
      let idx_v := exprDenote idx vs in
      safe_access arrs arr_v idx_v -> 
      let value_v := Array.sel (snd arrs arr_v) idx_v in  
      Step (Syntax.ReadAt var arr idx) v (Done (Locals.upd vs var value_v, arrs))
  | Write : forall arr idx value vs (arrs : arrays), 
      let v := (vs, arrs) in
      let arr_v := exprDenote arr vs in
      let idx_v := exprDenote idx vs in
      safe_access arrs arr_v idx_v ->
      let value_v := exprDenote value vs in
      let new_arr := Array.upd (snd arrs arr_v) idx_v value_v in
      Step (Syntax.WriteAt arr idx value) v (Done (vs, (fst arrs, upd (snd arrs) arr_v new_arr)))  | Len : forall var arr vs arrs,
      let v := (vs, arrs) in
      let arr_v := exprDenote arr vs in
      arr_v %in fst arrs ->
      let len := natToW (length (snd arrs arr_v)) in
      Step (Syntax.Len var arr) v (Done (Locals.upd vs var len, arrs))
  | Free : forall arr vs (arrs : arrays),
      let v := (vs, arrs) in
      let arr_v := exprDenote arr vs in
      arr_v %in fst arrs ->
      Step (Syntax.Free arr) v (Done (vs, (fst arrs %- arr_v, snd arrs)))
  | Malloc : forall var size vs arrs addr ls,
      let v := (vs, arrs) in
      ~ (addr %in fst arrs) ->
      let size_v := wordToNat (exprDenote size vs) in
      goodSize (size_v + 2) ->
      length ls = size_v ->
      Step (Syntax.Malloc var size) v (Done (Locals.upd vs var addr, (fst arrs %+ addr, upd (snd arrs) addr ls)))
.

Definition is_backward_simulation (R : Statement -> Statement -> Prop) : Prop :=
  forall s t, 
    R s t -> 
    (forall v v',
       Step t v (Done v') -> Step s v (Done v')) /\
    (forall v f x v' t', 
       Step t v (ToCall f x t' v') -> 
       exists s', 
         Step s v (ToCall f x s' v') /\ 
         R s' t').

Definition is_backward_similar s t := exists R, is_backward_simulation R /\ R s t.

(* each function can be optimized by different optimizors *)
Inductive is_backward_similar_callee : Callee -> Callee -> Prop :=
  | BothForeign : 
      forall spec1 spec2 : callTransition -> Prop, 
        (forall x, spec2 x -> spec1 x) -> 
        is_backward_similar_callee (Foreign spec1) (Foreign spec2)
  | BothInternal : 
      forall body1 body2, 
        is_backward_similar body1 body2 -> 
        is_backward_similar_callee (Internal body1) (Internal body2).

Definition is_backward_similar_fs fs1 fs2 := 
  forall (w : W) callee2,
    fs2 w = Some callee2 ->
    exists callee1,
      fs1 w = Some callee1 /\
      is_backward_similar_callee callee1 callee2.

Section Functions.

  Variable fs : W -> option Callee.

  Inductive StepsTo : Statement -> st -> st -> Prop :=
  | NoCall :
      forall s v v',
        Step s v (Done v') ->
        StepsTo s v v'
  | HasForeign :
      forall s v f x s' v' spec v'' v''',
        Step s v (ToCall f x s' v') ->
        fs f = Some (Foreign spec) -> 
        spec {| Arg := x; InitialHeap := snd v'; FinalHeap := snd v'' |} ->
        StepsTo s' v'' v''' ->
        StepsTo s v v'''
  | HasInternal :
      forall s v f x s' v' body vs_arg v'' v''',
        Step s v (ToCall f x s' v') ->
        fs f = Some (Internal body) -> 
        Locals.sel vs_arg "__arg" = x ->
        StepsTo body (vs_arg, snd v') v'' ->
        StepsTo s' (fst v', snd v'') v''' ->
        StepsTo s v v'''.

End Functions.

Hint Constructors StepsTo Step.

Lemma StepsTo_Seq : forall fs a v v', StepsTo fs a v v' -> forall b v'', StepsTo fs b v' v'' -> StepsTo fs (Syntax.Seq a b) v v''.
  induction 1; simpl; intuition eauto; inversion H0; subst; eauto.
Qed.
Hint Resolve StepsTo_Seq.

Lemma RunsTo_StepsTo : forall fs s v v', RunsTo fs s v v' -> StepsTo fs s v v'.
  induction 1; simpl; try solve [intuition eauto].

  unfold v, value_v in *; eauto.

  unfold v, arr_v, idx_v, value_v in *; econstructor; econstructor; eauto.

  unfold v, arr_v, idx_v, value_v, new_arr in *; econstructor; econstructor; eauto.
  
  inversion IHRunsTo; subst; eauto.

  inversion IHRunsTo; subst; eauto.

  unfold statement in *.
  inversion IHRunsTo1; subst; eauto.
  inversion IHRunsTo2; subst; eauto.
  
  unfold v, size_v in *; econstructor; econstructor; eauto.

  unfold v, arr_v in *; econstructor; econstructor; eauto.

  unfold v, arr_v, len in *; econstructor; econstructor; eauto.

  unfold v, arg_v in *; econstructor 2; eauto; simpl in *; eauto.

  unfold v, arg_v in *; econstructor 3; eauto; simpl in *; eauto.
Qed.

Hint Constructors RunsTo.

Lemma Done_RunsTo : forall fs s v out, Step s v out -> forall v', out = Done v' -> RunsTo fs s v v'.
  induction 1; simpl; intros; try discriminate; subst; try solve [intuition eauto]; intros.
  injection H; intros; subst; eauto.
  injection H0; intros; subst; eauto.
  econstructor; eauto.
  injection H; intros; subst; econstructor; eauto.
  injection H0; intros; subst; econstructor; eauto.
  injection H0; intros; subst; econstructor; eauto.
  injection H0; intros; subst; econstructor; eauto.
  injection H0; intros; subst; econstructor; eauto.
  injection H2; intros; subst; econstructor; eauto.
Qed.
Hint Resolve Done_RunsTo.

Lemma StepsTo_RunsTo : forall fs s v v', StepsTo fs s v v' -> RunsTo fs s v v'.
  induction 1; simpl; intuition eauto.
  (*here*)


Qed.

Hint Resolve RunsTo_StepsTo StepsTo_RunsTo.

Hint Unfold is_backward_similar is_backward_simulation.

Lemma correct_StepsTo : forall tfs t v v', StepsTo tfs t v v' -> forall sfs s, is_backward_similar s t -> is_backward_similar_fs sfs tfs -> StepsTo sfs s v v'.
  induction 1; simpl; intuition.

  destruct H0; openhyp.
  eapply H0 in H2; openhyp.
  econstructor; eauto.

  destruct H3; openhyp.
  eapply H3 in H5; openhyp.
  eapply H6 in H; openhyp.
  eapply H4 in H0; openhyp.
  inversion H8; subst.
  econstructor 2; eauto.
  eapply H11; eauto.

  destruct H4; openhyp.
  eapply H4 in H6; openhyp.
  eapply H7 in H; openhyp.
  eapply H5 in H0; openhyp.
  inversion H9; subst.
  econstructor 3; eauto.
Qed.
Hint Resolve correct_StepsTo.

Theorem correct_RunsTo : forall sfs s tfs t, is_backward_similar s t -> is_backward_similar_fs sfs tfs -> forall v v', RunsTo tfs t v v' -> RunsTo sfs s v v'.
  intuition eauto.
Qed.

Theorem correct_Safe : forall sfs s tfs t, is_backward_similar s t -> is_backward_similar_fs sfs tfs -> forall v, Safe sfs s v -> Safe tfs t v.
  admit.
Qed.

Hint Resolve correct_RunsTo correct_Safe.

Theorem correct : 
  forall sfs s tfs t, 
    is_backward_similar s t -> 
    is_backward_similar_fs sfs tfs -> 
    forall v, 
      (Safe sfs s v -> Safe tfs t v) /\ 
      forall v', 
        RunsTo tfs t v v' -> RunsTo sfs s v v'.
  intuition eauto.
Qed.
