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

/* These are checked in offset.c. */
#define CPU_ID 0
#define CPU_STACK_BOTTOM 8
#define VCPU_REGS 32
#define VCPU_LAZY (VCPU_REGS + 264)
#define VCPU_FREGS (VCPU_LAZY + 232)

#define REGS_SIZE 1024

#if GIC_VERSION == 3 || GIC_VERSION == 4
#define VCPU_GIC (VCPU_FREGS + 528)
#endif
