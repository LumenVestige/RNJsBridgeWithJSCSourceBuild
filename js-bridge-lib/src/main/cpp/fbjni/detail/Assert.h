/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#ifndef FBASSERT_H
#define FBASSERT_H

#include "visibility.h"

namespace facebook {
#define ENABLE_FBASSERT 1

#if ENABLE_FBASSERT
#define FBASSERTMSGF(expr, msg, ...) !(expr) ? facebook::assertInternal("Assert (%s:%d): " msg, __FILE__, __LINE__, ##__VA_ARGS__) : (void) 0
#else
#define FBASSERTMSGF(expr, msg, ...)
#endif // ENABLE_FBASSERT

#define FBASSERT(expr) FBASSERTMSGF(expr, "%s", #expr)

#define FBCRASH(msg, ...) facebook::assertInternal("Fatal error (%s:%d): " msg, __FILE__, __LINE__, ##__VA_ARGS__)
#define FBUNREACHABLE() facebook::assertInternal("This code should be unreachable (%s:%d)", __FILE__, __LINE__)

FBEXPORT void assertInternal(const char* formatstr, ...) __attribute__((noreturn));

// This allows storing the assert message before the current process terminates due to a crash
typedef void (*AssertHandler)(const char* message);
void setAssertHandler(AssertHandler assertHandler);

} // namespace facebook
#endif // FBASSERT_H
