Require Import Coq.Lists.List.
Require Import Coq.Arith.PeanoNat.
Require Import Coq.NArith.BinNat.
Require Import Hafnium.AbstractModel.
Require Import Hafnium.Concrete.Datatypes.
Require Import Hafnium.Concrete.Notations.
Require Import Hafnium.Concrete.Assumptions.Addr.
Require Import Hafnium.Concrete.Assumptions.ArchMM.
Require Import Hafnium.Concrete.Assumptions.Constants.
Require Import Hafnium.Concrete.Assumptions.Datatypes.
Require Import Hafnium.Concrete.Assumptions.Mpool.
Require Import Hafnium.Concrete.Assumptions.PageTables.
Require Import Hafnium.Concrete.MM.Datatypes.

(*** This file defines the state type for the concrete model and relates it to
     the abstract state. ***)

Record vm :=
  {
    vm_ptable : mm_ptable;
    vm_id : nat;
  }.

Definition vm_root_ptable (v : vm) : ptable_pointer :=
  ptable_pointer_from_address v.(vm_ptable).(root).

(* starting parameters -- don't change *)
Class concrete_params :=
  {
    vms : list vm;
    hafnium_root_ptable : ptable_pointer;
  }.

Record concrete_state :=
  {
    (* representation of the state of page tables in memory *)
    ptable_lookup : ptable_pointer -> mm_page_table;
    api_page_pool : mpool;
  }.

Definition is_valid {cp : concrete_params} (s : concrete_state) : Prop :=
  (* Possible constraints:
        - Block PTEs have the valid bit set
        - page tables have a constant size
        - page table indices are always below page table size
        - vm_id corresponds to a VM's place in the vms list
   *)
  True.

Definition vm_find {cp : concrete_params} (vid : nat) : option vm :=
  find (fun v => (v.(vm_id) =? vid)) vms.

Definition vm_page_valid (s : concrete_state) (v : vm) (a : paddr_t) : Prop :=
  exists e : pte_t,
    page_lookup s.(ptable_lookup) v.(vm_root_ptable) a.(pa_addr) = Some e
    /\ forall lvl, arch_mm_pte_is_valid e lvl = true.

Definition haf_page_valid
           {cp : concrete_params} (s : concrete_state) (a : paddr_t) : Prop :=
  exists e : pte_t,
    page_lookup s.(ptable_lookup) hafnium_root_ptable a.(pa_addr) = Some e
    /\ forall lvl, arch_mm_pte_is_valid e lvl = true.

Local Definition owned (mode : mode_t) : Prop :=
  (mode & MM_MODE_UNOWNED)%N = false.

Definition vm_page_owned (s : concrete_state) (v : vm) (a : paddr_t) : Prop :=
  exists e : pte_t,
    page_lookup s.(ptable_lookup) v.(vm_root_ptable) a.(pa_addr) = Some e
    /\ forall lvl,
      owned (arch_mm_stage2_attrs_to_mode (arch_mm_pte_attrs e lvl)).

Definition haf_page_owned
           {cp : concrete_params} (s : concrete_state) (a : paddr_t) : Prop :=
  exists e : pte_t,
    page_lookup s.(ptable_lookup) hafnium_root_ptable a.(pa_addr) = Some e
    /\ forall lvl,
      owned (arch_mm_stage1_attrs_to_mode (arch_mm_pte_attrs e lvl)).

Arguments owned_by {_} {_} _.
Arguments accessible_by {_} {_} _.
Definition represents
           {cp : concrete_params}
           (abst : @abstract_state paddr_t nat)
           (conc : concrete_state) : Prop :=
  is_valid conc
  /\ (forall (vid : nat) (a : paddr_t),
      In (inl vid) (abst.(accessible_by) a) <->
         (exists v : vm,
             vm_find vid = Some v /\ conc.(vm_page_valid) v a))
  /\ (forall (a : paddr_t),
         In (inr hid) (abst.(accessible_by) a) <-> conc.(haf_page_valid) a)
  /\ (forall (vid : nat) (a : paddr_t),
         abst.(owned_by) a = inl vid <->
         (exists v : vm,
             vm_find vid = Some v /\ conc.(vm_page_owned) v a))
  /\ (forall (a : paddr_t),
         abst.(owned_by) a = inr hid <-> conc.(haf_page_owned) a)
.

Definition abstract_state_equiv
           (s1 s2 : @abstract_state paddr_t nat) : Prop :=
  (forall a, s1.(owned_by) a = s2.(owned_by) a)
  /\ (forall e a,
         In e (s1.(accessible_by) a) <-> In e (s2.(accessible_by) a)).

(* for every API function, we need to prove that if the concrete state (is
   itself valid and) represents a valid abstract state before the call, then
   the concrete state after the call (is also valid and) represents a valid
   abstract state *)