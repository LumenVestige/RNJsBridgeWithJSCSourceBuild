/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

package com.sanyinchen.jsbridge.data;


import com.facebook.jni.annotations.DoNotStrip;

/**
 * Interface of a iterator for a {@link NativeMap}'s key set.
 */
@DoNotStrip
public interface ReadableMapKeySetIterator {

  boolean hasNextKey();
  String nextKey();
}
