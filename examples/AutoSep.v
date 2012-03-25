Require Import Bedrock.
Export Bedrock.

(** * Specialize the library proof automation to some parameters useful for basic examples. *)

Import SymIL.BedrockEvaluator.
Require Import Bedrock.sep.PtsTo2.

Ltac unfolder H :=
  cbv delta [
    ptsto_evaluator CORRECTNESS READER WRITER DEMO.expr_equal DEMO.types
    DEMO.ptsto32_ssig DEMO.ptrIndex DEMO.wordIndex
    SymEval.fold_args SymEval.fold_args_update
  ] in H;
  sym_evaluator H.

Ltac the_cancel_simplifier :=
  cbv beta iota zeta delta 
    [ SepTac.SEP.CancelSep projT1
      SepTac.SEP.hash SepTac.SEP.hash' SepTac.SEP.sepCancel

      SepExpr.FM.fold

      Provers.eq_summary Provers.eq_summarize Provers.eq_prove 
      Provers.transitivityEqProverRec

      ExprUnify.Subst

      SymIL.bedrock_types SymIL.bedrock_ext
      app map fold_right nth_error value error

      fst snd

      SepExpr.impures SepTac.SEP.star_SHeap SepExpr.FM.empty SepTac.SEP.liftSHeap
      SepTac.SEP.sheapSubstU ExprUnify.empty_Subst

      SepExpr.pures SepExpr.impures SepExpr.other

      SepTac.SEP.exists_subst ExprUnify.env_of_Subst

      SepTac.SEP.multimap_join SepExpr.FM.add SepExpr.FM.find SepExpr.FM.map
      SepExpr.SDomain SepExpr.SDenotation

      SepTac.SEP.unify_remove_all SepTac.SEP.unify_remove

      SepTac.SEP.unifyArgs
      ExprUnify.fold_left_2_opt
      Compare_dec.lt_eq_lt_dec nat_rec nat_rect 

      ExprUnify.exprUnify SepTac.SEP.substV length ExprUnify.Subst_lookup ExprUnify.Subst_replace
      Expr.liftExpr Expr.exprSubstU
      Peano_dec.eq_nat_dec EquivDec.equiv_dec
      Expr.EqDec_tvar
      Expr.tvar_rec Expr.tvar_rect
      sumbool_rec sumbool_rect
      eq_rec_r eq_rect eq_rec f_equal eq_sym
      ExprUnify.get_Eq
      Expr.Eq
      EquivDec.nat_eq_eqdec
      Provers.inSameGroup Provers.eqD_seq Provers.transitivityEqProver

      Provers.groupsOf
      Provers.addEquality
      Provers.in_seq_dec
      Expr.typeof 
      Expr.expr_seq_dec
      Expr.tvarD
      Expr.tvar_val_sdec 
      Provers.groupWith
      Expr.Range Expr.Domain Expr.Denotation
      Expr.well_typed 
      Expr.all2

      SepTac.SEP.forallEach
      SepTac.SEP.sheapD SepTac.SEP.sexprD
      SepTac.SEP.starred SepTac.SEP.himp
      Expr.Impl

      Expr.is_well_typed Expr.exprD Expr.applyD

      tvWord
    ].

Ltac vcgen :=
  structured_auto; autorewrite with sepFormula in *; simpl in *;
    unfold starB, hvarB, hpropB in *; fold hprop in *.

Ltac evaluate := sym_eval ltac:isConst idtac unfolder (CORRECTNESS ptsto_evaluator) tt tt tt.

Ltac cancel := sep_canceler ltac:(isConst) (@Provers.transitivityEqProverRec) the_cancel_simplifier tt.

Ltac unf := unfold substH.
Ltac reduce := Programming.reduce unf.
Ltac ho := Programming.ho unf; reduce.
Ltac step := match goal with
               | [ |- _ _ = Some _ ] => solve [ eauto ]
               | [ |- interp _ (![ _ ] _) ] => cancel
               | [ |- interp _ (![ _ ] _ ---> ![ _ ] _)%PropX ] => cancel
               | _ => ho
             end.
Ltac descend := Programming.descend; reduce.

Ltac sep := evaluate; descend; repeat (step; descend).
