Set Implicit Arguments.

Require Import Bedrock.Platform.Cito.ADT.
Require Bedrock.Platform.Cito.Inv.
Require Bedrock.Platform.Cito.WordMap.
Require Coq.FSets.FMapFacts.
Require Bedrock.Platform.Cito.RepInv.
Require Bedrock.Platform.Cito.LayoutHintsUtil.
Require Bedrock.Platform.Cito.SemanticsFacts5.

Module Make (Import E : ADT).

  Import Bedrock.Platform.Cito.Inv.
  Module Import InvMake := Make E.
  Import Semantics.
  Import SemanticsMake.
  Import Bedrock.Platform.Cito.WordMap.
  Import Coq.FSets.FMapFacts.
  Module Properties := Properties WordMap.
  Module Facts := Facts WordMap.

  Import Bedrock.Platform.Cito.RepInv.

  Module Make(R : RepInv E).
    Module Import Inner := InvMake.Make(R).

    Import Bedrock.Platform.Cito.LayoutHintsUtil.
    Import Bedrock.Platform.Cito.SemanticsFacts5.

    Lemma is_heap_Equal : forall h h',
      WordMap.Equal h h'
      -> is_heap h ===> is_heap h'.
      intros; apply starL_permute; unfold heap_elements; intuition.
      apply NoDupA_NoDup; apply WordMap.elements_3w.
      apply NoDupA_NoDup; apply WordMap.elements_3w.

      apply In_InA' in H0.
      apply InA_In.
      apply Properties.F.elements_mapsto_iff in H0.
      apply Properties.F.elements_mapsto_iff.
      eapply Properties.F.Equal_mapsto_iff; eauto.
      apply Properties.F.Equal_sym; auto.

      apply In_InA' in H0.
      apply InA_In.
      apply Properties.F.elements_mapsto_iff in H0.
      apply Properties.F.elements_mapsto_iff.
      eapply Properties.F.Equal_mapsto_iff; eauto.
    Qed.

  End Make.

End Make.
