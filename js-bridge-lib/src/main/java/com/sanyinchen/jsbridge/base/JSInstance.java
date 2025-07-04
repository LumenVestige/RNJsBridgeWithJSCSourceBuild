/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 * <p>
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

package com.sanyinchen.jsbridge.base;

import com.sanyinchen.jsbridge.data.NativeArrayInterface;

/**
 * This interface includes the methods needed to use a running JS
 * instance, without specifying any of the bridge-specific
 * initialization or lifecycle management.
 */
public interface JSInstance {

    void invokeCallback(
            int callbackID,
            NativeArrayInterface arguments);
    // TODO if this interface survives refactoring, think about adding
    // callFunction.
}
