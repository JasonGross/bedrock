Require Import Bedrock.Platform.Cito.examples.ReturnZeroDriver Bedrock.AMD64_gas.

Module M.
  Definition heapSize := 1024.
End M.

Module E := Make(M).

Definition compiled := moduleS E.m1.
Unset Extraction AccessOpaque.  Recursive Extraction compiled.
