/*
 * Copyright 2018 The Hafnium Authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <stdatomic.h>

#include "hf/arch/types.h"

#include "hf/cpu.h"
#include "hf/list.h"
#include "hf/mm.h"
#include "hf/mpool.h"

#include "vmapi/hf/spci.h"

#define LOG_BUFFER_SIZE 256

enum mailbox_state {
	/** There is no message in the mailbox. */
	MAILBOX_STATE_EMPTY,

	/** There is a message in the mailbox that is waiting for a reader. */
	MAILBOX_STATE_RECEIVED,

	/** There is a message in the mailbox that has been read. */
	MAILBOX_STATE_READ,
};

struct wait_entry {
	/** The VM that is waiting for a mailbox to become writable. */
	struct vm *waiting_vm;

	/**
	 * Links used to add entry to a VM's waiter_list. This is protected by
	 * the notifying VM's lock.
	 */
	struct list_entry wait_links;

	/**
	 * Links used to add entry to a VM's ready_list. This is protected by
	 * the waiting VM's lock.
	 */
	struct list_entry ready_links;
};

struct mailbox {
	enum mailbox_state state;
	struct spci_message *recv;
	const struct spci_message *send;

	/**
	 * List of wait_entry structs representing VMs that want to be notified
	 * when the mailbox becomes writable. Once the mailbox does become
	 * writable, the entry is removed from this list and added to the
	 * waiting VM's ready_list.
	 */
	struct list_entry waiter_list;

	/**
	 * List of wait_entry structs representing VMs whose mailboxes became
	 * writable since the owner of the mailbox registers for notification.
	 */
	struct list_entry ready_list;
};

struct vm {
	spci_vm_id_t id;
	/** See api.c for the partial ordering on locks. */
	struct spinlock lock;
	spci_vcpu_count_t vcpu_count;
	struct vcpu vcpus[MAX_CPUS];
	struct mm_ptable ptable;
	struct mailbox mailbox;
	char log_buffer[LOG_BUFFER_SIZE];
	size_t log_buffer_length;

	/** Wait entries to be used when waiting on other VM mailboxes. */
	struct wait_entry wait_entries[MAX_VMS];

	atomic_bool aborting;

	/** Arch-specific VM information. */
	struct arch_vm arch;
};

/** Encapsulates a VM whose lock is held. */
struct vm_locked {
	struct vm *vm;
};

/** Container for two vm_locked structures */
struct two_vm_locked {
	struct vm_locked vm1;
	struct vm_locked vm2;
};

bool vm_init(spci_vcpu_count_t vcpu_count, struct mpool *ppool,
	     struct vm **new_vm);
spci_vm_count_t vm_get_count(void);
struct vm *vm_find(spci_vm_id_t id);
struct vm_locked vm_lock(struct vm *vm);
struct two_vm_locked vm_lock_both(struct vm *vm1, struct vm *vm2);
void vm_unlock(struct vm_locked *locked);
struct vcpu *vm_get_vcpu(struct vm *vm, spci_vcpu_index_t vcpu_index);
