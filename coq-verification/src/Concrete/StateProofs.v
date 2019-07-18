Require Import Coq.Arith.PeanoNat.
Require Import Coq.NArith.BinNat.
Require Import Coq.Lists.List.
Require Import Hafnium.AbstractModel.
Require Import Hafnium.Concrete.State.
Require Import Hafnium.Concrete.Datatypes.
Require Import Hafnium.Concrete.Notations.
Require Import Hafnium.Util.List.
Require Import Hafnium.Util.Tactics.
Require Import Hafnium.Concrete.Assumptions.Addr.
Require Import Hafnium.Concrete.Assumptions.ArchMM.
Require Import Hafnium.Concrete.Assumptions.Constants.
Require Import Hafnium.Concrete.Assumptions.Datatypes.
Require Import Hafnium.Concrete.Assumptions.Mpool.
Require Import Hafnium.Concrete.Assumptions.PageTables.
Require Import Hafnium.Concrete.MM.Datatypes.

(*** This file contains correctness proofs about the relationship between
     concrete and abstract states. ***)

Section Proofs.
  Context {ap : @abstract_state_parameters paddr_t nat}
          {cp : concrete_params}.

  (* if two concrete states are equivalent and an abstract state represents one
     of them, then it also represents the other. *)
  Lemma represents_proper abst conc conc' :
    (forall ptr, conc.(ptable_deref) ptr = conc'.(ptable_deref) ptr) ->
    (conc.(api_page_pool) = conc'.(api_page_pool)) ->
    represents abst conc ->
    represents abst conc'.
  Admitted.

  (* if two abstract states are equivalent and one represents a concrete state,
     then the other also represents that concrete state. *)
  Lemma represents_proper_abstr abst abst' conc :
    abstract_state_equiv abst abst' ->
    represents abst conc ->
    represents abst' conc.
  Admitted.

  (* if the new table is the same as the old, abstract state doesn't change *)
  Lemma reassign_pointer_noop_represents conc ptr t abst :
    conc.(ptable_deref) ptr = t ->
    represents abst conc <->
    represents abst (conc.(reassign_pointer) ptr t).
  Proof.
    repeat match goal with
           | _ => progress basics
           | _ => progress cbn [reassign_pointer ptable_deref]
           | |- _ <-> _ => split
           | _ => break_match
           | _ => solver
           | _ => eapply represents_proper;
                    [ | | solve[eauto] ]; eauto; [ ]
           end.
  Qed.

  Definition all_root_ptables : list mm_ptable :=
    hafnium_ptable :: map vm_ptable vms.

  Definition all_root_ptable_pointers : list ptable_pointer :=
    hafnium_root_tables ++ flat_map vm_root_tables vms.

  Fixpoint pointer_in_table'
             (deref : ptable_pointer -> mm_page_table) (ptr : ptable_pointer)
             (t : mm_page_table) (lvls_to_go : nat) : Prop :=
    match lvls_to_go with
    | 0 => False
    | S lvls_to_go' =>
      let lvl := 4 - lvls_to_go in
      Exists
        (fun i =>
           match get_entry t i with
           | Some pte =>
             if arch_mm_pte_is_table pte lvl
             then 
               let next_t_ptr :=
                   ptable_pointer_from_address (arch_mm_table_from_pte pte lvl) in
               if ptable_pointer_eq_dec ptr next_t_ptr
               then True
               else pointer_in_table' deref ptr (deref next_t_ptr) lvls_to_go'
             else False
           | None => False
           end)
        (seq 0 MM_PTE_PER_PAGE)
    end.

  Definition pointer_in_table
             (deref : ptable_pointer -> mm_page_table) (ptr : ptable_pointer)
             (t : mm_page_table) : Prop :=
    Forall (pointer_in_table' deref ptr t) (seq 0 4).

  Definition deref_noncircular (c : concrete_state) : Prop :=
    forall ptr,
      ~ pointer_in_table c.(ptable_deref) ptr (c.(ptable_deref) ptr).

  (* TODO : It's not clear that this definition is the correct approach. Consider
     other ways to keep track of the fact that page tables don't have circular
     references and don't use any locations in the freelist. *)
  Definition pointers_ok (c : concrete_state) (ppool : mpool) : Prop :=
    deref_noncircular c
    /\ (forall ptr,
           mpool_contains ppool ptr <->
           (forall ptr2, ~ pointer_in_table c.(ptable_deref) ptr (c.(ptable_deref) ptr2))).

  (* We haven't formalized anywhere that pointers don't repeat, so we return a
     list of all locations where the provided pointer exists even though we
     expect there is only one. *)
  Fixpoint index_sequences_to_pointer'' (ptable_deref : ptable_pointer -> mm_page_table)
           (ptr : ptable_pointer) (root : ptable_pointer) (lvls_to_go : nat)
    : list (list nat) :=
    match lvls_to_go with
    | 0 => nil
    | S lvls_to_go' =>
      let lvl := 4 - lvls_to_go in
      if ptable_pointer_eq_dec root ptr
      then cons nil nil
      else
        flat_map
          (fun index =>
             let ptable := ptable_deref root in
             match get_entry ptable index with
             | Some pte =>
               if arch_mm_pte_is_table pte lvl
               then
                 let next_root :=
                     ptable_pointer_from_address
                       (arch_mm_table_from_pte pte lvl) in
                 map
                   (cons index)
                   (index_sequences_to_pointer''
                      ptable_deref ptr next_root lvls_to_go')
               else nil
             | None => nil
             end)
          (seq 0 MM_PTE_PER_PAGE)
    end.
  Fixpoint index_sequences_to_pointer'
           (ptable_deref : ptable_pointer -> mm_page_table)
           (ptr : ptable_pointer) (root_index : nat)
           (root_ptrs : list ptable_pointer) : list (list nat) :=
    match root_ptrs with
    | nil => nil
    | cons root_ptr root_ptrs' =>
      (map (cons root_index)
           (index_sequences_to_pointer'' ptable_deref ptr root_ptr 4))
        ++
        index_sequences_to_pointer' ptable_deref ptr (S root_index) root_ptrs'
    end.
  Definition index_sequences_to_pointer
           (ptable_deref : ptable_pointer -> mm_page_table)
           (ptr : ptable_pointer) (root_ptable : mm_ptable) :=
    index_sequences_to_pointer'
      ptable_deref ptr 0 (ptr_from_va (va_from_pa root_ptable.(root))).

  Definition abstract_change_attrs (abst : abstract_state)
             (a : paddr_t) (e : entity_id) (owned valid : bool) :=
    let eq_dec := @entity_id_eq_dec _ Nat.eq_dec in
    {|
      accessible_by :=
        (fun a' =>
           let prev := abst.(accessible_by) a' in
           if paddr_t_eq_dec a a'
           then if valid
                then nodup eq_dec (e :: prev)
                else remove eq_dec e prev
          else prev);
      owned_by :=
        (fun a' =>
           let prev := abst.(owned_by) a' in
           if paddr_t_eq_dec a a'
           then if owned
                then e (* TODO: make the state with multiple owners representable (although still not valid) *)
                else inr hid (* TODO: make unowned memory representable (although still not valid) *)
           else prev)
    |}.

  (* given a sequence of page table indices, says whether the address is found
     under the same sequence of page table indexing *)
  Definition is_under_path (indices : list nat) (addr : uintpaddr_t) : bool :=
    forallb
      (fun '(lvl, i) => get_index lvl addr =? i)
      (combine (seq 0 4) indices).

  Definition addresses_under_pointer_in_range
             (deref : ptable_pointer -> mm_page_table)
             (ptr : ptable_pointer) (root_ptable : mm_ptable)
             (begin end_ : uintvaddr_t) : list paddr_t :=
    let vrange := map N.of_nat (seq (N.to_nat begin) (N.to_nat end_)) in
    let prange := map (fun va => pa_from_va (va_init va)) vrange in
    let paths := index_sequences_to_pointer deref ptr root_ptable in
    filter
      (fun a => existsb (fun p => is_under_path p (pa_addr a)) paths) prange.

  Definition abstract_reassign_pointer_for_entity
             (abst : abstract_state) (conc : concrete_state)
             (ptr : ptable_pointer) (owned valid : bool)
             (e : entity_id) (root_ptable : mm_ptable)
             (begin end_ : uintvaddr_t) : abstract_state :=
    fold_right
      (fun pa abst =>
         abstract_change_attrs abst pa e owned valid)
      abst
      (addresses_under_pointer_in_range
         conc.(ptable_deref) ptr root_ptable begin end_).

  (* Update the abstract state to make everything under the given pointer have
     the provided new owned/valid bits. *)
  Definition abstract_reassign_pointer
             (abst : abstract_state) (conc : concrete_state)
             (ptr : ptable_pointer) (attrs : attributes)
             (begin end_ : uintvaddr_t) : abstract_state :=
    (* first, get the owned/valid bits *)
    let stage1_mode := arch_mm_stage1_attrs_to_mode attrs in
    let stage2_mode := arch_mm_stage2_attrs_to_mode attrs in
    let s1_owned := ((stage1_mode & MM_MODE_UNOWNED) != 0)%N in
    let s1_valid := ((stage1_mode & MM_MODE_INVALID) != 0)%N in
    let s2_owned := ((stage2_mode & MM_MODE_UNOWNED) != 0)%N in
    let s2_valid := ((stage2_mode & MM_MODE_INVALID) != 0)%N in

    (* update the state with regard to Hafnium *)
    let abst :=
        abstract_reassign_pointer_for_entity
          abst conc ptr s1_owned s1_valid (inr hid) hafnium_ptable begin end_ in

    (* update the state with regard to each VM *)
    fold_right
      (fun (v : vm) (abst : abstract_state) =>
         abstract_reassign_pointer_for_entity
           abst conc ptr s2_owned s2_valid (inl v.(vm_id)) (vm_ptable v)
           begin end_)
      abst
      vms.

  Definition has_uniform_attrs
             (ptable_deref : ptable_pointer -> mm_page_table)
             (t : mm_page_table) (level : nat) (attrs : attributes)
             (begin end_ : uintvaddr_t) : Prop :=
    forall (a : uintvaddr_t) (pte : pte_t),
      (begin <= a < end_)%N ->
      page_lookup' ptable_deref a t (4 - level) = Some pte ->
      forall lvl, arch_mm_pte_attrs pte lvl = attrs.

  Lemma reassign_pointer_represents conc ptr t abst:
    represents abst conc ->
    let conc' := conc.(reassign_pointer) ptr t in
    forall attrs level begin end_,
      has_uniform_attrs
        conc'.(ptable_deref) t level attrs begin end_ ->
      represents (abstract_reassign_pointer
                    abst conc ptr attrs begin end_)
                 conc'.
  Proof.
    cbv [reassign_pointer represents].
    cbv [is_valid].
    cbv [vm_page_valid haf_page_valid vm_page_owned haf_page_owned].
    cbn [ptable_deref].
    basics; try solver.
    (* TODO: 4 subgoals *)
  Admitted.

  Lemma abstract_reassign_pointer_trivial abst conc ptr attrs i :
    abstract_state_equiv (abstract_reassign_pointer abst conc ptr attrs i i)
                         abst.
  Admitted. (* TODO *)

  Lemma abstract_reassign_pointer_for_entity_change_concrete
        abst conc conc' ptr owned valid e root_ptr begin end_ :
    index_sequences_to_pointer conc.(ptable_deref) ptr root_ptr
    = index_sequences_to_pointer conc'.(ptable_deref) ptr root_ptr ->
    abstract_reassign_pointer_for_entity
      abst conc ptr owned valid e root_ptr begin end_
    = abstract_reassign_pointer_for_entity
        abst conc' ptr owned valid e root_ptr begin end_.
  Proof.
    cbv beta iota delta [abstract_reassign_pointer_for_entity
                           addresses_under_pointer_in_range].
    intro Heq. rewrite Heq. reflexivity.
  Qed.

  Lemma abstract_reassign_pointer_change_concrete
        abst conc conc' ptr attrs begin_index end_index :
    Forall (fun root =>
              index_sequences_to_pointer conc.(ptable_deref) ptr root
              = index_sequences_to_pointer conc'.(ptable_deref) ptr root)
           all_root_ptables ->
    abstract_reassign_pointer abst conc ptr attrs begin_index end_index
    = abstract_reassign_pointer abst conc' ptr attrs begin_index end_index.
  Proof.
    cbv [abstract_reassign_pointer all_root_ptables].
    repeat match goal with
           | _ => progress basics
           | _ => progress invert_list_properties
           | H : _ |- _ => apply Forall_map in H; rewrite Forall_forall in H
           | _ =>
             rewrite abstract_reassign_pointer_for_entity_change_concrete
               with (conc':=conc') by eauto
           | _ => apply fold_right_ext
           | _ => solve
                    [auto using
                          abstract_reassign_pointer_for_entity_change_concrete]
           end.
  Qed.

  (* has_uniform_attrs doesn't care if we reassign the pointer we started from *)
  (* TODO : fill in preconditions *)
  Lemma has_uniform_attrs_reassign_pointer c ptr new_table t level attrs begin end_:
    ~ pointer_in_table (ptable_deref c) ptr t ->
    has_uniform_attrs (ptable_deref c) t level attrs begin end_ ->
    has_uniform_attrs
      (ptable_deref (reassign_pointer c ptr new_table))
      t level attrs begin end_.
  Admitted. (* TODO *)

  Definition no_addresses_in_range deref ptr begin end_ : Prop :=
    Forall
      (fun root_ptable =>
         addresses_under_pointer_in_range deref ptr root_ptable begin end_ = nil)
      all_root_ptables.

  (* abstract_reassign_pointer is a no-op if the given tables don't have any
     addresses in range *)
  (* TODO: fill in preconditions; likely needs to know that the table is at the
     right level *)
  Lemma abstract_reassign_pointer_low
        abst conc attrs begin end_ t_ptrs :
    Forall
      (fun ptr => no_addresses_in_range conc.(ptable_deref) ptr begin end_)
      t_ptrs ->
    abstract_state_equiv
      abst
      (fold_left
         (fun abst t_ptr =>
            abstract_reassign_pointer abst conc t_ptr attrs begin end_)
         t_ptrs
         abst).
  Admitted.

  (* we can expand the range to include pointers that are out of range *)
  (* TODO: fill in preconditions; likely needs to know that the table is at the
     right level *)
  Lemma abstract_reassign_pointer_high
        abst conc attrs begin end_ i t_ptrs :
    Forall
      (fun ptr => no_addresses_in_range conc.(ptable_deref) ptr begin end_)
      (skipn i t_ptrs) ->
    abstract_state_equiv
      (fold_left
         (fun abst t_ptr =>
            abstract_reassign_pointer abst conc t_ptr attrs begin end_)
         (firstn i t_ptrs)
         abst)
      (fold_left
         (fun abst t_ptr =>
            abstract_reassign_pointer abst conc t_ptr attrs begin end_)
         t_ptrs
         abst).
  Admitted.
End Proofs.