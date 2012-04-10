Require Import Bool EqdepClass List.

Require Import Heaps Reflect.
Require Import Expr ExprUnify.
Require Import SepExpr.
Require Import Prover.
Require Import Env.

Set Implicit Arguments.

Require NatMap.

Module FM := NatMap.IntMap.

Fixpoint allb A (P : A -> bool) (ls : list A) : bool :=
  match ls with
    | nil => true
    | x :: ls' => P x && allb P ls'
  end.

Module Make (B : Heap) (ST : SepTheoryX.SepTheoryXType B).

  Module SE := SepExpr(B)(ST).
  Import SE.

  Section env.
    Variable types : list type.
    Variable funcs : functions types.
    
    Variable pcType : tvar.
    Variable stateType : tvar.
    Variable stateMem : tvarD types stateType -> B.mem.

    Variable sfuncs : sfunctions types pcType stateType.

    (** * Some substitution functions *)

    (* [first] gives the offset to add to a variable to determine its corresponding unification variable, for substitution purposes. *)
    Fixpoint substExpr (offset : nat) (s : Subst types) (e : expr types) : expr types :=
      match e with
        | Expr.Const _ k => Expr.Const k
        | Var x => match Subst_lookup (x + offset) s with
                     | None => e
                     | Some e' => e'
                   end
        | UVar _ => e
        | Expr.Func f es => Expr.Func f (map (substExpr offset s) es)
        | Equal t e1 e2 => Equal t (substExpr offset s e1) (substExpr offset s e2)
      end.

    Fixpoint substSexpr (offset : nat) (s : Subst types) (se : sexpr types pcType stateType) : sexpr types pcType stateType :=
      match se with
        | Emp => se
        | Inj e => Inj (substExpr offset s e)
        | Star se1 se2 => Star (substSexpr offset s se1) (substSexpr offset s se2)
        | Exists t se1 => Exists t (substSexpr offset s se1)
        | Func f es => Func f (map (substExpr offset s) es)
        | Const _ => se
      end.


    (** The type of one unfolding lemma *)
    Record lemma := {
      Foralls : variables;
      (* The lemma statement begins with this sequence of [forall] quantifiers over these types. *)
      Hyps : list (expr types);
      (* Next, we have this sequence of pure hypotheses. *)
      Lhs : sexpr types pcType stateType;
      Rhs : sexpr types pcType stateType
      (* Finally, we have this separation implication, with lefthand and righthand sides. *)
    }.

    (** Helper function to add a sequence of implications in front of a [Prop] *)

    Definition hypD (H : expr types) (env : env types) : Prop :=
      match exprD funcs nil env H tvProp with
        | None => False
        | Some P => P
      end.

    Fixpoint implyEach (Hs : list (expr types)) (env : env types) (P : Prop) : Prop :=
      match Hs with
        | nil => P
        | H :: Hs' => hypD H env -> implyEach Hs' env P
      end.

    (** The meaning of a lemma statement *)

    (* Redefine to use the opposite quantifier order *)
    Fixpoint forallEachR (ls : variables) : (env types -> Prop) -> Prop :=
      match ls with
        | nil => fun cc => cc nil
        | a :: b => fun cc =>
          forallEachR b (fun r => forall x : tvarD types a, cc (existT _ a x :: r))
      end.

    Definition lemmaD (lem : lemma) : Prop :=
      forallEachR (Foralls lem) (fun env =>
        implyEach (Hyps lem) env
        (forall specs, himp funcs sfuncs nil nil env specs (Lhs lem) (Rhs lem))).

    (** Preprocessed databases of hints *)

    Definition hintSide := list lemma.
    (* A complete set of unfolding hints of a single sidedness (see below) *)

    Definition hintSideD := Forall lemmaD.

    Record hintsPayload := {
      Forward : hintSide;
      (* Apply on the lefthand side of an implication *)
      Backward : hintSide 
      (* Apply on the righthand side *)
(*
      Prover : ProverT types
      (* Prover for pure hypotheses of lemmas *)
*)
    }.

    Definition default_hintsPayload : hintsPayload := 
    {| Forward := nil
     ; Backward := nil
     |}.

    Definition composite_hintsPayload (l r : hintsPayload) : hintsPayload :=
      {| Forward := Forward l ++ Forward r
       ; Backward := Backward l ++ Backward r
       |}.

    Record hintsSoundness (Payload : hintsPayload) : Prop := {
      ForwardOk : hintSideD (Forward Payload);
      BackwardOk : hintSideD (Backward Payload)
    }.
    
    Theorem hintsSoundness_default : hintsSoundness default_hintsPayload.
    Proof.
      econstructor; constructor.
    Qed.
    
    Require Provers. 
    Theorem hintsSoundness_composite l r (L : hintsSoundness l) (R : hintsSoundness r) 
      : hintsSoundness (composite_hintsPayload l r).
    Proof.
      econstructor; simpl; eapply Provers.Forall_app; solve [ eapply ForwardOk; auto | eapply BackwardOk; auto ].
    Qed.

    (** Applying up to a single hint to a hashed separation formula *)

    Definition fmFind A B (f : nat -> A -> option B) (m : FM.t A) : option B :=
      FM.fold (fun k v res =>
        match res with
          | Some _ => res
          | None => f k v
        end) m None.

    Fixpoint find A B (f : A -> option B) (ls : list A) : option B :=
      match ls with
        | nil => None
        | x :: ls' => match f x with
                        | None => find f ls'
                        | v => v
                      end
      end.

    Fixpoint findWithRest' A B (f : A -> list A -> option B) (ls acc : list A) : option B :=
      match ls with
        | nil => None
        | x :: ls' => match f x (rev_append acc ls') with
                        | None => findWithRest' f ls' (x :: acc)
                        | v => v
                      end
      end.

    Definition findWithRest A B (f : A -> list A -> option B) (ls : list A) : option B :=
      findWithRest' f ls nil.

    (* As we iterate through unfolding, we modify this sort of state. *)
    Record unfoldingState := {
      Vars : variables;
      UVars : variables;
      Heap : SHeap types pcType stateType
    }.

    Section unfoldOne.
      Variable prover : ProverT types.
      (* This prover must discharge all pure obligations of an unfolding lemma, if it is to be applied. *)
      Variable facts : Facts prover.

      Variable hs : hintSide.
      (* Use these hints to unfold impure predicates. *)

      (* Returns [None] if no unfolding opportunities are found.
       * Otherwise, return state after one unfolding. *)
      Definition unfoldForward (s : unfoldingState) : option unfoldingState :=
        (* Iterate through all the entries for impure functions. *)
        fmFind (fun f =>
          (* Iterate through all the argument lists passed to the current function. *)
          findWithRest (fun args argss =>
            (* Iterate through all hints. *)
            find (fun h =>
              (* Check if the hint's head symbol matches the impure call we are considering. *)
              match Lhs h with
                | Func f' args' =>
                  if equiv_dec f' f then
                    let firstUvar := length (UVars s) in

                    (* We must tweak the arguments by substituting unification variables for [forall]-quantified variables from the lemma statement. *)
                    let args' := map (exprSubstU O (length (Foralls h)) firstUvar) args' in

                    (* Unify the respective function arguments. *)
                    match exprUnifyArgs args' args (empty_Subst _) (empty_Subst _) with
                      | None => None
                      | Some (subs, _) =>
                        (* Now we must make sure all of the lemma's pure obligations are provable. *)
                        if allb (Prove prover facts) (map (substExpr firstUvar subs) (Hyps h)) then
                          (* Remove the current call from the state, as we are about to replace it with a simplified set of pieces. *)
                          let impures' := FM.add f argss (impures (Heap s)) in
                          let sh := {| impures := impures';
                            pures := pures (Heap s);
                            other := other (Heap s) |} in

                          (* Time to hash the hint RHS, to (among other things) get the new existential variables it creates. *)
                          let (exs, sh') := hash (substSexpr firstUvar subs (Rhs h)) in

                          (* The final result is obtained by joining the hint RHS with the original symbolic heap. *)
                            Some {| Vars := Vars s ++ exs;
                              UVars := UVars s;
                              Heap := star_SHeap sh sh' |}
                        else
                          None
                    end
                  else
                    None
                | _ => None
              end) hs)) (impures (Heap s)).

      Definition unfoldBackward (s : unfoldingState) : option unfoldingState :=
        (* Iterate through all the entries for impure functions. *)
        fmFind (fun f =>
          (* Iterate through all the argument lists passed to the current function. *)
          findWithRest (fun args argss =>
            (* Iterate through all hints. *)
            find (fun h =>
              (* Check if the hint's head symbol matches the impure call we are considering. *)
              match Rhs h with
                | Func f' args' =>
                  if equiv_dec f' f then
                    let firstUvar := length (UVars s) in

                    (* We must tweak the arguments by substituting unification variables for [forall]-quantified variables from the lemma statement. *)
                    let args' := map (exprSubstU O (length (Foralls h)) firstUvar) args' in

                    (* Unify the respective function arguments. *)
                    match exprUnifyArgs args' args (empty_Subst _) (empty_Subst _) with
                      | None => None
                      | Some (subs, _) =>
                        (* Now we must make sure all of the lemma's pure obligations are provable. *)
                        if allb (Prove prover facts) (map (substExpr firstUvar subs) (Hyps h)) then
                          (* Remove the current call from the state, as we are about to replace it with a simplified set of pieces. *)
                          let impures' := FM.add f argss (impures (Heap s)) in
                          let sh := {| impures := impures';
                            pures := pures (Heap s);
                            other := other (Heap s) |} in

                          (* Time to hash the hint LHS, to (among other things) get the new existential variables it creates. *)
                          let (exs, sh') := hash (substSexpr firstUvar subs (Lhs h)) in

                          (* Newly introduced variables must be replaced with unification variables. *)
                          let sh' := sheapSubstU O (length exs) (length (UVars s)) sh' in

                          (* The final result is obtained by joining the hint LHS with the original symbolic heap. *)
                          Some {| Vars := Vars s;
                            UVars := UVars s ++ exs;
                            Heap := star_SHeap sh sh' |}
                        else
                          None
                    end
                  else
                    None
                | _ => None
              end) hs)) (impures (Heap s)).
    End unfoldOne.

    Section unfolder.
      Variable hs : hintsPayload.
      Variable prover : ProverT types.

      (* Perform up to [bound] simplifications, based on [hs]. *)
      Fixpoint forward (bound : nat) (facts : Facts prover) (s : unfoldingState) : unfoldingState :=
        match bound with
          | O => s
          | S bound' =>
            match unfoldForward prover facts (Forward hs) s with
              | None => s
              | Some s' => forward bound' facts s'
            end
        end.

      Fixpoint backward (bound : nat) (facts : Facts prover) (s : unfoldingState) : unfoldingState :=
        match bound with
          | O => s
          | S bound' =>
            match unfoldBackward prover facts(Backward hs) s with
              | None => s
              | Some s' => backward bound' facts s'
            end
        end.

      (* Extended function environments, based on those symbols appearing in a goal but not the hint database. *)
      Variable funcs' : functions types.
      Variable sfuncs' : sfunctions types pcType stateType.

      Hypothesis hsOk : hintsSoundness hs.

      (* This soundness statement is clearly unsound, but I'll start with it to enable testing. *)
      Theorem unfolderOk : forall bound P Q (PC : ProverT_correct prover funcs'),
        (let (exsP, shP) := hash P in
         let (exsQ, shQ) := hash Q in
         let summ := Summarize prover (pures shP) in
         let sP := forward bound summ {| Vars := exsP;
           UVars := nil;
           Heap := shP |} in
         let shQ := sheapSubstU O (length exsQ) O shQ in
         let sQ := backward bound summ {| Vars := Vars sP;
           UVars := exsQ;
           Heap := shQ |} in
         forallEach (Vars sP) (fun alls =>
           exists_subst funcs' nil alls (env_of_Subst (empty_Subst _) (UVars sQ) 0) (fun exsQ =>
             forall cs, ST.himp cs (sexprD funcs' sfuncs' nil alls (sheapD (Heap sP)))
               (sexprD funcs' sfuncs' exsQ nil (sheapD (Heap sQ))))))
        -> forall cs, ST.himp cs (sexprD funcs' sfuncs' nil nil P) (sexprD funcs' sfuncs' nil nil Q).
      Admitted.
    End unfolder.
  End env.

  (** Package hints together with their environment/parameters. *)
  Record hints := {
    Types : Repr type;
    Functions : forall ts, Repr (signature (repr Types ts));
    PcType : tvar;
    StateType : tvar;
    SFunctions : forall ts, Repr (ssignature (repr Types ts) PcType StateType);
    Hints : forall ts, hintsPayload (repr Types ts) PcType StateType;
    HintsOk : forall ts fs ps, hintsSoundness (repr (Functions ts) fs) (repr (SFunctions ts) ps) (Hints ts)
  }.

  (** * Reflecting hints *)

  (* This tactic processes the part of a lemma statement after the quantifiers. *)
  Ltac collectTypes_hint' isConst P types k :=
    match P with
      | fun x => @?H x -> @?P x =>
        let types := collectTypes_expr ltac:(isConst) H types in
          collectTypes_hint' ltac:(isConst) P types k
      | fun x => forall cs, @ST.himp ?pcT ?stT cs (@?L x) (@?R x) =>
        collectTypes_sexpr ltac:(isConst) L types ltac:(fun types =>
          collectTypes_sexpr ltac:(isConst) R types k)
      | fun x => _ (@?L x) (@?R x) =>
        collectTypes_sexpr ltac:(isConst) L types ltac:(fun types =>
            collectTypes_sexpr ltac:(isConst) R types ltac:(fun types =>
                k types))
    end.

  (* This tactic adds quantifier processing. *)
  Ltac collectTypes_hint isConst P types k :=
    match P with
      | fun xs : ?T => forall x : ?T', @?f xs x =>
        match T' with
          | PropX.codeSpec _ _ => fail 1
          | _ => match type of T' with
                   | Prop => fail 1
                   | _ => let P := eval simpl in (fun x : VarType (T * T') =>
                     f (@openUp _ T (@fst _ _) x) (@openUp _ T' (@snd _ _) x)) in
                   let types := cons_uniq T' types in
                     collectTypes_hint ltac:(isConst) P types k
                 end
        end
      | _ => collectTypes_hint' ltac:(isConst) P types k
    end.

  (* Finally, this tactic adds a loop over all hints. *)
  Ltac collectTypes_hints unfoldTac isConst Ps types k :=
    match Ps with
      | tt => k types
      | (?P1, ?P2) =>
        collectTypes_hints unfoldTac ltac:(isConst) P1 types ltac:(fun types =>
          collectTypes_hints unfoldTac ltac:(isConst) P2 types k)
      | _ =>
        let T := type of Ps in
        let T := unfoldTac T in
          collectTypes_hint ltac:(isConst) (fun _ : VarType unit => T) types k
    end.

  (* Now we repeat this sequence of tactics for reflection itself. *)

  Ltac reify_hint' pcType stateType isConst P types funcs sfuncs vars k :=
    match P with
      | fun x => @?H x -> @?P x =>
        reify_expr isConst H types funcs (@nil tvar) vars ltac:(fun _ funcs H =>
          reify_hint' pcType stateType isConst P types funcs sfuncs vars ltac:(fun funcs sfuncs P =>
            let lem := eval simpl in (Build_lemma (types := types) (pcType := pcType) (stateType := stateType)
              vars (H :: Hyps P) (Lhs P) (Rhs P)) in
            k funcs sfuncs lem))
      | fun x => forall cs, @ST.himp _ _ cs (@?L x) (@?R x) =>
        reify_sexpr isConst L types funcs pcType stateType sfuncs (@nil tvar) vars ltac:(fun _uvars funcs sfuncs L =>
          reify_sexpr isConst R types funcs pcType stateType sfuncs (@nil tvar) vars ltac:(fun _uvars funcs sfuncs R =>
            let lem := constr:(Build_lemma (types := types) (pcType := pcType) (stateType := stateType)
              vars nil L R) in
            k funcs sfuncs lem))
      | fun x => _ (@?L x) (@?R x) =>
        reify_sexpr isConst L types funcs pcType stateType sfuncs (@nil tvar) vars ltac:(fun _ funcs sfuncs L =>
          reify_sexpr isConst R types funcs pcType stateType sfuncs (@nil tvar) vars ltac:(fun _ funcs sfuncs R =>
            let lem := constr:(Build_lemma (types := types) (pcType := pcType) (stateType := stateType)
              vars nil L R) in
            k funcs sfuncs lem))
    end.

  Ltac reify_hint pcType stateType isConst P types funcs sfuncs vars k :=
    match P with
      | fun xs : ?T => forall x : ?T', @?f xs x =>
        match T' with
          | PropX.codeSpec _ _ => fail 1
          | _ => match type of T' with
                   | Prop => fail 1
                   | _ =>
                     let P := eval simpl in (fun x : VarType (T' * T) =>
                       f (@openUp _ T (@snd _ _) x) (@openUp _ T' (@fst _ _) x)) in
                     let T' := reflectType types T' in
                     reify_hint pcType stateType isConst P types funcs sfuncs (T' :: vars) k
                   | _ => fail 3
                 end
          | _ => fail 2
        end
      | _ => reify_hint' pcType stateType isConst P types funcs sfuncs vars k
    end.

  Ltac reify_hints unfoldTac pcType stateType isConst Ps types funcs sfuncs k :=
    match Ps with
      | tt => k funcs sfuncs (@nil (lemma types pcType stateType)) || fail 2
      | (?P1, ?P2) =>
        reify_hints unfoldTac pcType stateType isConst P1 types funcs sfuncs ltac:(fun funcs sfuncs P1 =>
          reify_hints unfoldTac pcType stateType isConst P2 types funcs sfuncs ltac:(fun funcs sfuncs P2 =>
            k funcs sfuncs (P1 ++ P2)))
        || fail 2
      | _ =>
        let T := type of Ps in
        let T := unfoldTac T in
          reify_hint pcType stateType isConst (fun _ : VarType unit => T) types funcs sfuncs (@nil tvar) ltac:(fun funcs sfuncs P =>
            k funcs sfuncs (P :: nil))
    end.

  Lemma Forall_app : forall A (P : A -> Prop) ls1 ls2,
    Forall P ls1
    -> Forall P ls2
    -> Forall P (ls1 ++ ls2).
    induction 1; simpl; intuition.
  Qed.

  (* Build proofs of combined lemma statements *)
  Ltac prove Ps :=
    match Ps with
      | tt => constructor
      | (?P1, ?P2) => 
           (apply Forall_app; [ prove P1 | prove P2 ])
        || (constructor; [ exact P1 | prove P2 ])
      | _ => constructor; [ exact Ps | constructor ]
    end.


  (* Unfold definitions in a list of types *)
  Ltac unfoldTypes types :=
    match eval hnf in types with
      | nil => types
      | ?T :: ?types =>
        let T := eval hnf in T in
          let types := unfoldTypes types in
            constr:(T :: types)
    end.

  (* Main entry point tactic, to generate a hint database *)
Ltac lift_signature_over_repr s rp :=
  let d := eval simpl Domain in (Domain s) in
  let r := eval simpl Range in (Range s) in
  let den := eval simpl Denotation in (Denotation s) in
  constr:(fun ts' => @Sig (repr rp ts') d r den).

Ltac lift_signatures_over_repr fs rp :=
  match eval hnf in fs with
    | nil => constr:(fun ts' => @nil (signature (repr rp ts')))
    | ?f :: ?fs => 
      let f := lift_signature_over_repr f rp in
      let fs := lift_signatures_over_repr fs rp in
      constr:(fun ts' => (f ts') :: (fs ts'))
  end.

Ltac lift_ssignature_over_repr s rp pc st :=
  let d := eval simpl SDomain in (SDomain s) in
  let den := eval simpl SDenotation in (SDenotation s) in
  constr:(fun ts' => @SSig (repr rp ts') pc st d den).

Ltac lift_ssignatures_over_repr fs rp pc st :=
  match eval hnf in fs with
    | nil => constr:(fun ts' => @nil (ssignature (repr rp ts') pc st))
    | ?f :: ?fs => 
      let f := lift_ssignature_over_repr f rp pc st in
      let fs := lift_ssignatures_over_repr fs rp pc st in
      constr:(fun ts' => (f ts') :: (fs ts'))
  end.

Ltac lift_expr_over_repr e rp :=
  match eval hnf in e with
    | @Expr.Const _ ?t ?v => constr:(fun ts => @Expr.Const (repr rp ts) t v)
    | Expr.Var ?v => constr:(fun ts => @Expr.Var (repr rp ts) v)
    | Expr.UVar ?v => constr:(fun ts => @Expr.UVar (repr rp ts) v)
    | Expr.Func ?f ?args =>
      let args := lift_exprs_over_repr args rp in
      constr:(fun ts => @Expr.Func (repr rp ts) f (args ts))
    | Expr.Equal ?t ?l ?r =>
      let l := lift_expr_over_repr l rp in
      let r := lift_expr_over_repr r rp in
      constr:(fun ts => @Expr.Equal (repr rp ts) t (l ts) (r ts))
  end
with lift_exprs_over_repr es rp :=
  match eval hnf in es with
    | nil => constr:(fun ts => @nil (expr (repr rp ts)))
    | ?e :: ?es =>
      let e := lift_expr_over_repr e rp in
      let es := lift_exprs_over_repr es rp in
      constr:(fun ts => e ts :: es ts)
  end.

Ltac lift_sexpr_over_repr e rp pc st :=
  match eval hnf in e with
    | Emp => constr:(fun ts => @MkEmp (repr rp ts) pc st)
    | Inj ?e => 
      let e := lift_expr_over_repr e rp in
      constr:(fun ts => @MkInj (repr rp ts) pc st (e ts))
    | Star ?l ?r =>
      let l := lift_sexpr_over_repr l rp pc st in
      let r := lift_sexpr_over_repr r rp pc st in
      constr:(fun ts => @MkStar (repr rp ts) pc st (l ts) (r ts))
    | Exists ?t ?e =>
      let e := lift_sexpr_over_repr e rp pc st in
      constr:(fun ts => @MkExists (repr rp ts) pc st t (e ts))
    | Func ?f ?args => 
      let args := lift_exprs_over_repr args rp in
      constr:(fun ts => @MkFunc (repr rp ts) pc st f (args ts))
    | Const ?b => constr:(fun ts => @MkConst (repr rp ts) pc st b)
  end.

Ltac lift_lemma_over_repr lm rp pc st :=
  match eval hnf in lm with
    | {| Foralls := ?f
       ; Hyps := ?h
       ; Lhs := ?l
       ; Rhs := ?r
       |} => 
    let h := lift_exprs_over_repr h rp in
    let l := lift_sexpr_over_repr l rp pc st in
    let r := lift_sexpr_over_repr r rp pc st in
    constr:(fun ts => {| Foralls := f
                       ; Hyps := h ts
                       ; Lhs := l ts
                       ; Rhs := r ts
                       |})
  end.
Ltac lift_lemmas_over_repr lms rp pc st :=
  match lms with
    | nil => constr:(fun ts => @nil (lemma (repr rp ts) pc st))
    | ?lml ++ ?lmr =>
      let lml := lift_lemmas_over_repr lml rp pc st in
      let lmr := lift_lemmas_over_repr lmr rp pc st in
      constr:(fun ts => lml ts ++ lmr ts)
    | ?lm :: ?lms =>
      let lm := lift_lemma_over_repr lm rp pc st in
      let lms := lift_lemmas_over_repr lms rp pc st in
      constr:(fun ts => lm ts :: lms ts)
  end.

  
  Ltac prepareHints unfoldTac pcType stateType isConst types fwd bwd ret :=
    let types := unfoldTypes types in
    collectTypes_hints unfoldTac isConst fwd (@nil Type) ltac:(fun rt =>
      collectTypes_hints unfoldTac isConst bwd rt ltac:(fun rt =>
        let rt := constr:((pcType : Type) :: (stateType : Type) :: rt) in
        let types := extend_all_types rt types in
        let pcT := reflectType types pcType in
        let stateT := reflectType types stateType in
          (reify_hints unfoldTac pcT stateT isConst fwd types (@nil (signature types)) (@nil (@ssignature types pcT stateT)) ltac:(fun funcs sfuncs fwd' =>
            reify_hints unfoldTac pcT stateT isConst bwd types funcs sfuncs ltac:(fun funcs sfuncs bwd' =>
            let types_r := eval cbv beta iota zeta delta [ listToRepr ] in (listToRepr types EmptySet_type) in
            let types_rV := fresh "types" in
              (pose (types_rV := types_r) || fail 1000);
            let funcs_r := lift_signatures_over_repr funcs types_rV in 
            let funcs_r := eval cbv beta iota zeta delta [ listToRepr ] in (fun ts => listToRepr (funcs_r ts) (Default_signature (repr types_rV ts))) in
            let funcs_rV := fresh "funcs" in
            pose (funcs_rV := funcs_r) ;
            let preds_r := lift_ssignatures_over_repr sfuncs types_rV pcT stateT in
            let preds_r := eval cbv beta delta [ SE.SSig ] in preds_r in
            let preds_rV := fresh "preds" in
            let preds_r := eval cbv beta iota zeta delta [ listToRepr ] in (fun ts => listToRepr (preds_r ts) (Default_ssignature (repr types_rV ts) pcT stateT)) in
            pose (preds_rV := preds_r) ;
            let fwd' := lift_lemmas_over_repr fwd' types_rV pcT stateT in
            let bwd' := lift_lemmas_over_repr bwd' types_rV pcT stateT in
            let pf := fresh "fwd_pf" in
            assert (pf : forall ts fs ps, hintsSoundness (repr (funcs_rV ts) fs) (repr (preds_rV ts) ps) ({| Forward := fwd' ts ; Backward := bwd' ts |})) by 
              (constructor; [ prove fwd | prove bwd ]) ;
            let res := constr:(
              {| Types      := types_rV
               ; PcType     := pcT
               ; StateType  := stateT
               ; Functions  := funcs_rV
               ; SFunctions := preds_rV
               ; Hints      := fun ts => {| Forward := fwd' ts ; Backward := bwd' ts |}
               ; HintsOk    := pf
               |}) in ret res))))).

  (* Main entry point to simplify a goal *)
  Ltac unfolder isConst hs bound :=
    intros;
      let types := unfoldTypes (Types hs) in
      let funcs := eval simpl in (Functions hs) in
      let sfuncs := eval simpl in (SFunctions hs) in
      let pc := eval simpl in (PcType hs) in
      let state := eval simpl in (StateType hs) in
        match goal with
          | [ |- ST.himp _ ?P ?Q ] =>
            collectTypes_sexpr isConst P (@nil Type) ltac:(fun rt =>
              collectTypes_sexpr isConst Q rt ltac:(fun rt =>
                let types := extend_all_types rt types in
                  reify_sexpr isConst P types funcs pc state sfuncs (@nil type) (@nil type) ltac:(fun funcs sfuncs P =>
                    reify_sexpr isConst Q types funcs pc state sfuncs (@nil type) (@nil type) ltac:(fun funcs sfuncs Q =>
                      apply (unfolderOk (Hints hs) funcs sfuncs bound P Q)))))
      end.
(*
  Module TESTS.
    Section Tests.
    Variables pc state : Type.

    Variable f : nat -> ST.hprop pc state nil.
    Variable h : bool -> unit -> ST.hprop pc state nil.
    Variable g : bool -> nat -> nat -> nat.

    Ltac isConst e :=
      match e with
        | true => true
        | false => true
        | O => true
        | S ?e => isConst e
        | _ => false
      end.

    Definition nat_type := {|
      Impl := nat;
      Eq := fun x y => match equiv_dec x y with
                         | left pf => Some pf
                         | _ => None 
                       end
      |}.

    Definition bool_type := {|
      Impl := bool;
      Eq := fun x y => match equiv_dec x y with
                         | left pf => Some pf
                         | _ => None 
                       end
      |}.

    Definition unit_type := {|
      Impl := unit;
      Eq := fun x y => match equiv_dec x y with
                         | left pf => Some pf
                         | _ => None 
                       end
      |}.

    Definition types0 := nat_type :: bool_type :: unit_type :: nil.

    Fixpoint assumptionProver (types : list type) (Hs : list (expr types)) (P : expr types) :=
      match Hs with
        | nil => false
        | H :: Hs' => match expr_seq_dec H P with
                        | Some _ => true
                        | None => assumptionProver Hs' P
                      end
      end.

    Hypothesis Hemp : forall cs, ST.himp cs (ST.emp pc state) (ST.emp pc state).
    Hypothesis Hf : forall cs, ST.himp cs (f 0) (ST.emp _ _).
    Hypothesis Hh : forall cs, ST.himp cs (h true tt) (ST.star (h true tt) (f 13)).

    Hypothesis Hf0 : forall n cs, ST.himp cs (f n) (ST.emp _ _).
    Hypothesis Hh0 : forall b u cs, ST.himp cs (h b u) (ST.star (h (negb b) tt) (f 13)).

    Hypothesis Hf1 : forall n, n <> 0 -> forall cs, ST.himp cs (f n) (ST.emp _ _).
    Hypothesis Hh1 : forall b u, b = false -> u <> tt -> forall cs, ST.himp cs (h b u) (ST.star (h b tt) (f 13)).


    (** * Creating hint databases *)

    Ltac prepare := prepareHints ltac:(fun x => x) pc state isConst types0.

    Definition hints_emp : hints.
      prepare (Hemp, Hf) (Hemp, Hf, Hh) ltac:(fun x => refine x).
    Defined.

    Definition hints_tt : hints.
      prepare tt tt ltac:(fun x => refine x).
    Defined.
    End Tests.
  End TESTS.
*)

End Make.
