// Copyright (c) Facebook, Inc. and its affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

#include "Instance.h"

#include "JSBigString.h"
#include "JSBundleType.h"
#include "bridge/include/JSExecutor.h"
#include "MessageQueueThread.h"
#include "MethodCall.h"
#include "NativeToJsBridge.h"
#include "RAMBundleRegistry.h"
#include "RecoverableError.h"

#include "JSIndexedRAMBundle.h"
#include <folly/Memory.h>
#include <folly/MoveWrapper.h>
#include <folly/json.h>

#include <glog/logging.h>

#include <condition_variable>
#include <fstream>
#include <mutex>
#include <string>
#include <TraceSection.h>
namespace facebook {
    namespace react {

        Instance::~Instance() {
            if (nativeToJsBridge_) {
                nativeToJsBridge_->destroy();
            }
        }

        void Instance::initializeBridge(
                std::unique_ptr<InstanceCallback> callback,
                std::shared_ptr<JSExecutorFactory> jsef,
                std::shared_ptr<MessageQueueThread> jsQueue,
                std::shared_ptr<ModuleRegistry> moduleRegistry) {
            TRACE_SECTION("Instance::initializeBridge");
            callback_ = std::move(callback);
            moduleRegistry_ = std::move(moduleRegistry);
            jsQueue->runOnQueueSync([this, &jsef, jsQueue]() mutable {
                nativeToJsBridge_ = folly::make_unique<NativeToJsBridge>(
                        jsef.get(), moduleRegistry_, jsQueue, callback_);

                std::lock_guard<std::mutex> lock(m_syncMutex);
                m_syncReady = true;
                m_syncCV.notify_all();
            });

            CHECK(nativeToJsBridge_);
        }

        void Instance::loadApplication(std::unique_ptr<RAMBundleRegistry> bundleRegistry,
                                       std::unique_ptr<const JSBigString> string,
                                       std::string sourceURL) {
            TRACE_SECTION("Instance::loadApplication");
            callback_->incrementPendingJSCalls();
            nativeToJsBridge_->loadApplication(std::move(bundleRegistry), std::move(string),
                                               std::move(sourceURL));
        }

        void Instance::loadApplicationSync(std::unique_ptr<RAMBundleRegistry> bundleRegistry,
                                           std::unique_ptr<const JSBigString> string,
                                           std::string sourceURL) {
            TRACE_SECTION("Instance::loadApplicationSync");
            std::unique_lock<std::mutex> lock(m_syncMutex);
            m_syncCV.wait(lock, [this] { return m_syncReady; });
            nativeToJsBridge_->loadApplicationSync(std::move(bundleRegistry), std::move(string),
                                                   std::move(sourceURL));
        }

        void Instance::setSourceURL(std::string sourceURL) {
            callback_->incrementPendingJSCalls();
            nativeToJsBridge_->loadApplication(nullptr, nullptr, std::move(sourceURL));
        }

        void Instance::loadScriptFromString(std::unique_ptr<const JSBigString> string,
                                            std::string sourceURL,
                                            bool loadSynchronously) {
            TRACE_SECTION("Instance::loadScriptFromString");
            if (loadSynchronously) {
                loadApplicationSync(nullptr, std::move(string), std::move(sourceURL));
            } else {
                loadApplication(nullptr, std::move(string), std::move(sourceURL));
            }
        }

        bool Instance::isIndexedRAMBundle(const char *sourcePath) {
            TRACE_SECTION("Instance::isIndexedRAMBundle");
            std::ifstream bundle_stream(sourcePath, std::ios_base::in);
            BundleHeader header;

            if (!bundle_stream ||
                !bundle_stream.read(reinterpret_cast<char *>(&header), sizeof(header))) {
                return false;
            }

            return parseTypeFromHeader(header) == ScriptTag::RAMBundle;
        }

        void Instance::loadRAMBundleFromFile(const std::string &sourcePath,
                                             const std::string &sourceURL,
                                             bool loadSynchronously) {
            auto bundle = folly::make_unique<JSIndexedRAMBundle>(sourcePath.c_str());
            auto startupScript = bundle->getStartupCode();
            auto registry = RAMBundleRegistry::multipleBundlesRegistry(std::move(bundle),
                                                                       JSIndexedRAMBundle::buildFactory());
            loadRAMBundle(
                    std::move(registry),
                    std::move(startupScript),
                    sourceURL,
                    loadSynchronously);
        }

        void Instance::loadRAMBundle(std::unique_ptr<RAMBundleRegistry> bundleRegistry,
                                     std::unique_ptr<const JSBigString> startupScript,
                                     std::string startupScriptSourceURL,
                                     bool loadSynchronously) {
            if (loadSynchronously) {
                loadApplicationSync(std::move(bundleRegistry), std::move(startupScript),
                                    std::move(startupScriptSourceURL));
            } else {
                loadApplication(std::move(bundleRegistry), std::move(startupScript),
                                std::move(startupScriptSourceURL));
            }
        }

        void Instance::setGlobalVariable(std::string propName,
                                         std::unique_ptr<const JSBigString> jsonValue) {
            nativeToJsBridge_->setGlobalVariable(std::move(propName),
                                                 std::move(jsonValue));
        }

        void *Instance::getJavaScriptContext() {
            return nativeToJsBridge_ ? nativeToJsBridge_->getJavaScriptContext()
                                     : nullptr;
        }

        bool Instance::isInspectable() {
            return nativeToJsBridge_ ? nativeToJsBridge_->isInspectable() : false;
        }

        bool Instance::isBatchActive() {
            return nativeToJsBridge_ ? nativeToJsBridge_->isBatchActive() : false;
        }

        void Instance::callJSFunction(std::string &&module, std::string &&method,
                                      folly::dynamic &&params) {
            TRACE_SECTION("Instance::callJSFunction");
            callback_->incrementPendingJSCalls();
            nativeToJsBridge_->callFunction(std::move(module), std::move(method),
                                            std::move(params));
        }

        void Instance::callJSCallback(uint64_t callbackId, folly::dynamic &&params) {
            TRACE_SECTION("Instance::callJSCallback");
            callback_->incrementPendingJSCalls();
            nativeToJsBridge_->invokeCallback((double) callbackId, std::move(params));
        }

        void Instance::registerBundle(uint32_t bundleId, const std::string &bundlePath) {
            nativeToJsBridge_->registerBundle(bundleId, bundlePath);
        }

        const ModuleRegistry &Instance::getModuleRegistry() const {
            return *moduleRegistry_;
        }

        ModuleRegistry &Instance::getModuleRegistry() { return *moduleRegistry_; }

        void Instance::handleMemoryPressure(int pressureLevel) {
            nativeToJsBridge_->handleMemoryPressure(pressureLevel);
        }

    } // namespace react
} // namespace facebook
