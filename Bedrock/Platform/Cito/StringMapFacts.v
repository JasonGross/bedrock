Set Implicit Arguments.

Require Import StringMap.
Module K := String_as_UDT.
Module M := StringMap.
Require Import FMapFacts.
Include (Properties M).
Include (Facts M).
Require Import FMapFacts1.
Module bug_4066_workaround_1 := WFacts_fun K M.
Include bug_4066_workaround_1.
Module bug_4066_workaround_2 := UWFacts_fun K M.
Include bug_4066_workaround_2.
Require Import FMapFacts2.
Module bug_4066_workaround_3 := UWFacts_fun K M.
Include bug_4066_workaround_3.
