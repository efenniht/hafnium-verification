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

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "hf/arch/types.h"

#include "hf/addr.h"

#include "vmapi/hf/spci.h"

/**
 * Disables interrutps.
 */
void arch_irq_disable(void);

/**
 * Enables interrupts.
 */
void arch_irq_enable(void);

/**
 * Reset the register values other than the PC and argument which are set with
 * `arch_regs_set_pc_arg()`.
 */
void arch_regs_reset(struct arch_regs *r, bool is_primary, spci_vm_id_t vm_id,
		     cpu_id_t vcpu_id, paddr_t table);

/**
 * Updates the given registers so that when a vcpu runs, it starts off at the
 * given address (pc) with the given argument.
 *
 * This function must only be called on an arch_regs that is known not be in use
 * by any other physical CPU.
 */
void arch_regs_set_pc_arg(struct arch_regs *r, ipaddr_t pc, uintreg_t arg);

/**
 * Updates the register holding the return value of a function.
 *
 * This function must only be called on an arch_regs that is known not be in use
 * by any other physical CPU.
 */
void arch_regs_set_retval(struct arch_regs *r, uintreg_t v);
