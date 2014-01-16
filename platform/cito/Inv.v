Require Import AutoSep.

Set Implicit Arguments.

Require Import Layout.
Require Import Bags.
Require Import Semantics.

Definition is_heap (h : Heap) : HProp := starL (fun p => layout (fst p) (snd p)) (heap_elements h).

Definition empty_vs : vals := fun _ => $0.

Section TopSection.

  Definition has_extra_stack sp offset e_stack e_stack_real :=
    ((sp ^+ $4) =*> $(e_stack) *
     (sp ^+ $8 ^+ $(4 * offset)) =?> e_stack_real)%Sep.

  Definition is_state sp rp e_stack e_stack_real vars (v : State) temps : HProp :=
    (
     locals vars (fst v) 0 (sp ^+ $8) *
     array temps (sp ^+ $8 ^+ $(4 * length vars)) *
     is_heap (snd v) *
     sp =*> rp *
     has_extra_stack sp (length vars + length temps) e_stack e_stack_real
    )%Sep.

  Require Import Malloc.
  Require Import Safe.
  Require Import Basics.

  Definition layout_option addr ret : HProp :=
    match ret with
      | None  => ([| True |])%Sep
      | Some a => layout addr a
    end.

  Fixpoint make_triples pairs outs :=
    match pairs, outs with
      | p :: ps, o :: os => {| Word := fst p; ADTIn := snd p; ADTOut := o |} :: make_triples ps os
      | _, _ => nil
    end.

  Definition store_pair heap (p : W * ArgIn) :=
    match snd p with
      | inl _ => heap
      | inr a => heap_upd heap (fst p) a
    end.

  Fixpoint make_heap pairs := fold_left store_pair pairs heap_empty.

  Open Scope type.

  Require Import ConvertLabel.
  Definition internal_spec G fs spec st : propX _ _ (settings * smem :: G) :=
    (Ex v, Ex rp, Ex e_stack,
     ![^[is_state st#Sp rp e_stack e_stack (ArgVars spec) v nil * mallocHeap 0] * #0] st /\
     let stn := fst st in
     let env := (from_bedrock_label_map (Labels stn), fs stn) in
     [| Safe env (Body spec) v |] /\
     (st#Rp, stn) 
       @@@ (
         st' ~> Ex v', Ex rp', 
         (* the callee needn't have the right extra stack size recorded in the end, but the extra stack should be there *)
         Ex e_stack',
         ![^[ is_state st'#Sp rp' e_stack' e_stack (ArgVars spec) v' nil * mallocHeap 0] * #1] st' /\
         [| exists vs', 
            RunsTo env (Body spec) v (vs', snd v') /\ 
            st'#Rv = sel vs' (RetVar spec) /\
            st'#Sp = st#Sp |]))%PropX.

  Definition foreign_spec G spec st : propX _ _ (settings * smem :: G) :=
    (Ex pairs, Ex rp, Ex e_stack,
     let heap := make_heap pairs in
     ![^[is_state st#Sp rp e_stack e_stack nil (empty_vs, heap) (map fst pairs) * mallocHeap 0] * #0] st /\
     let stn := fst st in
     [| disjoint_ptrs pairs /\
        PreCond spec (map snd pairs) |] /\
     (st#Rp, stn) 
       @@@ (
         st' ~> Ex args', Ex addr, Ex ret, Ex rp', Ex outs,
         let t := decide_ret addr ret in
         let ret_w := fst t in
         let ret_a := snd t in
         let triples := make_triples pairs outs in
         let heap := fold_left store_out triples heap in
         (* the callee needn't have the right extra stack size recorded in the end, but the extra stack should be there *)
         Ex e_stack',
         ![^[is_state st#Sp rp' e_stack' e_stack nil (empty_vs, heap) args' * layout_option ret_w ret_a * mallocHeap 0] * #1] st' /\
         [| length outs = length pairs /\
            PostCond spec (map (fun x => (ADTIn x, ADTOut x)) triples) ret /\
            length args' = length triples /\
            st'#Rv = ret_w /\
            st'#Sp = st#Sp |]))%PropX.

  Definition cptr_AlX G (p : W) (stn : settings) a : propX _ _ G :=
    (ExX, 
     Cptr p #0 /\
     Al st : state, AlX : settings * smem,
     a (stn, st) ---> #1 (stn, st))%PropX.
    
  Definition funcs_ok stn (fs : settings -> W -> option Callee) : PropX W (settings * state) := 
    ((Al i, Al spec,
      [| fs stn i = Some (Internal spec) |] 
        ---> cptr_AlX i stn (internal_spec _ fs spec)) /\
     (Al i, Al spec, 
      [| fs stn i = Some (Foreign spec) |] 
        ---> cptr_AlX i stn (foreign_spec _ spec)))%PropX.

  Section vars.

    Variable vars : list string.
    
    Variable temp_size : nat.

    Definition inv_template rv_precond rv_postcond s : assert := 
      st ~> Ex fs, 
      let stn := fst st in
      funcs_ok stn fs /\
      ExX, Ex v, Ex temps, Ex rp, Ex e_stack,
      ![^[is_state st#Sp rp e_stack e_stack vars v temps * mallocHeap 0] * #0] st /\
      let env := (from_bedrock_label_map (Labels stn), fs stn) in
      [| Safe env s v /\
         length temps = temp_size /\
         rv_precond st#Rv v |] /\
      (rp, stn) 
        @@@ (
          st' ~> Ex v', Ex temps',
          ![^[is_state st'#Sp rp e_stack e_stack vars v' temps' * mallocHeap 0] * #1] st' /\
          [| RunsTo env s v v' /\
             length temps' = temp_size /\
             st'#Sp = st#Sp /\
             rv_postcond st'#Rv v' |]).

    Definition inv := inv_template (fun _ _ => True).
    
    End vars.

End TopSection.