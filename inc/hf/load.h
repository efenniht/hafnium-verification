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

#include <stddef.h>
#include <stdint.h>

#include "hf/boot_params.h"
#include "hf/cpio.h"
#include "hf/memiter.h"
#include "hf/mm.h"
#include "hf/mpool.h"

bool load_primary(struct mm_stage1_locked stage1_locked,
		  const struct memiter *cpio, uintreg_t kernel_arg,
		  struct memiter *initrd, struct mpool *ppool);
bool load_secondary(struct mm_stage1_locked stage1_locked,
		    const struct memiter *cpio,
		    const struct boot_params *params,
		    struct boot_params_update *update, struct mpool *ppool);
