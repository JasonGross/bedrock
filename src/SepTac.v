Require Import IL SepIL SymIL.
Require Import Word Memory.
Import List.
Require Import DepList EqdepClass.

Require Expr SepExpr.
Module SEP := SymIL.BedrockEvaluator.SEP.
(* (Provers.transitivityEqProverRec funcs) *)
Lemma ApplyCancelSep : forall types hyps funcs eq_prover sfuncs (l r : SEP.sexpr (bedrock_types ++ types) (Expr.tvType O) (Expr.tvType 1)),
  Expr.AllProvable funcs nil nil hyps ->
  forall cs, 
  match SEP.CancelSep (funcs := funcs) eq_prover  hyps l r with
    | {| SEP.vars := vars; 
         SEP.lhs := lhs; SEP.rhs_ex := rhs_ex; 
         SEP.rhs := rhs; SEP.SUBST := SUBST |} =>
      SEP.forallEach vars
        (fun VS : Expr.env (bedrock_types ++ types) =>
          SEP.exists_subst funcs VS
          (ExprUnify.env_of_Subst SUBST rhs_ex 0)
          (fun rhs_ex0 : Expr.env (bedrock_types ++ types) =>
            SEP.himp funcs sfuncs nil rhs_ex0 VS cs lhs rhs))
  end ->
  himp cs (@SEP.sexprD _ funcs _ _ sfuncs nil nil l)
          (@SEP.sexprD _ funcs _ _ sfuncs nil nil r).
Proof.
  unfold Himp. intros. 
  apply SEP.ApplyCancelSep in H0. unfold SEP.himp in *. assumption.
  simpl; tauto.
Qed.

Lemma Himp_to_SEP_himp : forall types funcs sfuncs 
  (l r : @SEP.sexpr (bedrock_types ++ types) (Expr.tvType 0) (Expr.tvType 1)),
  (forall cs, SEP.himp funcs sfuncs nil nil nil cs l r) ->
  (@SEP.sexprD _ funcs _ _ sfuncs nil nil l)
  ===>
  (@SEP.sexprD _ funcs _ _ sfuncs nil nil r).
Proof.
  unfold Himp, SEP.himp. intuition.
Qed.

Require Import PropX.

Lemma pick_cont : forall specs P Q R CPTR stn_st,
  interp specs (![ P ] stn_st)->
  specs CPTR = Some (fun x => R x) ->
  (forall x, interp specs (Q x ---> R x)) ->
  forall CPTR',
  CPTR = CPTR' ->
  interp specs (Q stn_st) ->
  exists pre', specs CPTR' = Some pre' /\ interp specs (pre' stn_st).
Proof. 
  intros; subst; do 2 esplit; try eassumption.
  eapply Imply_E; eauto.
Qed.

Ltac pick_continuation tac :=
  match goal with
    | [ H : interp ?specs (![ ?P ] ?X)
      , H' : ?specs ?CPTR = Some (fun x => ?R x)
      , H'' : forall x, interp ?specs (@?Q x ---> ?R x)%PropX
      |- exists pre', ?specs ?CPTR' = Some pre' /\ interp _ (pre' ?X) ] =>
    apply (@pick_cont specs P Q R CPTR X H H' H'' CPTR'); 
      [ solve [ tac ]
      | PropXTac.propxFo ; autorewrite with sepFormula ; 
        unfold substH ; simpl subst ]
  end.

Lemma interp_interp_himp : forall cs P Q stn_st,
  interp cs (![ P ] stn_st) ->
  (himp cs P Q) ->
  interp cs (![ Q ] stn_st).
Proof.
  unfold himp. intros. destruct stn_st.
  rewrite sepFormula_eq in *. unfold sepFormula_def in *. simpl in *.
  eapply Imply_E; eauto. 
Qed.

Ltac change_to_himp := 
  match goal with
    | [ H : interp ?specs (![ _ ] ?X)
      |- interp ?specs (![ _ ] ?X) ] =>
    eapply (@interp_interp_himp _ _ _ _ H)
  end.

Ltac sep_canceler isConst prover simplifier types' :=
  (try change_to_himp) ;
  match goal with 
    | [ |- himp ?cs ?L ?R ] =>
      let pcT := constr:(W) in
      let stateT := constr:(prod settings state) in
      let types := eval unfold SymIL.bedrock_types in SymIL.bedrock_types in
      let types :=
        match types' with
          | tt => types
          | _ => constr:(types ++ types')
        end
      in
      let goals := constr:(L :: R :: nil) in
      let goals := eval unfold starB exB hvarB in goals in
      SEP.reflect_sexprs pcT stateT ltac:(isConst) types tt tt goals ltac:(fun props proofs types pcT stT funcs sfuncs v =>
        match v with
          | ?L :: ?R :: nil =>
            apply (@ApplyCancelSep (SymIL.bedrock_ext types) props funcs (Provers.transitivityEqProverRec funcs) sfuncs L R proofs)
        end ; simplifier (* ; 
        cbv beta iota zeta delta
          [ SEP.CancelSep

            Provers.transitivityEqProverRec Provers.transitivityEqProver Provers.inSameGroup Provers.eqD
            Provers.eq_prove Provers.eq_summary Provers.eq_summarize Provers.groupsOf

            SEP.star_SHeap SEP.liftSHeap SEP.multimap_join
            SEP.hash SEP.hash' SEP.sepCancel SEP.exists_subst
            SEP.exists_subst SEP.forallEach 
            SEP.unifyArgs SEP.himp SEP.sexprD SEP.sheapD SEP.starred SEP.sheapSubstU 
            SEP.unify_remove_all SEP.unify_remove
            SEP.substV
            
            SepExpr.impures SepExpr.pures SepExpr.other
            SepExpr.SDenotation SepExpr.SDomain

            SepExpr.FM.find SepExpr.FM.add SepExpr.FM.remove SepExpr.FM.remove SepExpr.FM.map SepExpr.FM.empty SepExpr.FM.fold

            app map nth_error value error fold_right length

            Expr.applyD Expr.exprD Expr.Range Expr.Domain Expr.Denotation Expr.Impl
            Expr.liftExpr Expr.exprSubstU Expr.tvarD Expr.lookupAs 
            Expr.EqDec_tvar Expr.tvar_rec Expr.tvar_rect Expr.Eq
            

            ExprUnify.Subst_lookup ExprUnify.fold_left_2_opt
            ExprUnify.exprUnify ExprUnify.empty_Subst ExprUnify.get_Eq
            ExprUnify.env_of_Subst 

            SymIL.bedrock_ext SymIL.bedrock_types SymIL.BedrockEvaluator.types

            EquivDec.equiv_dec
            Compare_dec.lt_eq_lt_dec Peano_dec.eq_nat_dec EquivDec.nat_eq_eqdec
            
            Logic.eq_sym eq_sym f_equal
            eq_rec_r eq_rect eq_rec
            nat_rec nat_rect
            sumbool_rec sumbool_rect


            
            projT1 fst snd
          ]; 
        try reflexivity*))
  end.

(*
Require Unfolder.
Module U := Unfolder.Make BedrockHeap ST.
*)

Definition smem_read stn := SepIL.ST.HT.smem_get_word (IL.implode stn).
Definition smem_write stn := SepIL.ST.HT.smem_set_word (IL.explode stn).
