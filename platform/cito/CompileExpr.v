Require Import AutoSep Wrap Arith.
Import DefineStructured.
Require Import ExprLemmas VariableLemmas GeneralTactics.
Require Import SyntaxExpr SemanticsExpr.

Set Printing Coercions.
Set Implicit Arguments. 

(* The depth of stack actually used by compileExpr *)
Fixpoint depth expr := 
  match expr with
    | Var _ => 0
    | Const _ => 0
    | Binop _ a b => max (depth a) (S (depth b))
    | TestE _ a b => max (depth a) (S (depth b))
  end.

Fixpoint varsIn expr:=
  match expr with
    |Var s => s :: nil
    |Const w => nil
    |Binop op a b => varsIn a ++ varsIn b
    |TestE te a b => varsIn a ++ varsIn b
  end.

Ltac clear_imports :=
  match goal with
    Him : LabelMap.t assert |- _ =>
      repeat match goal with
               H : context [ Him ] |- _ => clear H
             end; 
      clear Him
  end.

Ltac HypothesisParty H := 
  match type of H with
    | interp _ (![ _ ](_, ?x)) => 
      repeat match goal with 
               | [H0: evalInstrs _ x _ = _, H1: evalInstrs _ _ _ = _ |- _] => not_eq H0 H1; generalize dependent H1
               | [H0: evalInstrs _ x _ = _, H1: interp _ _ |- _] => not_eq H H1; generalize dependent H1
             end
  end.

Section ExprComp.

(* setting up for new compilation *)
  Variable imports : LabelMap.t assert.
  Variable imports_global : importsGlobal imports.
  Variable modName : string.
  Variable vars : list string.

  Definition Seq2 := @Seq_ _ imports_global modName.
  Definition Skip := Straightline_ imports modName nil.
  Fixpoint Seq ls :=
    match ls with
      | nil => Skip
      | a :: ls' => Seq2 a (Seq ls')
    end.
  Definition Strline := Straightline_ imports modName.

  Fixpoint compile vars expr base_mem:=
    match expr with
      | Var str => Strline (Assign (LvReg Rv) (RvLval (variableSlot str vars)) :: nil)
      | Const w => Strline (Assign (LvReg Rv) (RvImm w) :: nil)
      | Binop op a b => Seq (
        compile vars a base_mem :: 
        Strline(Assign (variableSlot (tempOf base_mem) vars) (RvLval (LvReg Rv)) :: nil) :: 
        compile vars b (S base_mem) :: 
        (Strline (IL.Binop (LvReg Rv) (RvLval (variableSlot (tempOf base_mem) vars )) op (RvLval (LvReg Rv)) :: nil)) :: nil)
      | TestE te a b => Seq (compile vars a base_mem ::
        Strline( Assign (variableSlot (tempOf base_mem) vars) (RvLval (LvReg Rv)) :: nil ) ::
        compile vars b (S base_mem) ::
        Structured.If_ imports_global (RvLval (variableSlot (tempOf base_mem) vars )) te (RvLval (LvReg Rv))
        (Strline (Assign Rv (RvImm $1) :: nil))
        (Strline (Assign Rv (RvImm $0) :: nil))
        ::nil)
    end.

  Ltac not_eq H1 H2 := 
    match H1 with
      | H2 => fail 1
      | _ => idtac
    end.

  Ltac openHyp := 
    match goal with
      | [H: _ /\ _ |- _ ] => destruct H
      | [H: exists x, _ |- _ ] => destruct H
    end.
  Ltac openSS:= 
    match goal with
      | [x: prod settings state |- _ ]=> destruct x; rewriter
    end.
  Ltac reverse_interp:=
    match goal with
      | [H: interp ?specs (![ SEP.ST.star ?other (locals ?vars ?base ?res ?reg) ] ?pair) |- _ ] =>
        assert (interp specs (![(locals vars base res reg) * other] pair)) by (step auto_ext); clear H
    end.
  Ltac reverse_interp' H:=
    match H with
      | interp ?specs (![ SEP.ST.star ?other (locals ?vars ?base ?res ?reg) ] ?pair) =>
        assert (interp specs (![(locals vars base res reg) * other] pair)) by (step auto_ext); clear H
    end.
  Ltac open_pair:=
    match goal with
      | [H : context[ fst ( _, _ )] |- _ ] => unfold fst in H
      | [H : context[ snd ( _, _ )] |- _ ] => unfold snd in H
    end.
  Ltac interpHyp:= repeat open_pair; rewriter'; try reverse_interp;
    match goal with 
      | [H0: forall _ _, (interp _ _) -> _ , H1: interp _ _|- _] => eapply H0 in H1; clear H0 
      | [H0: forall _ _ _, (interp _ _) -> _ , H1: interp _ _|- _] => eapply H0 in H1; clear H0
      | [H0: forall _ _ _ _, (interp _ _) -> _ , H1: interp _ _|- _] => eapply H0 in H1; clear H0
    end.
(*Open boolean comparison*)
  Require Import Word.
  Hint Extern 1 (weqb _ _ = true) => apply weqb_true_iff.
  Lemma weqb_eq: forall w1 w2, w1 = w2 -> IL.weqb w1 w2 =  true.
    intros. unfold IL.weqb; auto.
  Qed.
  Lemma wneb_ne: forall w1 w2, w1 <> w2 -> IL.wneb w1 w2 =  true.
    intros; unfold wneb; destruct (weq w1 w2); auto.
  Qed.
  Lemma wltb_lt: forall w1 w2, w1 < w2 -> IL.wltb w1 w2 = true.
     unfold wltb; intros; destruct (wlt_dec w1 w2); auto.
  Qed.
  Lemma wleb_le: forall w1 w2, w1 <= w2 -> IL.wleb w1 w2 = true.
    unfold wleb; intros; destruct (weq w1 w2); destruct (wlt_dec w1 w2); auto.
    elimtype False; apply n.
    assert (wordToNat w1 = wordToNat w2) by nomega.
    apply (f_equal (fun w => natToWord 32 w)) in H0.
    repeat rewrite natToWord_wordToNat in H0.
    assumption.
  Qed.
  Lemma weqb_ne: forall w1 w2, w1 <> w2 -> IL.weqb w1 w2 = false.
    unfold IL.weqb; intros; generalize (weqb_true_iff w1 w2); destruct (Word.weqb w1 w2); intuition.
  Qed.
  Lemma wneb_eq: forall w1 w2, w1 = w2 -> IL.wneb w1 w2 =  false.
   unfold IL.wneb; intros; destruct (weq w1 w2); intuition.
  Qed.
  Lemma wltb_geq: forall w1 w2, w2 <= w1 -> IL.wltb w1 w2 = false.
    unfold IL.wltb; intros; destruct (wlt_dec w1 w2); intuition.
  Qed.
  Lemma wleb_gt: forall w1 w2, w2 < w1 -> IL.wleb w1 w2 = false.
    unfold IL.wleb; intros; destruct (weq w1 w2); destruct (wlt_dec w1 w2); intuition; nomega.
  Qed.
  Ltac solve_test:=
    match goal with
      | _ => rewrite weqb_eq; [ solve[ rewriter; eauto ] | ]
      | _ => rewrite wneb_ne; [ solve[ rewriter; eauto ] | ]
      | _ => rewrite wltb_lt; [ solve[ rewriter; eauto ] | ]
      | _ => rewrite wleb_le; [ solve[ rewriter; eauto ] | ]
      | _ => rewrite weqb_ne; [ solve[ rewriter; eauto ] | ]
      | _ => rewrite wneb_eq; [ solve[ rewriter; eauto ] | ]
      | _ => rewrite wltb_geq; [ solve[ rewriter; eauto ] | ]
      | _ => rewrite wleb_gt; [ solve[ rewriter; eauto ] | ]
    end.

  Lemma sameDenote: forall vs1 vs2 ls expr, 
    disj (varsIn expr) ls -> changedVariables vs2 vs1 ls -> exprDenote expr vs1 = exprDenote expr vs2.
    induction expr; simpl; intuition.
    unfold changedVariables in H. 
    destruct (weq (vs1 s) (vs2 s)); auto.
    apply H0 in n.
    assert (In s (s::nil)) by intuition.
    apply H in n; intuition.
    destruct b; simpl; intuition; f_equal;
      first [apply IHexpr1 | apply IHexpr2 ]; variables.
    rewrite IHexpr1; try rewrite IHexpr2; variables.
  Qed.

  Ltac final:= descend; rewriter';
    match goal with
      | _ => solve_test;
        match goal with
          | [H:context [ (exprDenote ?e2 ?v1) ] |- context [exprDenote ?e2 ?v2 ] ] => not_eq v1 v2; replace (exprDenote e2 v2) with (exprDenote e2 v1) by (eapply sameDenote; variables); eauto
        end
      | _ => f_equal; [ erewrite eval_changed_vars; eauto; [eapply sel_upd_eq; eauto| eapply temps_not_in_array; eauto] | ]
      | |- interp _ _ => step auto_ext
      | _ => idtac
    end; try eapply sameDenote; variables.
  
  Lemma In_cons A (rp:A): forall X ls, In X ls -> In X (rp :: ls).
    intros. Transparent In.
    simpl. tauto.
  Qed.
  (*Prep locals that works even if [In] is Opaque*)
  Ltac prep_locals_magic:=
    unfold variableSlot in *; repeat rewrite four_plus_variablePosition in * by assumption;
      repeat match goal with
               | [ H : In ?X ?ls |- _ ] =>
                 match ls with
                   | "rp" :: _ => fail 1
                   | _ =>
                     match goal with
                       | [ _ : In X ("rp" :: ls) |- _ ] => fail 1
                       | _ => assert (In X ("rp" :: ls)) by (eapply In_cons; eauto)
                     end
                 end
             end.

  Ltac safeConditionForEval:=
    match goal with
      | [H: evalInstrs _ _ ?inst = _ |- _] =>
        match inst with
          | context[variableSlot ?s ?vars] => 
            match s with
              | tempOf ?m => assert (Safe: In (tempOf (m)) vars) by variables
              | _ => assert (Safe: In s vars) by intuition
            end
        end
    end. 

  Lemma noChange: forall v1 v2 n m w1,
    changedVariables (upd v1 (tempOf n) w1) v2
    (tempChunk (S n) m) -> sel v2 (tempOf n) = w1.
    intros.
    destruct (weq (sel v2 (tempOf n)) w1); auto.    
    unfold changedVariables in H.
    assert (sel (upd v1 (tempOf n) w1) (tempOf n) = w1).
    rewrite sel_upd_eq; auto.
    rewrite<- H0 in n0.
    eapply H in n0.
    contradict n0.
    variables.
  Qed.
  (*Very specific tactic. Asserts that [tempOf n] hasn't change.*)
  Ltac use_noChange:= 
    match goal with 
      | [H: changedVariables (upd _ (tempOf ?n) _) _ (tempChunk (S ?n) _) |- _ ] => generalize H; eapply noChange in H; intro
    end. 
  Ltac safe_eval:= 
    try clear_imports; match goal with
      |[H: interp _ (![?P](_, ?x)), H': evalCond _ ?t _ _ ?x = _ |- _ ] =>
      try use_noChange; HypothesisParty H; move H' after H; destruct t
        |[H: interp _ (![?P](_, ?x)), H': evalInstrs _ ?x ?insts = _ |- _ ] =>
        HypothesisParty H
        ;match insts with
           | (IL.Binop _ _ ?b _ ) :: _ => destruct b
           | _ => idtac
         end
    end; try(safeConditionForEval; prep_locals_magic); repeat openSS; repeat open_pair; evaluate auto_ext; intros.
  Ltac finish_interp:=
    match goal with
      | |- interp _ _ => step auto_ext
      | _ => idtac
    end.
  Ltac use_indHyp:=
    match goal with
      | [H: forall _ _, _ ->  vcs _ |- _ ] => eapply H; clear H
      | [H: forall _ _, _ ->  vcs _ |- _ ] => clear H
    end; intros.
  Ltac clear_interp:=
    match goal with
      | [H: interp _ ?x |- _] =>
        match x with
          | sepFormula _ _ => fail 1
          | _ => clear H
        end
    end.
  (*Common way to finish the subgoals after applying hypothesis.*)
  Ltac subgoal_crush:=
    repeat (interpHyp; post; variables) ;
      post; descend; variables.
  Ltac one_step:= 
    first [ interpHyp; [ repeat openHyp | subgoal_crush] | interpHyp; post; variables | safe_eval; rewriter'].

  Lemma expr_preserve: forall expr specs x pre base_mem,
       interp specs (Postcondition (compile vars expr base_mem pre) x) ->
   (forall (specs0 : codeSpec W (settings * state)) (x0 : settings * state),
    interp specs0 (pre x0) ->
    interp specs0
      (ExX  : ST.settings * smem,
       (Ex vs : vals,
        (Ex reserved : nat,
         [|incl (varsIn expr) vars /\
           incl (tempChunk base_mem (depth expr)) vars /\
           disj (varsIn expr) (tempChunk (base_mem) (depth expr)) /\
           (In "rp" vars -> False)|] /\
         ![^[locals ("rp" :: vars) vs reserved (x0) # (Sp)] * #0] x0))%PropX)) ->
   exists x0 : state,
     simplify specs (pre (fst x, x0)) (SNil W (settings * state)) /\
     (forall (specs0 : codeSpec W (ST.settings * state)) 
        (other : hpropB nil) (vs : vals) (reserved : nat),
      interp specs0
        (![locals ("rp" :: vars) vs reserved (Regs x0 Sp) * other] (fst x, x0)) ->
      incl (varsIn expr) vars /\
      incl (tempChunk (base_mem) (depth expr)) vars /\
      disj (varsIn expr) (tempChunk (base_mem) (depth expr)) /\
      (In "rp" vars -> False) ->
      (x) # (Sp) = Regs x0 Sp /\
      (exists vs_new : vals,
         interp specs0
           (![locals ("rp" :: vars) vs_new reserved (x) # (Sp) * other] x) /\
         (x) # (Rv) = exprDenote expr vs /\
         changed_in vs vs_new (tempChunk base_mem (depth expr)))).
    induction expr;
      wrap0;
      repeat openSS;
        try (interpHyp; post; post; [ | subgoal_crush; safe_eval; post; step auto_ext ];
          interpHyp; post; [ | subgoal_crush ]);
        descend; eauto; post; clear_interp; repeat one_step; descend; final. 
  Qed.
  Ltac show_preserve:=
    match goal with
      | [H: interp _ (Postcondition _ _)|- _] =>  eapply expr_preserve in H
    end.
  Lemma expr_progress: forall expr pre base_mem,
    (forall (specs : codeSpec W (settings * state)) (x : settings * state),
    interp specs (pre x) ->
    interp specs
      (ExX  : ST.settings * smem,
       (Ex vs : vals,
        (Ex reserved : nat,
         [|incl (varsIn expr) vars /\
           incl (tempChunk base_mem (depth expr)) vars /\
           disj (varsIn expr) (tempChunk base_mem (depth expr)) /\
           (In "rp" vars -> False)|] /\
         ![^[locals ("rp" :: vars) vs reserved (x) # (Sp)] * #0] x))%PropX)) ->
   vcs (VerifCond (compile vars expr base_mem pre)).
    induction expr;
      wrap0; repeat use_indHyp; propxFo;
        try( show_preserve; post);
          first[ solve [ one_step; descend; variables; pose 1] | post; show_preserve; post; pose 2 | idtac; pose 3]; 
            repeat one_step;
              try (solve [ descend; variables ]); 
                descend; final.
  Qed.

  Definition runs_to_generic require effect x_pre x := 
    forall specs other vs reserved, 
      interp specs (![locals ("rp" :: vars) vs reserved x_pre#Sp * other ] x_pre) 
      -> require vs x_pre#Rv
      -> Regs x Sp = x_pre#Sp 
      /\ exists vs_new, interp specs (![locals ("rp" :: vars) vs_new reserved (Regs x Sp) * other ] (fst x_pre, x)) 
        /\ effect vs x_pre#Rv vs_new (Regs x Rv).

  Variable expr : Expr.
  Variable base_mem : nat.
  Definition expr_vars_require :=
    List.incl (varsIn expr) vars
    /\ List.incl (tempChunk (base_mem) (depth expr)) vars
    /\ disj (varsIn expr)(tempChunk (base_mem) (depth expr))
    /\ ~ In "rp" vars.

  Definition expr_new_pre : assert := x ~> ExX, Ex vs, Ex reserved,
    [| expr_vars_require |]
    /\ ![^[locals ("rp" :: vars) vs reserved x#Sp] * #0]x.

  Definition expr_runs_to := runs_to_generic 
    (fun _ _ => expr_vars_require)
    (fun vs _ vs_new rv_new => 
      rv_new = exprDenote expr vs
      /\ changedVariables vs vs_new (tempChunk base_mem (depth expr))).

  Definition expr_post (pre : assert) := st ~> Ex st_pre, pre (fst st, st_pre)
    /\ [| expr_runs_to (fst st, st_pre) (snd st) |].

  Definition expr_verifCond pre := (forall specs x, interp specs (pre x) -> interp specs (expr_new_pre x)) :: nil.

  Definition body := compile vars expr base_mem.

  Hint Extern 12 => sp_solver.

  Definition exprCmd : cmd imports modName.

    refine (Wrap imports imports_global modName body expr_post expr_verifCond _ _);
    unfold expr_verifCond, expr_new_pre, expr_post, body, expr_runs_to, runs_to_generic; unfold expr_vars_require in *; wrap0;
      [ destruct x; eapply expr_preserve |
        eapply expr_progress ]; eauto.
 Defined.

End ExprComp.
