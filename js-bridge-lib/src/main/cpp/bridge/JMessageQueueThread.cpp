// Copyright (c) Facebook, Inc. and its affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

#include "JMessageQueueThread.h"

#include <condition_variable>
#include <mutex>

#include <fbjni/fbjni.h>
#include <fbjni/detail/Log.h>
#include <folly/Memory.h>
#include <jscexecutor/jsi/jsi/jsi.h>

#include "JNativeRunnable.h"

namespace facebook {
namespace react {

namespace {

struct JavaJSException : jni::JavaClass<JavaJSException, JThrowable> {
  static constexpr auto kJavaDescriptor = "Lcom/sanyinchen/jsbridge/exception/JSException;";

  static local_ref<JavaJSException> create(const char* message, const char* stack,
                                           const std::exception& ex) {
    local_ref<jthrowable> cause = jni::JCppException::create(ex);
    return newInstance(make_jstring(message), make_jstring(stack), cause.get());
  }
};

std::function<void()> wrapRunnable(std::function<void()>&& runnable) {
  return [runnable=std::move(runnable)] {
    try {
      runnable();
    } catch (const jsi::JSError& ex) {
      throwNewJavaException(
          JavaJSException::create(ex.getMessage().c_str(), ex.getStack().c_str(), ex)
          .get());
    }
  };
}

}

JMessageQueueThread::JMessageQueueThread(alias_ref<JavaMessageQueueThread::javaobject> jobj) :
    m_jobj(make_global(jobj)) {
}

void JMessageQueueThread::runOnQueue(std::function<void()>&& runnable) {
  // For C++ modules, this can be called from an arbitrary thread
  // managed by the module, via callJSCallback or callJSFunction.  So,
  // we ensure that it is registered with the JVM.
  jni::ThreadScope guard;
  static auto method = JavaMessageQueueThread::javaClassStatic()->
    getMethod<void(Runnable::javaobject)>("runOnQueue");
  method(m_jobj, JNativeRunnable::newObjectCxxArgs(wrapRunnable(std::move(runnable))).get());
}

void JMessageQueueThread::runOnQueueSync(std::function<void()>&& runnable) {
  static auto jIsOnThread = JavaMessageQueueThread::javaClassStatic()->
    getMethod<jboolean()>("isOnThread");

  if (jIsOnThread(m_jobj)) {
    wrapRunnable(std::move(runnable))();
  } else {
    std::mutex signalMutex;
    std::condition_variable signalCv;
    bool runnableComplete = false;

    runOnQueue([&] () mutable {
      std::lock_guard<std::mutex> lock(signalMutex);

      runnable();
      runnableComplete = true;

      signalCv.notify_one();
    });

    std::unique_lock<std::mutex> lock(signalMutex);
    signalCv.wait(lock, [&runnableComplete] { return runnableComplete; });
  }
}

void JMessageQueueThread::quitSynchronous() {
  static auto method = JavaMessageQueueThread::javaClassStatic()->
    getMethod<void()>("quitSynchronous");
  method(m_jobj);
}

} }
