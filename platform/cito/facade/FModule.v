Set Implicit Arguments.

Require Import StringMap.
Import StringMap.

Require Import Facade.

Local Notation FunCore := OperationalSpec.

Definition is_syntactic_wellformed (f : FunCore) := true.

Record FFunction :=
  {
    Core : FunCore;
    syntactic_wellformed : is_syntactic_wellformed Core = true
  }.
    
Coercion Core : FFunction >-> OperationalSpec.

Section ADTValue.

  Variable ADTValue : Type.

  Notation AxiomaticSpec := (@AxiomaticSpec ADTValue).

  Record FModule := 
    {
      Imports : StringMap.t AxiomaticSpec;
      (* Exports : StringMap.t AxiomaticSpec; *)
      Functions : StringMap.t FFunction
    }.

End ADTValue.