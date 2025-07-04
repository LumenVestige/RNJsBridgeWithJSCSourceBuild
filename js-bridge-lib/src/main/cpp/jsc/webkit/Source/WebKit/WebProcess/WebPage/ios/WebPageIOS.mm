/*
 * Copyright (C) 2012-2018 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "config.h"
#import "WebPage.h"

#if PLATFORM(IOS_FAMILY)

#import "AccessibilityIOS.h"
#import "DataReference.h"
#import "DocumentEditingContext.h"
#import "DrawingArea.h"
#import "EditingRange.h"
#import "EditorState.h"
#import "GestureTypes.h"
#import "InteractionInformationAtPosition.h"
#import "Logging.h"
#import "NativeWebKeyboardEvent.h"
#import "PluginView.h"
#import "PrintInfo.h"
#import "RemoteLayerTreeDrawingArea.h"
#import "SandboxUtilities.h"
#import "SyntheticEditingCommandType.h"
#import "TextCheckingControllerProxy.h"
#import "UIKitSPI.h"
#import "UserData.h"
#import "ViewGestureGeometryCollector.h"
#import "VisibleContentRectUpdateInfo.h"
#import "WKAccessibilityWebPageObjectIOS.h"
#import "WebAutocorrectionContext.h"
#import "WebAutocorrectionData.h"
#import "WebChromeClient.h"
#import "WebCoreArgumentCoders.h"
#import "WebFrame.h"
#import "WebImage.h"
#import "WebPageProxyMessages.h"
#import "WebPreviewLoaderClient.h"
#import "WebProcess.h"
#import <CoreText/CTFont.h>
#import <WebCore/Autofill.h>
#import <WebCore/AutofillElements.h>
#import <WebCore/Chrome.h>
#import <WebCore/ContentChangeObserver.h>
#import <WebCore/DOMTimerHoldingTank.h>
#import <WebCore/DataDetection.h>
#import <WebCore/DiagnosticLoggingClient.h>
#import <WebCore/DiagnosticLoggingKeys.h>
#import <WebCore/DocumentLoader.h>
#import <WebCore/DragController.h>
#import <WebCore/Editing.h>
#import <WebCore/Editor.h>
#import <WebCore/Element.h>
#import <WebCore/ElementAncestorIterator.h>
#import <WebCore/EventHandler.h>
#import <WebCore/File.h>
#import <WebCore/FloatQuad.h>
#import <WebCore/FocusController.h>
#import <WebCore/Frame.h>
#import <WebCore/FrameLoaderClient.h>
#import <WebCore/FrameView.h>
#import <WebCore/GeometryUtilities.h>
#import <WebCore/HTMLAreaElement.h>
#import <WebCore/HTMLAttachmentElement.h>
#import <WebCore/HTMLBodyElement.h>
#import <WebCore/HTMLElement.h>
#import <WebCore/HTMLElementTypeHelpers.h>
#import <WebCore/HTMLFormElement.h>
#import <WebCore/HTMLIFrameElement.h>
#import <WebCore/HTMLImageElement.h>
#import <WebCore/HTMLInputElement.h>
#import <WebCore/HTMLLabelElement.h>
#import <WebCore/HTMLOptGroupElement.h>
#import <WebCore/HTMLOptionElement.h>
#import <WebCore/HTMLParserIdioms.h>
#import <WebCore/HTMLSelectElement.h>
#import <WebCore/HTMLSummaryElement.h>
#import <WebCore/HTMLTextAreaElement.h>
#import <WebCore/HTMLTextFormControlElement.h>
#import <WebCore/HistoryItem.h>
#import <WebCore/HitTestResult.h>
#import <WebCore/InputMode.h>
#import <WebCore/KeyboardEvent.h>
#import <WebCore/LibWebRTCProvider.h>
#import <WebCore/MediaSessionManagerIOS.h>
#import <WebCore/Node.h>
#import <WebCore/NodeList.h>
#import <WebCore/NotImplemented.h>
#import <WebCore/Page.h>
#import <WebCore/Pasteboard.h>
#import <WebCore/PlatformKeyboardEvent.h>
#import <WebCore/PlatformMouseEvent.h>
#import <WebCore/PointerCaptureController.h>
#import <WebCore/Quirks.h>
#import <WebCore/RenderBlock.h>
#import <WebCore/RenderImage.h>
#import <WebCore/RenderThemeIOS.h>
#import <WebCore/RenderView.h>
#import <WebCore/RuntimeApplicationChecks.h>
#import <WebCore/Settings.h>
#import <WebCore/SharedBuffer.h>
#import <WebCore/StyleProperties.h>
#import <WebCore/TextIndicator.h>
#import <WebCore/TextIterator.h>
#import <WebCore/UserAgent.h>
#import <WebCore/VisibleUnits.h>
#import <WebCore/WebEvent.h>
#import <wtf/MathExtras.h>
#import <wtf/MemoryPressureHandler.h>
#import <wtf/SetForScope.h>
#import <wtf/SoftLinking.h>
#import <wtf/cocoa/Entitlements.h>
#import <wtf/text/TextStream.h>

#define RELEASE_LOG_IF_ALLOWED(channel, fmt, ...) RELEASE_LOG_IF(isAlwaysOnLoggingAllowed(), channel, "%p - WebPage::" fmt, this, ##__VA_ARGS__)
#define RELEASE_LOG_ERROR_IF_ALLOWED(channel, fmt, ...) RELEASE_LOG_ERROR_IF(isAlwaysOnLoggingAllowed(), channel, "%p - WebPage::" fmt, this, ##__VA_ARGS__)

namespace WebKit {
using namespace WebCore;

void WebPage::platformInitialize()
{
    platformInitializeAccessibility();
}

void WebPage::platformDetach()
{
    [m_mockAccessibilityElement setWebPage:nullptr];
}
    
void WebPage::platformInitializeAccessibility()
{
    m_mockAccessibilityElement = adoptNS([[WKAccessibilityWebPageObject alloc] init]);
    [m_mockAccessibilityElement setWebPage:this];

    accessibilityTransferRemoteToken(accessibilityRemoteTokenData());
}

void WebPage::platformReinitialize()
{
    accessibilityTransferRemoteToken(accessibilityRemoteTokenData());
}

RetainPtr<NSData> WebPage::accessibilityRemoteTokenData() const
{
    return newAccessibilityRemoteToken([NSUUID UUID]);
}

static void computeEditableRootHasContentAndPlainText(const VisibleSelection& selection, EditorState::PostLayoutData& data)
{
    data.hasContent = false;
    data.hasPlainText = false;
    if (!selection.isContentEditable())
        return;

    if (data.selectedTextLength || data.characterAfterSelection || data.characterBeforeSelection || data.twoCharacterBeforeSelection) {
        // If any of these variables have been previously set, the editable root must have plain text content, so we can bail from the remainder of the check.
        data.hasContent = true;
        data.hasPlainText = true;
        return;
    }

    auto* root = selection.rootEditableElement();
    if (!root)
        return;

    auto startInEditableRoot = firstPositionInNode(root);
    data.hasContent = root->hasChildNodes() && !isEndOfEditableOrNonEditableContent(startInEditableRoot);
    data.hasPlainText = data.hasContent && hasAnyPlainText(Range::create(root->document(), VisiblePosition { startInEditableRoot }, VisiblePosition { lastPositionInNode(root) }));
}

bool WebPage::isTransparentOrFullyClipped(const Element& element) const
{
    auto* renderer = element.renderer();
    if (!renderer)
        return false;

    auto* enclosingLayer = renderer->enclosingLayer();
    return enclosingLayer && enclosingLayer->isTransparentOrFullyClippedRespectingParentFrames();
}

void WebPage::platformEditorState(Frame& frame, EditorState& result, IncludePostLayoutDataHint shouldIncludePostLayoutData) const
{
    FrameView* view = frame.view();
    if (frame.editor().hasComposition()) {
        RefPtr<Range> compositionRange = frame.editor().compositionRange();
        Vector<WebCore::SelectionRect> compositionRects;
        if (compositionRange) {
            compositionRange->collectSelectionRects(compositionRects);
            if (compositionRects.size())
                result.firstMarkedRect = view->contentsToRootView(compositionRects[0].rect());
            if (compositionRects.size() > 1)
                result.lastMarkedRect = view->contentsToRootView(compositionRects.last().rect());
            else
                result.lastMarkedRect = result.firstMarkedRect;
            result.markedText = plainTextReplacingNoBreakSpace(compositionRange.get());
        }
    }

    // We only set the remaining EditorState entries if layout is done as a performance optimization
    // to avoid the need to force a synchronous layout here to compute these entries. If we
    // have a composition or are using a hardware keyboard then we send the full editor state
    // immediately so that the UIProcess can update UI, including the position of the caret.
    bool needsLayout = !frame.view() || frame.view()->needsLayout();
    bool requiresPostLayoutData = frame.editor().hasComposition();
#if !PLATFORM(MACCATALYST)
    requiresPostLayoutData |= m_keyboardIsAttached;
#endif
    if ((shouldIncludePostLayoutData == IncludePostLayoutDataHint::No || needsLayout) && !requiresPostLayoutData) {
        result.isMissingPostLayoutData = true;
        return;
    }

    auto& postLayoutData = result.postLayoutData();
    
    const VisibleSelection& selection = frame.selection().selection();
    postLayoutData.isStableStateUpdate = m_isInStableState;
    bool startNodeIsInsideFixedPosition = false;
    bool endNodeIsInsideFixedPosition = false;
    if (selection.isCaret()) {
        postLayoutData.caretRectAtStart = view->contentsToRootView(frame.selection().absoluteCaretBounds(&startNodeIsInsideFixedPosition));
        endNodeIsInsideFixedPosition = startNodeIsInsideFixedPosition;
        postLayoutData.caretRectAtEnd = postLayoutData.caretRectAtStart;
        // FIXME: The following check should take into account writing direction.
        postLayoutData.isReplaceAllowed = result.isContentEditable && atBoundaryOfGranularity(selection.start(), WordGranularity, DirectionForward);
        postLayoutData.wordAtSelection = plainTextReplacingNoBreakSpace(wordRangeFromPosition(selection.start()).get());
        if (selection.isContentEditable())
            charactersAroundPosition(selection.start(), postLayoutData.characterAfterSelection, postLayoutData.characterBeforeSelection, postLayoutData.twoCharacterBeforeSelection);
    } else if (selection.isRange()) {
        postLayoutData.caretRectAtStart = view->contentsToRootView(VisiblePosition(selection.start()).absoluteCaretBounds(&startNodeIsInsideFixedPosition));
        postLayoutData.caretRectAtEnd = view->contentsToRootView(VisiblePosition(selection.end()).absoluteCaretBounds(&endNodeIsInsideFixedPosition));
        RefPtr<Range> selectedRange = selection.toNormalizedRange();
        String selectedText;
        if (selectedRange) {
            selectedRange->collectSelectionRects(postLayoutData.selectionRects);
            convertSelectionRectsToRootView(view, postLayoutData.selectionRects);
            selectedText = plainTextReplacingNoBreakSpace(selectedRange.get(), TextIteratorDefaultBehavior, true);
            postLayoutData.selectedTextLength = selectedText.length();
            const int maxSelectedTextLength = 200;
            if (selectedText.length() <= maxSelectedTextLength)
                postLayoutData.wordAtSelection = selectedText;
        }
        // FIXME: We should disallow replace when the string contains only CJ characters.
        postLayoutData.isReplaceAllowed = result.isContentEditable && !result.isInPasswordField && !selectedText.isAllSpecialCharacters<isHTMLSpace>();
    }
    postLayoutData.atStartOfSentence = frame.selection().selectionAtSentenceStart();
    postLayoutData.insideFixedPosition = startNodeIsInsideFixedPosition || endNodeIsInsideFixedPosition;
    if (!selection.isNone()) {
        if (m_focusedElement && m_focusedElement->renderer()) {
            auto& renderer = *m_focusedElement->renderer();
            postLayoutData.focusedElementRect = rootViewInteractionBoundsForElement(*m_focusedElement);
            postLayoutData.caretColor = renderer.style().caretColor();
        }
        if (result.isContentEditable) {
            if (auto container = makeRefPtr(selection.rootEditableElement()))
                postLayoutData.editableRootIsTransparentOrFullyClipped = isTransparentOrFullyClipped(*container);
        }
        computeEditableRootHasContentAndPlainText(selection, postLayoutData);
        postLayoutData.selectionStartIsAtParagraphBoundary = atBoundaryOfGranularity(selection.visibleStart(), TextGranularity::ParagraphGranularity, SelectionDirection::DirectionBackward);
        postLayoutData.selectionEndIsAtParagraphBoundary = atBoundaryOfGranularity(selection.visibleEnd(), TextGranularity::ParagraphGranularity, SelectionDirection::DirectionForward);
    }
}

void WebPage::platformWillPerformEditingCommand()
{
    auto& frame = m_page->focusController().focusedOrMainFrame();
    if (auto* document = frame.document()) {
        if (auto* holdingTank = document->domTimerHoldingTankIfExists())
            holdingTank->removeAll();
    }
}

FloatSize WebPage::screenSize() const
{
    return m_screenSize;
}

FloatSize WebPage::availableScreenSize() const
{
    return m_availableScreenSize;
}

FloatSize WebPage::overrideScreenSize() const
{
    return m_overrideScreenSize;
}

void WebPage::didReceiveMobileDocType(bool isMobileDoctype)
{
    resetViewportDefaultConfiguration(m_mainFrame.get(), isMobileDoctype);
}

void WebPage::savePageState(HistoryItem& historyItem)
{
    historyItem.setScaleIsInitial(!m_userHasChangedPageScaleFactor);
    historyItem.setMinimumLayoutSizeInScrollViewCoordinates(m_viewportConfiguration.minimumLayoutSize());
    historyItem.setContentSize(m_viewportConfiguration.contentsSize());
}

static double scaleAfterViewportWidthChange(double currentScale, bool userHasChangedPageScaleFactor, const ViewportConfiguration& viewportConfiguration, float unobscuredWidthInScrollViewCoordinates, const IntSize& newContentSize, const IntSize& oldContentSize, float visibleHorizontalFraction)
{
    double scale;
    if (!userHasChangedPageScaleFactor)
        scale = viewportConfiguration.initialScale();
    else
        scale = std::max(std::min(currentScale, viewportConfiguration.maximumScale()), viewportConfiguration.minimumScale());

    LOG(VisibleRects, "scaleAfterViewportWidthChange getting scale %.2f", scale);

    if (userHasChangedPageScaleFactor) {
        // When the content size changes, we keep the same relative horizontal content width in view, otherwise we would
        // end up zoomed too far in landscape->portrait, and too close in portrait->landscape.
        double widthToKeepInView = visibleHorizontalFraction * newContentSize.width();
        double newScale = unobscuredWidthInScrollViewCoordinates / widthToKeepInView;
        scale = std::max(std::min(newScale, viewportConfiguration.maximumScale()), viewportConfiguration.minimumScale());
    }
    return scale;
}

static FloatPoint relativeCenterAfterContentSizeChange(const FloatRect& originalContentRect, IntSize oldContentSize, IntSize newContentSize)
{
    // If the content size has changed, keep the same relative position.
    FloatPoint oldContentCenter = originalContentRect.center();
    float relativeHorizontalPosition = oldContentCenter.x() / oldContentSize.width();
    float relativeVerticalPosition =  oldContentCenter.y() / oldContentSize.height();
    return FloatPoint(relativeHorizontalPosition * newContentSize.width(), relativeVerticalPosition * newContentSize.height());
}

static inline FloatRect adjustExposedRectForNewScale(const FloatRect& exposedRect, double exposedRectScale, double newScale)
{
    if (exposedRectScale == newScale)
        return exposedRect;

    float horizontalChange = exposedRect.width() * exposedRectScale / newScale - exposedRect.width();
    float verticalChange = exposedRect.height() * exposedRectScale / newScale - exposedRect.height();

    auto adjustedRect = exposedRect;
    adjustedRect.inflate({ horizontalChange / 2, verticalChange / 2 });
    return adjustedRect;
}

void WebPage::restorePageState(const HistoryItem& historyItem)
{
    // When a HistoryItem is cleared, its scale factor and scroll point are set to zero. We should not try to restore the other
    // parameters in those conditions.
    if (!historyItem.pageScaleFactor()) {
        send(Messages::WebPageProxy::CouldNotRestorePageState());
        return;
    }

    // We can restore the exposed rect and scale, but we cannot touch the scroll position since the obscured insets
    // may be changing in the UIProcess. The UIProcess can update the position from the information we send and will then
    // scroll to the correct position through a regular VisibleContentRectUpdate.

    m_userHasChangedPageScaleFactor = !historyItem.scaleIsInitial();

    FrameView& frameView = *m_page->mainFrame().view();

    FloatSize currentMinimumLayoutSizeInScrollViewCoordinates = m_viewportConfiguration.minimumLayoutSize();
    if (historyItem.minimumLayoutSizeInScrollViewCoordinates() == currentMinimumLayoutSizeInScrollViewCoordinates) {
        float boundedScale = std::min<float>(m_viewportConfiguration.maximumScale(), std::max<float>(m_viewportConfiguration.minimumScale(), historyItem.pageScaleFactor()));
        scalePage(boundedScale, IntPoint());

        Optional<FloatPoint> scrollPosition;
        if (historyItem.shouldRestoreScrollPosition()) {
            m_drawingArea->setExposedContentRect(historyItem.exposedContentRect());
            m_hasRestoredExposedContentRectAfterDidCommitLoad = true;
            scrollPosition = FloatPoint(historyItem.scrollPosition());
        }
        send(Messages::WebPageProxy::RestorePageState(scrollPosition, frameView.scrollOrigin(), historyItem.obscuredInsets(), boundedScale));
    } else {
        IntSize oldContentSize = historyItem.contentSize();
        IntSize newContentSize = frameView.contentsSize();
        double visibleHorizontalFraction = static_cast<float>(historyItem.unobscuredContentRect().width()) / oldContentSize.width();

        double newScale = scaleAfterViewportWidthChange(historyItem.pageScaleFactor(), !historyItem.scaleIsInitial(), m_viewportConfiguration, currentMinimumLayoutSizeInScrollViewCoordinates.width(), newContentSize, oldContentSize, visibleHorizontalFraction);

        Optional<FloatPoint> newCenter;
        if (historyItem.shouldRestoreScrollPosition()) {
            if (!oldContentSize.isEmpty() && !newContentSize.isEmpty() && newContentSize != oldContentSize)
                newCenter = relativeCenterAfterContentSizeChange(historyItem.unobscuredContentRect(), oldContentSize, newContentSize);
            else
                newCenter = FloatRect(historyItem.unobscuredContentRect()).center();
        }

        scalePage(newScale, IntPoint());
        send(Messages::WebPageProxy::RestorePageCenterAndScale(newCenter, newScale));
    }
}

double WebPage::minimumPageScaleFactor() const
{
    if (!m_viewportConfiguration.allowsUserScaling())
        return m_page->pageScaleFactor();
    return m_viewportConfiguration.minimumScale();
}

double WebPage::maximumPageScaleFactor() const
{
    if (!m_viewportConfiguration.allowsUserScaling())
        return m_page->pageScaleFactor();
    return m_viewportConfiguration.maximumScale();
}

double WebPage::maximumPageScaleFactorIgnoringAlwaysScalable() const
{
    if (!m_viewportConfiguration.allowsUserScalingIgnoringAlwaysScalable())
        return m_page->pageScaleFactor();
    return m_viewportConfiguration.maximumScaleIgnoringAlwaysScalable();
}

bool WebPage::allowsUserScaling() const
{
    return m_viewportConfiguration.allowsUserScaling();
}

bool WebPage::handleEditingKeyboardEvent(KeyboardEvent& event)
{
    auto* platformEvent = event.underlyingPlatformEvent();
    if (!platformEvent)
        return false;
    
    // Don't send synthetic events to the UIProcess. They are only
    // used for interacting with JavaScript.
    if (platformEvent->isSyntheticEvent())
        return false;

    // FIXME: Interpret the event immediately upon receiving it in UI process, without sending to WebProcess first.
    bool eventWasHandled = false;
    bool sendResult = WebProcess::singleton().parentProcessConnection()->sendSync(Messages::WebPageProxy::InterpretKeyEvent(editorState(), platformEvent->type() == PlatformKeyboardEvent::Char),
        Messages::WebPageProxy::InterpretKeyEvent::Reply(eventWasHandled), m_pageID);
    return sendResult && eventWasHandled;
}

bool WebPage::parentProcessHasServiceWorkerEntitlement() const
{
    static bool hasEntitlement = WTF::hasEntitlement(WebProcess::singleton().parentProcessConnection()->xpcConnection(), "com.apple.developer.WebKit.ServiceWorkers");
    return hasEntitlement;
}

void WebPage::sendComplexTextInputToPlugin(uint64_t, const String&)
{
    notImplemented();
}

bool WebPage::performNonEditingBehaviorForSelector(const String&, WebCore::KeyboardEvent*)
{
    notImplemented();
    return false;
}

bool WebPage::performDefaultBehaviorForKeyEvent(const WebKeyboardEvent&)
{
    notImplemented();
    return false;
}

void WebPage::getSelectionContext(CallbackID callbackID)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    if (!frame.selection().isRange()) {
        send(Messages::WebPageProxy::SelectionContextCallback(String(), String(), String(), callbackID));
        return;
    }
    const int selectionExtendedContextLength = 350;
    
    String selectedText = plainTextReplacingNoBreakSpace(frame.selection().selection().toNormalizedRange().get());
    String textBefore = plainTextReplacingNoBreakSpace(rangeExpandedByCharactersInDirectionAtWordBoundary(frame.selection().selection().start(), selectionExtendedContextLength, DirectionBackward).get(), TextIteratorDefaultBehavior, true);
    String textAfter = plainTextReplacingNoBreakSpace(rangeExpandedByCharactersInDirectionAtWordBoundary(frame.selection().selection().end(), selectionExtendedContextLength, DirectionForward).get(), TextIteratorDefaultBehavior, true);

    send(Messages::WebPageProxy::SelectionContextCallback(selectedText, textBefore, textAfter, callbackID));
}

NSObject *WebPage::accessibilityObjectForMainFramePlugin()
{
    if (!m_page)
        return nil;
    
    if (auto* pluginView = pluginViewForFrame(&m_page->mainFrame()))
        return pluginView->accessibilityObject();
    
    return nil;
}
    
void WebPage::registerUIProcessAccessibilityTokens(const IPC::DataReference& elementToken, const IPC::DataReference&)
{
    NSData *elementTokenData = [NSData dataWithBytes:elementToken.data() length:elementToken.size()];
    [m_mockAccessibilityElement setRemoteTokenData:elementTokenData];
}

void WebPage::readSelectionFromPasteboard(const String&, CompletionHandler<void(bool&&)>&& completionHandler)
{
    notImplemented();
    completionHandler(false);
}

void WebPage::getStringSelectionForPasteboard(CompletionHandler<void(String&&)>&& completionHandler)
{
    notImplemented();
    completionHandler({ });
}

void WebPage::getDataSelectionForPasteboard(const String, CompletionHandler<void(SharedMemory::Handle&&, uint64_t)>&& completionHandler)
{
    notImplemented();
    completionHandler({ }, 0);
}

WKAccessibilityWebPageObject* WebPage::accessibilityRemoteObject()
{
    notImplemented();
    return 0;
}

bool WebPage::platformCanHandleRequest(const WebCore::ResourceRequest&)
{
    notImplemented();
    return false;
}

void WebPage::shouldDelayWindowOrderingEvent(const WebKit::WebMouseEvent&, CompletionHandler<void(bool)>&& completionHandler)
{
    notImplemented();
    completionHandler(false);
}

void WebPage::acceptsFirstMouse(int, const WebKit::WebMouseEvent&, CompletionHandler<void(bool)>&& completionHandler)
{
    notImplemented();
    completionHandler(false);
}

void WebPage::computePagesForPrintingPDFDocument(WebCore::FrameIdentifier, const PrintInfo&, Vector<IntRect>&)
{
    notImplemented();
}

void WebPage::drawPagesToPDFFromPDFDocument(CGContextRef, PDFDocument *, const PrintInfo&, uint32_t, uint32_t)
{
    notImplemented();
}

void WebPage::advanceToNextMisspelling(bool)
{
    notImplemented();
}

IntRect WebPage::rectForElementAtInteractionLocation() const
{
    HitTestResult result = m_page->mainFrame().eventHandler().hitTestResultAtPoint(m_lastInteractionLocation, HitTestRequest::ReadOnly | HitTestRequest::Active | HitTestRequest::AllowChildFrameContent);
    Node* hitNode = result.innerNode();
    if (!hitNode || !hitNode->renderer())
        return IntRect();
    return result.innerNodeFrame()->view()->contentsToRootView(hitNode->renderer()->absoluteBoundingBoxRect(true));
}

void WebPage::updateSelectionAppearance()
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    if (!frame.editor().ignoreSelectionChanges() && (frame.editor().hasComposition() || !frame.selection().selection().isNone()))
        didChangeSelection();
}

static void dispatchSyntheticMouseMove(Frame& mainFrame, const WebCore::FloatPoint& location, OptionSet<WebEvent::Modifier> modifiers, WebCore::PointerID pointerId = WebCore::mousePointerID)
{
    IntPoint roundedAdjustedPoint = roundedIntPoint(location);
    auto shiftKey = modifiers.contains(WebEvent::Modifier::ShiftKey);
    auto ctrlKey = modifiers.contains(WebEvent::Modifier::ControlKey);
    auto altKey = modifiers.contains(WebEvent::Modifier::AltKey);
    auto metaKey = modifiers.contains(WebEvent::Modifier::MetaKey);
    auto mouseEvent = PlatformMouseEvent(roundedAdjustedPoint, roundedAdjustedPoint, NoButton, PlatformEvent::MouseMoved, 0, shiftKey, ctrlKey, altKey, metaKey, WallTime::now(), WebCore::ForceAtClick, WebCore::NoTap, pointerId);
    // FIXME: Pass caps lock state.
    mainFrame.eventHandler().dispatchSyntheticMouseMove(mouseEvent);
}

static bool nodeTriggersFastPath(const Node& targetNode)
{
    if (!is<Element>(targetNode))
        return false;

    if (is<HTMLFormControlElement>(targetNode))
        return true;

    auto ariaRole = AccessibilityObject::ariaRoleToWebCoreRole(downcast<Element>(targetNode).getAttribute(HTMLNames::roleAttr));
    return AccessibilityObject::isARIAControl(ariaRole) || AccessibilityObject::isARIAInput(ariaRole);
}

void WebPage::generateSyntheticEditingCommand(SyntheticEditingCommandType command)
{
    PlatformKeyboardEvent keyEvent;
    auto& frame = m_page->focusController().focusedOrMainFrame();
    
    OptionSet<PlatformEvent::Modifier> modifiers;
    modifiers.add(PlatformEvent::Modifier::MetaKey);
    
    switch (command) {
    case SyntheticEditingCommandType::Undo:
        keyEvent = PlatformKeyboardEvent(PlatformEvent::KeyDown, "z", "z",
#if ENABLE(KEYBOARD_KEY_ATTRIBUTE)
        "z",
#endif
#if ENABLE(KEYBOARD_CODE_ATTRIBUTE)
        "KeyZ"_s,
#endif
        @"U+005A", 90, false, false, false, modifiers, WallTime::now());
        break;
    case SyntheticEditingCommandType::Redo:
        keyEvent = PlatformKeyboardEvent(PlatformEvent::KeyDown, "y", "y",
#if ENABLE(KEYBOARD_KEY_ATTRIBUTE)
        "y",
#endif
#if ENABLE(KEYBOARD_CODE_ATTRIBUTE)
        "KeyY"_s,
#endif
        @"U+0059", 89, false, false, false, modifiers, WallTime::now());
        break;
    case SyntheticEditingCommandType::ToggleBoldface:
        keyEvent = PlatformKeyboardEvent(PlatformEvent::KeyDown, "b", "b",
#if ENABLE(KEYBOARD_KEY_ATTRIBUTE)
        "b",
#endif
#if ENABLE(KEYBOARD_CODE_ATTRIBUTE)
        "KeyB"_s,
#endif
        @"U+0042", 66, false, false, false, modifiers, WallTime::now());
        break;
    case SyntheticEditingCommandType::ToggleItalic:
        keyEvent = PlatformKeyboardEvent(PlatformEvent::KeyDown, "i", "i",
#if ENABLE(KEYBOARD_KEY_ATTRIBUTE)
        "i",
#endif
#if ENABLE(KEYBOARD_CODE_ATTRIBUTE)
        "KeyI"_s,
#endif
        @"U+0049", 73, false, false, false, modifiers, WallTime::now());
        break;
    case SyntheticEditingCommandType::ToggleUnderline:
        keyEvent = PlatformKeyboardEvent(PlatformEvent::KeyDown, "u", "u",
#if ENABLE(KEYBOARD_KEY_ATTRIBUTE)
        "u",
#endif
#if ENABLE(KEYBOARD_CODE_ATTRIBUTE)
        "KeyU"_s,
#endif
        @"U+0055", 85, false, false, false, modifiers, WallTime::now());
        break;
    default:
        break;
    }

    keyEvent.setIsSyntheticEvent();
    
    PlatformKeyboardEvent::setCurrentModifierState(modifiers);
    
    frame.eventHandler().keyEvent(keyEvent);
}

void WebPage::handleSyntheticClick(Node& nodeRespondingToClick, const WebCore::FloatPoint& location, OptionSet<WebEvent::Modifier> modifiers, WebCore::PointerID pointerId)
{
    if (!nodeRespondingToClick.document().settings().contentChangeObserverEnabled()) {
        completeSyntheticClick(nodeRespondingToClick, location, modifiers, WebCore::OneFingerTap, pointerId);
        return;
    }

    auto& respondingDocument = nodeRespondingToClick.document();
    auto& contentChangeObserver = respondingDocument.contentChangeObserver();
    auto targetNodeWentFromHiddenToVisible = contentChangeObserver.hiddenTouchTarget() == &nodeRespondingToClick && ContentChangeObserver::isConsideredVisible(nodeRespondingToClick);
    {
        LOG_WITH_STREAM(ContentObservation, stream << "handleSyntheticClick: node(" << &nodeRespondingToClick << ") " << location);
        ContentChangeObserver::MouseMovedScope observingScope(respondingDocument);
        auto& mainFrame = m_page->mainFrame();
        dispatchSyntheticMouseMove(mainFrame, location, modifiers, pointerId);
        mainFrame.document()->updateStyleIfNeeded();
        if (m_isClosed)
            return;
    }

    if (targetNodeWentFromHiddenToVisible) {
        LOG(ContentObservation, "handleSyntheticClick: target node was hidden and now is visible -> hover.");
        return;
    }

    auto observedContentChange = contentChangeObserver.observedContentChange();
    auto targetNodeTriggersFastPath = nodeTriggersFastPath(nodeRespondingToClick);

    auto continueContentObservation = !(observedContentChange == WKContentVisibilityChange || targetNodeTriggersFastPath);
    if (continueContentObservation) {
        // Wait for callback to completePendingSyntheticClickForContentChangeObserver() to decide whether to send the click event.
        const Seconds observationDuration = 32_ms;
        contentChangeObserver.startContentObservationForDuration(observationDuration);
        LOG(ContentObservation, "handleSyntheticClick: Can't decide it yet -> wait.");
        m_pendingSyntheticClickNode = &nodeRespondingToClick;
        m_pendingSyntheticClickLocation = location;
        m_pendingSyntheticClickModifiers = modifiers;
        m_pendingSyntheticClickPointerId = pointerId;
        return;
    }
    contentChangeObserver.stopContentObservation();
    callOnMainThread([protectedThis = makeRefPtr(this), targetNode = Ref<Node>(nodeRespondingToClick), location, modifiers, observedContentChange, pointerId] {
        if (protectedThis->m_isClosed || !protectedThis->corePage())
            return;

        auto shouldStayAtHoverState = observedContentChange == WKContentVisibilityChange;
        if (shouldStayAtHoverState) {
            // The move event caused new contents to appear. Don't send synthetic click event, but just ensure that the mouse is on the most recent content.
            dispatchSyntheticMouseMove(protectedThis->corePage()->mainFrame(), location, modifiers, pointerId);
            LOG(ContentObservation, "handleSyntheticClick: Observed meaningful visible change -> hover.");
            return;
        }
        LOG(ContentObservation, "handleSyntheticClick: calling completeSyntheticClick -> click.");
        protectedThis->completeSyntheticClick(targetNode, location, modifiers, WebCore::OneFingerTap, pointerId);
    });
}

void WebPage::didFinishContentChangeObserving(WKContentChange observedContentChange)
{
    LOG_WITH_STREAM(ContentObservation, stream << "didFinishContentChangeObserving: pending target node(" << m_pendingSyntheticClickNode << ")");
    if (!m_pendingSyntheticClickNode)
        return;
    callOnMainThread([protectedThis = makeRefPtr(this), targetNode = Ref<Node>(*m_pendingSyntheticClickNode), originalDocument = makeWeakPtr(m_pendingSyntheticClickNode->document()), observedContentChange, location = m_pendingSyntheticClickLocation, modifiers = m_pendingSyntheticClickModifiers, pointerId = m_pendingSyntheticClickPointerId] {
        if (protectedThis->m_isClosed || !protectedThis->corePage())
            return;
        if (!originalDocument || &targetNode->document() != originalDocument)
            return;

        // Only dispatch the click if the document didn't get changed by any timers started by the move event.
        if (observedContentChange == WKContentNoChange) {
            LOG(ContentObservation, "No chage was observed -> click.");
            protectedThis->completeSyntheticClick(targetNode, location, modifiers, WebCore::OneFingerTap, pointerId);
            return;
        }
        // Ensure that the mouse is on the most recent content.
        LOG(ContentObservation, "Observed meaningful visible change -> hover.");
        dispatchSyntheticMouseMove(protectedThis->corePage()->mainFrame(), location, modifiers, pointerId);
    });
    m_pendingSyntheticClickNode = nullptr;
    m_pendingSyntheticClickLocation = { };
    m_pendingSyntheticClickModifiers = { };
    m_pendingSyntheticClickPointerId = 0;
}

void WebPage::completeSyntheticClick(Node& nodeRespondingToClick, const WebCore::FloatPoint& location, OptionSet<WebEvent::Modifier> modifiers, SyntheticClickType syntheticClickType, WebCore::PointerID pointerId)
{
    IntPoint roundedAdjustedPoint = roundedIntPoint(location);
    Frame& mainframe = m_page->mainFrame();

    RefPtr<Frame> oldFocusedFrame = m_page->focusController().focusedFrame();
    RefPtr<Element> oldFocusedElement = oldFocusedFrame ? oldFocusedFrame->document()->focusedElement() : nullptr;

    SetForScope<bool> userIsInteractingChange { m_userIsInteracting, true };

    bool tapWasHandled = false;
    m_lastInteractionLocation = roundedAdjustedPoint;

    // FIXME: Pass caps lock state.
    bool shiftKey = modifiers.contains(WebEvent::Modifier::ShiftKey);
    bool ctrlKey = modifiers.contains(WebEvent::Modifier::ControlKey);
    bool altKey = modifiers.contains(WebEvent::Modifier::AltKey);
    bool metaKey = modifiers.contains(WebEvent::Modifier::MetaKey);

    tapWasHandled |= mainframe.eventHandler().handleMousePressEvent(PlatformMouseEvent(roundedAdjustedPoint, roundedAdjustedPoint, LeftButton, PlatformEvent::MousePressed, 1, shiftKey, ctrlKey, altKey, metaKey, WallTime::now(), WebCore::ForceAtClick, syntheticClickType, pointerId));
    if (m_isClosed)
        return;

    tapWasHandled |= mainframe.eventHandler().handleMouseReleaseEvent(PlatformMouseEvent(roundedAdjustedPoint, roundedAdjustedPoint, LeftButton, PlatformEvent::MouseReleased, 1, shiftKey, ctrlKey, altKey, metaKey, WallTime::now(), WebCore::ForceAtClick, syntheticClickType, pointerId));
    if (m_isClosed)
        return;

    RefPtr<Frame> newFocusedFrame = m_page->focusController().focusedFrame();
    RefPtr<Element> newFocusedElement = newFocusedFrame ? newFocusedFrame->document()->focusedElement() : nullptr;

    // If the focus has not changed, we need to notify the client anyway, since it might be
    // necessary to start assisting the node.
    // If the node has been focused by JavaScript without user interaction, the
    // keyboard is not on screen.
    if (newFocusedElement && newFocusedElement == oldFocusedElement)
        elementDidRefocus(*newFocusedElement);

    if (nodeRespondingToClick.document().settings().contentChangeObserverEnabled()) {
        auto& document = nodeRespondingToClick.document();
        // Dispatch mouseOut to dismiss tooltip content when tapping on the control bar buttons (cc, settings).
        if (document.quirks().needsYouTubeMouseOutQuirk()) {
            if (auto* frame = document.frame())
                frame->eventHandler().dispatchSyntheticMouseOut(PlatformMouseEvent(roundedAdjustedPoint, roundedAdjustedPoint, LeftButton, PlatformEvent::NoType, 0, shiftKey, ctrlKey, altKey, metaKey, WallTime::now(), 0, WebCore::NoTap, pointerId));
        }
    }

    if (m_isClosed)
        return;

    if (!tapWasHandled || !nodeRespondingToClick.isElementNode())
        send(Messages::WebPageProxy::DidNotHandleTapAsClick(roundedIntPoint(location)));
    
    send(Messages::WebPageProxy::DidCompleteSyntheticClick());
}

void WebPage::handleTap(const IntPoint& point, OptionSet<WebEvent::Modifier> modifiers, TransactionID lastLayerTreeTransactionId)
{
    FloatPoint adjustedPoint;
    Node* nodeRespondingToClick = m_page->mainFrame().nodeRespondingToClickEvents(point, adjustedPoint);
    Frame* frameRespondingToClick = nodeRespondingToClick ? nodeRespondingToClick->document().frame() : nullptr;
    IntPoint adjustedIntPoint = roundedIntPoint(adjustedPoint);

    if (!frameRespondingToClick || lastLayerTreeTransactionId < WebFrame::fromCoreFrame(*frameRespondingToClick)->firstLayerTreeTransactionIDAfterDidCommitLoad())
        send(Messages::WebPageProxy::DidNotHandleTapAsClick(adjustedIntPoint));
#if ENABLE(DATA_DETECTION)
    else if (is<Element>(*nodeRespondingToClick) && DataDetection::shouldCancelDefaultAction(downcast<Element>(*nodeRespondingToClick))) {
        InteractionInformationRequest request(adjustedIntPoint);
        requestPositionInformation(request);
        send(Messages::WebPageProxy::DidNotHandleTapAsClick(adjustedIntPoint));
    }
#endif
    else
        handleSyntheticClick(*nodeRespondingToClick, adjustedPoint, modifiers);
}

void WebPage::handleDoubleTapForDoubleClickAtPoint(const IntPoint& point, OptionSet<WebEvent::Modifier> modifiers, TransactionID lastLayerTreeTransactionId)
{
    FloatPoint adjustedPoint;
    auto* nodeRespondingToDoubleClick = m_page->mainFrame().nodeRespondingToDoubleClickEvent(point, adjustedPoint);
    if (!nodeRespondingToDoubleClick)
        return;

    auto* frameRespondingToDoubleClick = nodeRespondingToDoubleClick->document().frame();
    if (!frameRespondingToDoubleClick || lastLayerTreeTransactionId < WebFrame::fromCoreFrame(*frameRespondingToDoubleClick)->firstLayerTreeTransactionIDAfterDidCommitLoad())
        return;

    bool shiftKey = modifiers.contains(WebEvent::Modifier::ShiftKey);
    bool ctrlKey = modifiers.contains(WebEvent::Modifier::ControlKey);
    bool altKey = modifiers.contains(WebEvent::Modifier::AltKey);
    bool metaKey = modifiers.contains(WebEvent::Modifier::MetaKey);
    auto roundedAdjustedPoint = roundedIntPoint(adjustedPoint);
    nodeRespondingToDoubleClick->document().frame()->eventHandler().handleMousePressEvent(PlatformMouseEvent(roundedAdjustedPoint, roundedAdjustedPoint, LeftButton, PlatformEvent::MousePressed, 2, shiftKey, ctrlKey, altKey, metaKey, WallTime::now(), 0, WebCore::NoTap));
    if (m_isClosed)
        return;
    nodeRespondingToDoubleClick->document().frame()->eventHandler().handleMouseReleaseEvent(PlatformMouseEvent(roundedAdjustedPoint, roundedAdjustedPoint, LeftButton, PlatformEvent::MouseReleased, 2, shiftKey, ctrlKey, altKey, metaKey, WallTime::now(), 0, WebCore::NoTap));
}

void WebPage::requestFocusedElementInformation(WebKit::CallbackID callbackID)
{
    FocusedElementInformation info;
    if (m_focusedElement)
        getFocusedElementInformation(info);

    send(Messages::WebPageProxy::FocusedElementInformationCallback(info, callbackID));
}

#if ENABLE(DATA_INTERACTION)
void WebPage::requestDragStart(const IntPoint& clientPosition, const IntPoint& globalPosition, uint64_t allowedActions)
{
    SetForScope<WebCore::DragSourceAction> allowedActionsForScope(m_allowedDragSourceActions, static_cast<WebCore::DragSourceAction>(allowedActions));
    bool didStart = m_page->mainFrame().eventHandler().tryToBeginDragAtPoint(clientPosition, globalPosition);
    send(Messages::WebPageProxy::DidHandleDragStartRequest(didStart));
}

void WebPage::requestAdditionalItemsForDragSession(const IntPoint& clientPosition, const IntPoint& globalPosition, uint64_t allowedActions)
{
    SetForScope<WebCore::DragSourceAction> allowedActionsForScope(m_allowedDragSourceActions, static_cast<WebCore::DragSourceAction>(allowedActions));
    // To augment the platform drag session with additional items, end the current drag session and begin a new drag session with the new drag item.
    // This process is opaque to the UI process, which still maintains the old drag item in its drag session. Similarly, this persistent drag session
    // is opaque to the web process, which only sees that the current drag has ended, and that a new one is beginning.
    PlatformMouseEvent event(clientPosition, globalPosition, LeftButton, PlatformEvent::MouseMoved, 0, false, false, false, false, WallTime::now(), 0, NoTap);
    m_page->dragController().dragEnded();
    m_page->mainFrame().eventHandler().dragSourceEndedAt(event, DragOperationNone, MayExtendDragSession::Yes);

    bool didHandleDrag = m_page->mainFrame().eventHandler().tryToBeginDragAtPoint(clientPosition, globalPosition);
    send(Messages::WebPageProxy::DidHandleAdditionalDragItemsRequest(didHandleDrag));
}

void WebPage::didConcludeDrop()
{
    m_rangeForDropSnapshot = nullptr;
    m_pendingImageElementsForDropSnapshot.clear();
}

void WebPage::didConcludeEditDrag()
{
    send(Messages::WebPageProxy::WillReceiveEditDragSnapshot());

    layoutIfNeeded();

    m_pendingImageElementsForDropSnapshot.clear();

    bool waitingForAnyImageToLoad = false;
    auto frame = makeRef(m_page->focusController().focusedOrMainFrame());
    if (auto selectionRange = frame->selection().selection().toNormalizedRange()) {
        for (TextIterator iterator(selectionRange.get()); !iterator.atEnd(); iterator.advance()) {
            auto* node = iterator.node();
            if (!is<HTMLImageElement>(node))
                continue;

            auto& imageElement = downcast<HTMLImageElement>(*node);
            auto* cachedImage = imageElement.cachedImage();
            if (cachedImage && cachedImage->image() && cachedImage->image()->isNull()) {
                m_pendingImageElementsForDropSnapshot.add(&imageElement);
                waitingForAnyImageToLoad = true;
            }
        }
        auto collapsedRange = Range::create(selectionRange->ownerDocument(), selectionRange->endPosition(), selectionRange->endPosition());
        frame->selection().setSelectedRange(collapsedRange.ptr(), DOWNSTREAM, FrameSelection::ShouldCloseTyping::Yes, UserTriggered);

        m_rangeForDropSnapshot = WTFMove(selectionRange);
    }

    if (!waitingForAnyImageToLoad)
        computeAndSendEditDragSnapshot();
}

void WebPage::didFinishLoadingImageForElement(WebCore::HTMLImageElement& element)
{
    if (m_pendingImageElementsForDropSnapshot.isEmpty())
        return;

    m_pendingImageElementsForDropSnapshot.remove(&element);

    if (m_pendingImageElementsForDropSnapshot.isEmpty())
        computeAndSendEditDragSnapshot();
}

void WebPage::computeAndSendEditDragSnapshot()
{
    Optional<TextIndicatorData> textIndicatorData;
    static auto defaultTextIndicatorOptionsForEditDrag = TextIndicatorOptionIncludeSnapshotOfAllVisibleContentWithoutSelection | TextIndicatorOptionExpandClipBeyondVisibleRect | TextIndicatorOptionPaintAllContent | TextIndicatorOptionIncludeMarginIfRangeMatchesSelection | TextIndicatorOptionPaintBackgrounds | TextIndicatorOptionComputeEstimatedBackgroundColor | TextIndicatorOptionUseSelectionRectForSizing | TextIndicatorOptionIncludeSnapshotWithSelectionHighlight;
    if (auto range = std::exchange(m_rangeForDropSnapshot, nullptr)) {
        if (auto textIndicator = TextIndicator::createWithRange(*range, defaultTextIndicatorOptionsForEditDrag, TextIndicatorPresentationTransition::None, { }))
            textIndicatorData = textIndicator->data();
    }
    send(Messages::WebPageProxy::DidReceiveEditDragSnapshot(WTFMove(textIndicatorData)));
}

#endif

void WebPage::sendTapHighlightForNodeIfNecessary(uint64_t requestID, Node* node)
{
#if ENABLE(TOUCH_EVENTS)
    if (!node)
        return;

    if (m_page->isEditable() && node == m_page->mainFrame().document()->body())
        return;

    if (is<Element>(*node)) {
        ASSERT(m_page);
        m_page->mainFrame().loader().client().prefetchDNS(downcast<Element>(*node).absoluteLinkURL().host().toString());
    }

    if (is<HTMLAreaElement>(node)) {
        node = downcast<HTMLAreaElement>(node)->imageElement();
        if (!node)
            return;
    }

    Vector<FloatQuad> quads;
    if (RenderObject *renderer = node->renderer()) {
        renderer->absoluteQuads(quads);
        Color highlightColor = renderer->style().tapHighlightColor();
        if (!node->document().frame()->isMainFrame()) {
            FrameView* view = node->document().frame()->view();
            for (size_t i = 0; i < quads.size(); ++i) {
                FloatQuad& currentQuad = quads[i];
                currentQuad.setP1(view->contentsToRootView(roundedIntPoint(currentQuad.p1())));
                currentQuad.setP2(view->contentsToRootView(roundedIntPoint(currentQuad.p2())));
                currentQuad.setP3(view->contentsToRootView(roundedIntPoint(currentQuad.p3())));
                currentQuad.setP4(view->contentsToRootView(roundedIntPoint(currentQuad.p4())));
            }
        }

        RoundedRect::Radii borderRadii;
        if (is<RenderBox>(*renderer))
            borderRadii = downcast<RenderBox>(*renderer).borderRadii();

        bool nodeHasBuiltInClickHandling = is<HTMLFormControlElement>(*node) || is<HTMLAnchorElement>(*node) || is<HTMLLabelElement>(*node) || is<HTMLSummaryElement>(*node) || node->isLink();
        send(Messages::WebPageProxy::DidGetTapHighlightGeometries(requestID, highlightColor, quads, roundedIntSize(borderRadii.topLeft()), roundedIntSize(borderRadii.topRight()), roundedIntSize(borderRadii.bottomLeft()), roundedIntSize(borderRadii.bottomRight()), nodeHasBuiltInClickHandling));
    }
#else
    UNUSED_PARAM(requestID);
    UNUSED_PARAM(node);
#endif
}

void WebPage::handleTwoFingerTapAtPoint(const WebCore::IntPoint& point, OptionSet<WebKit::WebEvent::Modifier> modifiers, uint64_t requestID)
{
    FloatPoint adjustedPoint;
    Node* nodeRespondingToClick = m_page->mainFrame().nodeRespondingToClickEvents(point, adjustedPoint);
    if (!nodeRespondingToClick || !nodeRespondingToClick->renderer()) {
        send(Messages::WebPageProxy::DidNotHandleTapAsClick(roundedIntPoint(adjustedPoint)));
        return;
    }
    sendTapHighlightForNodeIfNecessary(requestID, nodeRespondingToClick);
#if ENABLE(DATA_DETECTION)
    if (is<Element>(*nodeRespondingToClick) && DataDetection::shouldCancelDefaultAction(downcast<Element>(*nodeRespondingToClick))) {
        InteractionInformationRequest request(roundedIntPoint(adjustedPoint));
        requestPositionInformation(request);
        send(Messages::WebPageProxy::DidNotHandleTapAsClick(roundedIntPoint(adjustedPoint)));
    } else
#endif
        completeSyntheticClick(*nodeRespondingToClick, adjustedPoint, modifiers, WebCore::TwoFingerTap);
}

void WebPage::handleStylusSingleTapAtPoint(const WebCore::IntPoint& point, uint64_t requestID)
{
    SetForScope<bool> userIsInteractingChange { m_userIsInteracting, true };

    auto& frame = m_page->focusController().focusedOrMainFrame();

    auto pointInDocument = frame.view()->rootViewToContents(point);
    HitTestResult hitTest = frame.eventHandler().hitTestResultAtPoint(pointInDocument, HitTestRequest::ReadOnly | HitTestRequest::Active | HitTestRequest::AllowChildFrameContent);

    Node* node = hitTest.innerNonSharedNode();
    if (!node)
        return;
    auto renderer = node->renderer();
    if (!renderer)
        return;

    if (renderer->isReplaced())
        return;

    VisiblePosition position = renderer->positionForPoint(hitTest.localPoint(), nullptr);
    if (position.isNull())
        position = firstPositionInOrBeforeNode(node);

    if (position.isNull())
        return;

    auto range = Range::create(*frame.document(), position, position);
    frame.selection().setSelectedRange(range.ptr(), position.affinity(), WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
    auto image = frame.editor().insertEditableImage();
    frame.document()->setFocusedElement(image.get());
}

void WebPage::potentialTapAtPosition(uint64_t requestID, const WebCore::FloatPoint& position, bool shouldRequestMagnificationInformation)
{
    m_potentialTapNode = m_page->mainFrame().nodeRespondingToClickEvents(position, m_potentialTapLocation, m_potentialTapSecurityOrigin.get());

    if (shouldRequestMagnificationInformation && m_potentialTapNode && m_viewGestureGeometryCollector) {
        // FIXME: Could this be combined into tap highlight?
        FloatPoint origin = position;
        FloatRect renderRect;
        bool fitEntireRect;
        double viewportMinimumScale;
        double viewportMaximumScale;

        m_viewGestureGeometryCollector->computeZoomInformationForNode(*m_potentialTapNode, origin, renderRect, fitEntireRect, viewportMinimumScale, viewportMaximumScale);
        send(Messages::WebPageProxy::HandleSmartMagnificationInformationForPotentialTap(requestID, renderRect, fitEntireRect, viewportMinimumScale, viewportMaximumScale));
    }

    sendTapHighlightForNodeIfNecessary(requestID, m_potentialTapNode.get());
#if ENABLE(TOUCH_EVENTS)
    if (m_potentialTapNode && !m_potentialTapNode->allowsDoubleTapGesture())
        send(Messages::WebPageProxy::DisableDoubleTapGesturesDuringTapIfNecessary(requestID));
#endif
}

void WebPage::commitPotentialTap(OptionSet<WebEvent::Modifier> modifiers, TransactionID lastLayerTreeTransactionId, WebCore::PointerID pointerId)
{
    auto invalidTargetForSingleClick = !m_potentialTapNode;
    if (!invalidTargetForSingleClick) {
        bool targetRenders = m_potentialTapNode->renderer();
        if (!targetRenders && is<Element>(m_potentialTapNode.get()))
            targetRenders = downcast<Element>(*m_potentialTapNode).renderOrDisplayContentsStyle();
        invalidTargetForSingleClick = !targetRenders && !is<HTMLAreaElement>(m_potentialTapNode.get());
    }
    if (invalidTargetForSingleClick) {
        commitPotentialTapFailed();
        return;
    }

    FloatPoint adjustedPoint;
    Node* nodeRespondingToClick = m_page->mainFrame().nodeRespondingToClickEvents(m_potentialTapLocation, adjustedPoint, m_potentialTapSecurityOrigin.get());
    Frame* frameRespondingToClick = nodeRespondingToClick ? nodeRespondingToClick->document().frame() : nullptr;

    if (!frameRespondingToClick || lastLayerTreeTransactionId < WebFrame::fromCoreFrame(*frameRespondingToClick)->firstLayerTreeTransactionIDAfterDidCommitLoad()) {
        commitPotentialTapFailed();
        return;
    }

    if (m_potentialTapNode == nodeRespondingToClick) {
#if ENABLE(DATA_DETECTION)
        if (is<Element>(*nodeRespondingToClick) && DataDetection::shouldCancelDefaultAction(downcast<Element>(*nodeRespondingToClick))) {
            InteractionInformationRequest request(roundedIntPoint(m_potentialTapLocation));
            requestPositionInformation(request);
            commitPotentialTapFailed();
        } else
#endif
            handleSyntheticClick(*nodeRespondingToClick, adjustedPoint, modifiers, pointerId);
    } else
        commitPotentialTapFailed();

    m_potentialTapNode = nullptr;
    m_potentialTapLocation = FloatPoint();
    m_potentialTapSecurityOrigin = nullptr;
}

void WebPage::commitPotentialTapFailed()
{
    ContentChangeObserver::didCancelPotentialTap(m_page->mainFrame());
    if (!m_page->focusController().focusedOrMainFrame().selection().selection().isContentEditable())
        clearSelection();

    send(Messages::WebPageProxy::CommitPotentialTapFailed());
    send(Messages::WebPageProxy::DidNotHandleTapAsClick(roundedIntPoint(m_potentialTapLocation)));
}

void WebPage::cancelPotentialTap()
{
    ContentChangeObserver::didCancelPotentialTap(m_page->mainFrame());
    cancelPotentialTapInFrame(*m_mainFrame);
}

void WebPage::cancelPotentialTapInFrame(WebFrame& frame)
{
    if (m_potentialTapNode) {
        auto* potentialTapFrame = m_potentialTapNode->document().frame();
        if (potentialTapFrame && !potentialTapFrame->tree().isDescendantOf(frame.coreFrame()))
            return;
    }

    m_potentialTapNode = nullptr;
    m_potentialTapLocation = FloatPoint();
    m_potentialTapSecurityOrigin = nullptr;
}

void WebPage::didRecognizeLongPress()
{
    ContentChangeObserver::didRecognizeLongPress(m_page->mainFrame());
}

void WebPage::tapHighlightAtPosition(uint64_t requestID, const FloatPoint& position)
{
    Frame& mainframe = m_page->mainFrame();
    FloatPoint adjustedPoint;
    sendTapHighlightForNodeIfNecessary(requestID, mainframe.nodeRespondingToClickEvents(position, adjustedPoint));
}

void WebPage::inspectorNodeSearchMovedToPosition(const FloatPoint& position)
{
    IntPoint adjustedPoint = roundedIntPoint(position);
    Frame& mainframe = m_page->mainFrame();

    mainframe.eventHandler().mouseMoved(PlatformMouseEvent(adjustedPoint, adjustedPoint, NoButton, PlatformEvent::MouseMoved, 0, false, false, false, false, { }, 0, WebCore::NoTap));
    mainframe.document()->updateStyleIfNeeded();
}

void WebPage::inspectorNodeSearchEndedAtPosition(const FloatPoint& position)
{
    if (Node* node = m_page->mainFrame().deepestNodeAtLocation(position))
        node->inspect();
}

void WebPage::updateInputContextAfterBlurringAndRefocusingElementIfNeeded(Element& element)
{
    if (m_recentlyBlurredElement != &element || !m_isShowingInputViewForFocusedElement)
        return;

    m_hasPendingInputContextUpdateAfterBlurringAndRefocusingElement = true;
    callOnMainThread([this, protectedThis = makeRefPtr(this)] {
        if (m_hasPendingInputContextUpdateAfterBlurringAndRefocusingElement)
            send(Messages::WebPageProxy::UpdateInputContextAfterBlurringAndRefocusingElement());
        m_hasPendingInputContextUpdateAfterBlurringAndRefocusingElement = false;
    });
}

void WebPage::blurFocusedElement()
{
    if (!m_focusedElement)
        return;

    m_focusedElement->blur();
}

void WebPage::setIsShowingInputViewForFocusedElement(bool showingInputView)
{
    m_isShowingInputViewForFocusedElement = showingInputView;
}

void WebPage::setFocusedElementValue(const String& value)
{
    // FIXME: should also handle the case of HTMLSelectElement.
    if (is<HTMLInputElement>(m_focusedElement.get()))
        downcast<HTMLInputElement>(*m_focusedElement).setValue(value, DispatchInputAndChangeEvent);
}

void WebPage::setFocusedElementValueAsNumber(double value)
{
    if (is<HTMLInputElement>(m_focusedElement.get()))
        downcast<HTMLInputElement>(*m_focusedElement).setValueAsNumber(value, DispatchInputAndChangeEvent);
}

void WebPage::setFocusedElementSelectedIndex(uint32_t index, bool allowMultipleSelection)
{
    if (is<HTMLSelectElement>(m_focusedElement.get()))
        downcast<HTMLSelectElement>(*m_focusedElement).optionSelectedByUser(index, true, allowMultipleSelection);
}

void WebPage::showInspectorHighlight(const WebCore::Highlight& highlight)
{
    send(Messages::WebPageProxy::ShowInspectorHighlight(highlight));
}

void WebPage::hideInspectorHighlight()
{
    send(Messages::WebPageProxy::HideInspectorHighlight());
}

void WebPage::showInspectorIndication()
{
    send(Messages::WebPageProxy::ShowInspectorIndication());
}

void WebPage::hideInspectorIndication()
{
    send(Messages::WebPageProxy::HideInspectorIndication());
}

void WebPage::enableInspectorNodeSearch()
{
    send(Messages::WebPageProxy::EnableInspectorNodeSearch());
}

void WebPage::disableInspectorNodeSearch()
{
    send(Messages::WebPageProxy::DisableInspectorNodeSearch());
}

void WebPage::setForceAlwaysUserScalable(bool userScalable)
{
    m_forceAlwaysUserScalable = userScalable;
    m_viewportConfiguration.setForceAlwaysUserScalable(userScalable);
}

static IntRect elementBoundsInFrame(const Frame& frame, const Element& focusedElement)
{
    frame.document()->updateLayoutIgnorePendingStylesheets();
    
    if (focusedElement.hasTagName(HTMLNames::textareaTag) || focusedElement.hasTagName(HTMLNames::inputTag) || focusedElement.hasTagName(HTMLNames::selectTag))
        return WebPage::absoluteInteractionBoundsForElement(focusedElement);

    if (auto* rootEditableElement = focusedElement.rootEditableElement())
        return WebPage::absoluteInteractionBoundsForElement(*rootEditableElement);

    return { };
}

static IntPoint constrainPoint(const IntPoint& point, const Frame& frame, const Element& focusedElement)
{
    ASSERT(&focusedElement.document() == frame.document());
    const int DEFAULT_CONSTRAIN_INSET = 2;
    IntRect innerFrame = elementBoundsInFrame(frame, focusedElement);
    IntPoint constrainedPoint = point;

    int minX = innerFrame.x() + DEFAULT_CONSTRAIN_INSET;
    int maxX = innerFrame.maxX() - DEFAULT_CONSTRAIN_INSET;
    int minY = innerFrame.y() + DEFAULT_CONSTRAIN_INSET;
    int maxY = innerFrame.maxY() - DEFAULT_CONSTRAIN_INSET;

    if (point.x() < minX)
        constrainedPoint.setX(minX);
    else if (point.x() > maxX)
        constrainedPoint.setX(maxX);

    if (point.y() < minY)
        constrainedPoint.setY(minY);
    else if (point.y() >= maxY)
        constrainedPoint.setY(maxY);
                    
    return constrainedPoint;
}

void WebPage::selectWithGesture(const IntPoint& point, uint32_t granularity, uint32_t gestureType, uint32_t gestureState, bool isInteractingWithFocusedElement, CallbackID callbackID)
{
    if (static_cast<GestureRecognizerState>(gestureState) == GestureRecognizerState::Began)
        setFocusedFrameBeforeSelectingTextAtLocation(point);

    auto& frame = m_page->focusController().focusedOrMainFrame();
    VisiblePosition position = visiblePositionInFocusedNodeForPoint(frame, point, isInteractingWithFocusedElement);

    if (position.isNull()) {
        send(Messages::WebPageProxy::GestureCallback(point, gestureType, gestureState, 0, callbackID));
        return;
    }
    RefPtr<Range> range;
    SelectionFlags flags = None;
    GestureRecognizerState wkGestureState = static_cast<GestureRecognizerState>(gestureState);
    switch (static_cast<GestureType>(gestureType)) {
    case GestureType::PhraseBoundary:
    {
        if (!frame.editor().hasComposition())
            break;
        RefPtr<Range> markedRange = frame.editor().compositionRange();
        if (position < markedRange->startPosition())
            position = markedRange->startPosition();
        if (position > markedRange->endPosition())
            position = markedRange->endPosition();
        if (wkGestureState != GestureRecognizerState::Began)
            flags = distanceBetweenPositions(markedRange->startPosition(), frame.selection().selection().start()) != distanceBetweenPositions(markedRange->startPosition(), position) ? PhraseBoundaryChanged : None;
        else
            flags = PhraseBoundaryChanged;
        range = Range::create(*frame.document(), position, position);
    }
        break;

    case GestureType::OneFingerTap:
    {
        VisiblePosition result;
        // move the position at the end of the word
        if (atBoundaryOfGranularity(position, LineGranularity, DirectionForward)) {
            // Don't cross line boundaries.
            result = position;
        } else if (withinTextUnitOfGranularity(position, WordGranularity, DirectionForward)) {
            // The position lies within a word.
            RefPtr<Range> wordRange = enclosingTextUnitOfGranularity(position, WordGranularity, DirectionForward);
            if (wordRange) {
                result = wordRange->startPosition();
                if (distanceBetweenPositions(position, result) > 1)
                    result = wordRange->endPosition();
            }
            flags = WordIsNearTap;
        } else if (atBoundaryOfGranularity(position, WordGranularity, DirectionBackward)) {
            // The position is at the end of a word.
            result = position;
        } else {
            // The position is not within a word.
            // Go to the next boundary.
            result = positionOfNextBoundaryOfGranularity(position, WordGranularity, DirectionForward);

            // If there is no such boundary we go to the end of the element.
            if (result.isNull())
                result = endOfEditableContent(position);
        }
        if (result.isNotNull())
            range = Range::create(*frame.document(), result, result);
    }
        break;

    case GestureType::Loupe:
        if (position.rootEditableElement())
            range = Range::create(*frame.document(), position, position);
        else
#if !PLATFORM(MACCATALYST)
            range = wordRangeFromPosition(position);
#else
            switch (wkGestureState) {
            case GestureRecognizerState::Began:
                m_startingGestureRange = Range::create(*frame.document(), position, position);
                break;
            case GestureRecognizerState::Changed:
                if (m_startingGestureRange) {
                    if (m_startingGestureRange->startPosition() < position)
                        range = Range::create(*frame.document(), m_startingGestureRange->startPosition(), position);
                    else
                        range = Range::create(*frame.document(), position, m_startingGestureRange->startPosition());
                }
                break;
            case GestureRecognizerState::Ended:
            case GestureRecognizerState::Cancelled:
                m_startingGestureRange = nullptr;
                break;
            case GestureRecognizerState::Failed:
            case GestureRecognizerState::Possible:
                ASSERT_NOT_REACHED();
                break;
            }
#endif
        break;

    case GestureType::TapAndAHalf:
        switch (wkGestureState) {
        case GestureRecognizerState::Began:
            range = wordRangeFromPosition(position);
            m_currentWordRange = range ? RefPtr<Range>(Range::create(*frame.document(), range->startPosition(), range->endPosition())) : nullptr;
            break;
        case GestureRecognizerState::Changed:
            if (!m_currentWordRange)
                break;
            range = Range::create(*frame.document(), m_currentWordRange->startPosition(), m_currentWordRange->endPosition());
            if (position < range->startPosition())
                range->setStart(position.deepEquivalent());
            if (position > range->endPosition())
                range->setEnd(position.deepEquivalent());
            break;
        case GestureRecognizerState::Ended:
        case GestureRecognizerState::Cancelled:
            m_currentWordRange = nullptr;
            break;
        case GestureRecognizerState::Failed:
        case GestureRecognizerState::Possible:
            ASSERT_NOT_REACHED();
        }
        break;

    case GestureType::OneFingerDoubleTap:
        if (atBoundaryOfGranularity(position, LineGranularity, DirectionForward)) {
            // Double-tap at end of line only places insertion point there.
            // This helps to get the callout for pasting at ends of lines,
            // paragraphs, and documents.
            range = Range::create(*frame.document(), position, position);
         } else
            range = wordRangeFromPosition(position);
        break;

    case GestureType::TwoFingerSingleTap:
        // Single tap with two fingers selects the entire paragraph.
        range = enclosingTextUnitOfGranularity(position, ParagraphGranularity, DirectionForward);
        break;

    case GestureType::OneFingerTripleTap:
        if (atBoundaryOfGranularity(position, LineGranularity, DirectionForward)) {
            // Triple-tap at end of line only places insertion point there.
            // This helps to get the callout for pasting at ends of lines,
            // paragraphs, and documents.
            range = Range::create(*frame.document(), position, position);
        } else
            range = enclosingTextUnitOfGranularity(position, ParagraphGranularity, DirectionForward);
        break;

    default:
        break;
    }
    if (range)
        frame.selection().setSelectedRange(range.get(), position.affinity(), WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);

    send(Messages::WebPageProxy::GestureCallback(point, gestureType, gestureState, static_cast<uint32_t>(flags), callbackID));
}

static RefPtr<Range> rangeForPointInRootViewCoordinates(Frame& frame, const IntPoint& pointInRootViewCoordinates, bool baseIsStart)
{
    VisibleSelection existingSelection = frame.selection().selection();
    VisiblePosition selectionStart = existingSelection.visibleStart();
    VisiblePosition selectionEnd = existingSelection.visibleEnd();

    auto pointInDocument = frame.view()->rootViewToContents(pointInRootViewCoordinates);

    if (baseIsStart) {
        int startY = selectionStart.absoluteCaretBounds().center().y();
        if (pointInDocument.y() < startY)
            pointInDocument.setY(startY);
    } else {
        int endY = selectionEnd.absoluteCaretBounds().center().y();
        if (pointInDocument.y() > endY)
            pointInDocument.setY(endY);
    }
    
    VisiblePosition result;
    RefPtr<Range> range;
    
    HitTestResult hitTest = frame.eventHandler().hitTestResultAtPoint(pointInDocument, HitTestRequest::ReadOnly | HitTestRequest::Active | HitTestRequest::AllowChildFrameContent);
    if (hitTest.targetNode())
        result = frame.eventHandler().selectionExtentRespectingEditingBoundary(frame.selection().selection(), hitTest.localPoint(), hitTest.targetNode()).deepEquivalent();
    else
        result = frame.visiblePositionForPoint(pointInDocument).deepEquivalent();
    
    if (baseIsStart) {
        if (comparePositions(result, selectionStart) <= 0)
            result = selectionStart.next();
        else if (&selectionStart.deepEquivalent().anchorNode()->treeScope() != &hitTest.targetNode()->treeScope())
            result = VisibleSelection::adjustPositionForEnd(result.deepEquivalent(), selectionStart.deepEquivalent().containerNode());
        
        if (result.isNotNull())
            range = Range::create(*frame.document(), selectionStart, result);
    } else {
        if (comparePositions(selectionEnd, result) <= 0)
            result = selectionEnd.previous();
        else if (&hitTest.targetNode()->treeScope() != &selectionEnd.deepEquivalent().anchorNode()->treeScope())
            result = VisibleSelection::adjustPositionForStart(result.deepEquivalent(), selectionEnd.deepEquivalent().containerNode());
        
        if (result.isNotNull())
            range = Range::create(*frame.document(), result.deepEquivalent(), selectionEnd);
    }
    
    return range;
}

static RefPtr<Range> rangeAtWordBoundaryForPosition(Frame* frame, const VisiblePosition& position, bool baseIsStart, SelectionDirection direction)
{
    SelectionDirection sameDirection = baseIsStart ? DirectionForward : DirectionBackward;
    SelectionDirection oppositeDirection = baseIsStart ? DirectionBackward : DirectionForward;
    VisiblePosition base = baseIsStart ? frame->selection().selection().visibleStart() : frame->selection().selection().visibleEnd();
    VisiblePosition extent = baseIsStart ? frame->selection().selection().visibleEnd() : frame->selection().selection().visibleStart();
    VisiblePosition initialExtent = position;

    if (atBoundaryOfGranularity(extent, WordGranularity, sameDirection)) {
        // This is a word boundary. Leave selection where it is.
        return nullptr;
    }

    if (atBoundaryOfGranularity(extent, WordGranularity, oppositeDirection)) {
        // This is a word boundary in the wrong direction. Nudge the selection to a character before proceeding.
        extent = baseIsStart ? extent.previous() : extent.next();
    }

    // Extend to the boundary of the word.

    VisiblePosition wordBoundary = positionOfNextBoundaryOfGranularity(extent, WordGranularity, sameDirection);
    if (wordBoundary.isNotNull()
        && atBoundaryOfGranularity(wordBoundary, WordGranularity, sameDirection)
        && initialExtent != wordBoundary) {
        extent = wordBoundary;
        return (base < extent) ? Range::create(*frame->document(), base, extent) : Range::create(*frame->document(), extent, base);
    }
    // Conversely, if the initial extent equals the current word boundary, then
    // run the rest of this function to see if the selection should extend
    // the other direction to the other word.

    // If this is where the extent was initially, then iterate in the other direction in the document until we hit the next word.
    while (extent.isNotNull()
        && !atBoundaryOfGranularity(extent, WordGranularity, sameDirection)
        && extent != base
        && !atBoundaryOfGranularity(extent, LineGranularity, sameDirection)
        && !atBoundaryOfGranularity(extent, LineGranularity, oppositeDirection)) {
        extent = baseIsStart ? extent.next() : extent.previous();
    }

    // Don't let the smart extension make the extent equal the base.
    // Expand out to word boundary.
    if (extent.isNull() || extent == base)
        extent = wordBoundary;
    if (extent.isNull())
        return nullptr;

    return (base < extent) ? Range::create(*frame->document(), base, extent) : Range::create(*frame->document(), extent, base);
}

IntRect WebPage::rootViewBoundsForElement(const Element& element)
{
    auto* frame = element.document().frame();
    if (!frame)
        return { };

    auto* view = frame->view();
    if (!view)
        return { };

    auto* renderer = element.renderer();
    if (!renderer)
        return { };

    return view->contentsToRootView(renderer->absoluteBoundingBoxRect());
}

IntRect WebPage::absoluteInteractionBoundsForElement(const Element& element)
{
    auto* frame = element.document().frame();
    if (!frame)
        return { };

    auto* view = frame->view();
    if (!view)
        return { };

    auto* renderer = element.renderer();
    if (!renderer)
        return { };

    if (is<RenderBox>(*renderer)) {
        auto& box = downcast<RenderBox>(*renderer);

        FloatRect rect;
        // FIXME: want borders or not?
        if (box.style().isOverflowVisible())
            rect = box.layoutOverflowRect();
        else
            rect = box.clientBoxRect();
        return box.localToAbsoluteQuad(rect).enclosingBoundingBox();
    }

    auto& style = renderer->style();
    FloatRect boundingBox = renderer->absoluteBoundingBoxRect(true /* use transforms*/);
    // This is wrong. It's subtracting borders after converting to absolute coords on something that probably doesn't represent a rectangular element.
    boundingBox.move(style.borderLeftWidth(), style.borderTopWidth());
    boundingBox.setWidth(boundingBox.width() - style.borderLeftWidth() - style.borderRightWidth());
    boundingBox.setHeight(boundingBox.height() - style.borderBottomWidth() - style.borderTopWidth());
    return enclosingIntRect(boundingBox);
}

IntRect WebPage::rootViewInteractionBoundsForElement(const Element& element)
{
    auto* frame = element.document().frame();
    if (!frame)
        return { };

    auto* view = frame->view();
    if (!view)
        return { };

    return view->contentsToRootView(absoluteInteractionBoundsForElement(element));
}

void WebPage::clearSelection()
{
    m_startingGestureRange = nullptr;
    m_page->focusController().focusedOrMainFrame().selection().clear();
}

void WebPage::dispatchSyntheticMouseEventsForSelectionGesture(SelectionTouch touch, const IntPoint& point)
{
    auto frame = makeRef(m_page->focusController().focusedOrMainFrame());
    if (!frame->selection().selection().isContentEditable())
        return;

    IntRect focusedElementRect;
    if (m_focusedElement)
        focusedElementRect = rootViewInteractionBoundsForElement(*m_focusedElement);

    if (focusedElementRect.isEmpty())
        return;

    auto adjustedPoint = point.constrainedBetween(focusedElementRect.minXMinYCorner(), focusedElementRect.maxXMaxYCorner());
    auto& eventHandler = m_page->mainFrame().eventHandler();
    switch (touch) {
    case SelectionTouch::Started:
        eventHandler.handleMousePressEvent({ adjustedPoint, adjustedPoint, LeftButton, PlatformEvent::MousePressed, 1, false, false, false, false, WallTime::now(), WebCore::ForceAtClick, NoTap });
        break;
    case SelectionTouch::Moved:
        eventHandler.dispatchSyntheticMouseMove({ adjustedPoint, adjustedPoint, LeftButton, PlatformEvent::MouseMoved, 0, false, false, false, false, WallTime::now(), WebCore::ForceAtClick, NoTap });
        break;
    case SelectionTouch::Ended:
    case SelectionTouch::EndedMovingForward:
    case SelectionTouch::EndedMovingBackward:
    case SelectionTouch::EndedNotMoving:
        eventHandler.handleMouseReleaseEvent({ adjustedPoint, adjustedPoint, LeftButton, PlatformEvent::MouseReleased, 1, false, false, false, false, WallTime::now(), WebCore::ForceAtClick, NoTap });
        break;
    }
}

void WebPage::updateSelectionWithTouches(const IntPoint& point, uint32_t touches, bool baseIsStart, CallbackID callbackID)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    IntPoint pointInDocument = frame.view()->rootViewToContents(point);
    VisiblePosition position = frame.visiblePositionForPoint(pointInDocument);
    if (position.isNull()) {
        send(Messages::WebPageProxy::TouchesCallback(point, touches, 0, callbackID));
        return;
    }

    RefPtr<Range> range;
    VisiblePosition result;
    SelectionFlags flags = None;

    auto selectionTouch = static_cast<SelectionTouch>(touches);
    if (shouldDispatchSyntheticMouseEventsWhenModifyingSelection())
        dispatchSyntheticMouseEventsForSelectionGesture(selectionTouch, point);

    switch (selectionTouch) {
    case SelectionTouch::Started:
    case SelectionTouch::EndedNotMoving:
        break;
    
    case SelectionTouch::Ended:
        if (frame.selection().selection().isContentEditable()) {
            result = closestWordBoundaryForPosition(position);
            if (result.isNotNull())
                range = Range::create(*frame.document(), result, result);
        } else
            range = rangeForPointInRootViewCoordinates(frame, point, baseIsStart);
        break;

    case SelectionTouch::EndedMovingForward:
        range = rangeAtWordBoundaryForPosition(&frame, position, baseIsStart, DirectionForward);
        break;
        
    case SelectionTouch::EndedMovingBackward:
        range = rangeAtWordBoundaryForPosition(&frame, position, baseIsStart, DirectionBackward);
        break;

    case SelectionTouch::Moved:
        range = rangeForPointInRootViewCoordinates(frame, point, baseIsStart);
        break;
    }
    if (range)
        frame.selection().setSelectedRange(range.get(), position.affinity(), WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);

    send(Messages::WebPageProxy::TouchesCallback(point, touches, flags, callbackID));
}

void WebPage::selectWithTwoTouches(const WebCore::IntPoint& from, const WebCore::IntPoint& to, uint32_t gestureType, uint32_t gestureState, CallbackID callbackID)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    VisiblePosition fromPosition = frame.visiblePositionForPoint(frame.view()->rootViewToContents(from));
    VisiblePosition toPosition = frame.visiblePositionForPoint(frame.view()->rootViewToContents(to));
    RefPtr<Range> range;
    if (fromPosition.isNotNull() && toPosition.isNotNull()) {
        if (fromPosition < toPosition)
            range = Range::create(*frame.document(), fromPosition, toPosition);
        else
            range = Range::create(*frame.document(), toPosition, fromPosition);
        frame.selection().setSelectedRange(range.get(), fromPosition.affinity(), WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
    }

    // We can use the same callback for the gestures with one point.
    send(Messages::WebPageProxy::GestureCallback(from, gestureType, gestureState, 0, callbackID));
}

void WebPage::extendSelection(uint32_t granularity)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    // For the moment we handle only WordGranularity.
    if (granularity != WordGranularity || !frame.selection().isCaret())
        return;

    VisiblePosition position = frame.selection().selection().start();
    auto wordRange = wordRangeFromPosition(position);
    if (!wordRange)
        return;

    IntPoint endLocationForSyntheticMouseEvents;
    bool shouldDispatchMouseEvents = shouldDispatchSyntheticMouseEventsWhenModifyingSelection();
    if (shouldDispatchMouseEvents) {
        auto startLocationForSyntheticMouseEvents = frame.view()->contentsToRootView(VisiblePosition(wordRange->startPosition()).absoluteCaretBounds()).center();
        endLocationForSyntheticMouseEvents = frame.view()->contentsToRootView(VisiblePosition(wordRange->endPosition()).absoluteCaretBounds()).center();
        dispatchSyntheticMouseEventsForSelectionGesture(SelectionTouch::Started, startLocationForSyntheticMouseEvents);
        dispatchSyntheticMouseEventsForSelectionGesture(SelectionTouch::Moved, endLocationForSyntheticMouseEvents);
    }

    frame.selection().setSelectedRange(wordRange.get(), position.affinity(), WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);

    if (shouldDispatchMouseEvents)
        dispatchSyntheticMouseEventsForSelectionGesture(SelectionTouch::Ended, endLocationForSyntheticMouseEvents);
}

void WebPage::platformDidSelectAll()
{
    if (!shouldDispatchSyntheticMouseEventsWhenModifyingSelection())
        return;

    auto frame = makeRef(m_page->focusController().focusedOrMainFrame());
    auto startCaretRect = frame->view()->contentsToRootView(VisiblePosition(frame->selection().selection().start()).absoluteCaretBounds());
    auto endCaretRect = frame->view()->contentsToRootView(VisiblePosition(frame->selection().selection().end()).absoluteCaretBounds());
    dispatchSyntheticMouseEventsForSelectionGesture(SelectionTouch::Started, startCaretRect.center());
    dispatchSyntheticMouseEventsForSelectionGesture(SelectionTouch::Moved, endCaretRect.center());
    dispatchSyntheticMouseEventsForSelectionGesture(SelectionTouch::Ended, endCaretRect.center());
}

void WebPage::selectWordBackward()
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    if (!frame.selection().isCaret())
        return;

    VisiblePosition position = frame.selection().selection().start();
    VisiblePosition startPosition = positionOfNextBoundaryOfGranularity(position, WordGranularity, DirectionBackward);
    if (startPosition.isNotNull() && startPosition != position)
        frame.selection().setSelectedRange(Range::create(*frame.document(), startPosition, position).ptr(), position.affinity(), WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
}

void WebPage::moveSelectionByOffset(int32_t offset, CallbackID callbackID)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    
    VisiblePosition startPosition = frame.selection().selection().end();
    if (startPosition.isNull())
        return;
    SelectionDirection direction = offset < 0 ? DirectionBackward : DirectionForward;
    VisiblePosition position = startPosition;
    for (int i = 0; i < abs(offset); ++i) {
        position = positionOfNextBoundaryOfGranularity(position, CharacterGranularity, direction);
        if (position.isNull())
            break;
    }
    if (position.isNotNull() && startPosition != position)
        frame.selection().setSelectedRange(Range::create(*frame.document(), position, position).ptr(), position.affinity(), WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
    send(Messages::WebPageProxy::VoidCallback(callbackID));
}
    
void WebPage::startAutoscrollAtPosition(const WebCore::FloatPoint& positionInWindow)
{
    if (m_focusedElement && m_focusedElement->renderer()) {
        m_page->mainFrame().eventHandler().startSelectionAutoscroll(m_focusedElement->renderer(), positionInWindow);
        return;
    }
    
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    VisibleSelection selection = frame.selection().selection();
    if (!selection.isRange())
        return;
    RefPtr<Range> range = frame.selection().toNormalizedRange();
    if (!range)
        return;
    auto* renderer = range->startContainer().renderer();
    if (!renderer)
        return;

    m_page->mainFrame().eventHandler().startSelectionAutoscroll(renderer, positionInWindow);
}
    
void WebPage::cancelAutoscroll()
{
    m_page->mainFrame().eventHandler().cancelSelectionAutoscroll();
}

void WebPage::requestEvasionRectsAboveSelection(CompletionHandler<void(const Vector<FloatRect>&)>&& reply)
{
    auto& frame = m_page->focusController().focusedOrMainFrame();
    auto frameView = makeRefPtr(frame.view());
    if (!frameView) {
        reply({ });
        return;
    }

    auto& selection = frame.selection().selection();
    if (selection.isNone()) {
        reply({ });
        return;
    }

    auto selectedRange = selection.toNormalizedRange();
    if (!selectedRange) {
        reply({ });
        return;
    }

    if (!m_focusedElement || !m_focusedElement->renderer() || isTransparentOrFullyClipped(*m_focusedElement)) {
        reply({ });
        return;
    }

    float scaleFactor = pageScaleFactor();
    const double factorOfContentArea = 0.5;
    auto unobscuredContentArea = m_page->mainFrame().view()->unobscuredContentRect().area();
    if (unobscuredContentArea.hasOverflowed()) {
        reply({ });
        return;
    }

    double contextMenuAreaLimit = factorOfContentArea * scaleFactor * unobscuredContentArea.unsafeGet();

    FloatRect selectionBoundsInRootViewCoordinates;
    if (selection.isRange())
        selectionBoundsInRootViewCoordinates = frameView->contentsToRootView(selectedRange->absoluteBoundingBox());
    else
        selectionBoundsInRootViewCoordinates = frameView->contentsToRootView(frame.selection().absoluteCaretBounds());

    auto centerOfTargetBounds = selectionBoundsInRootViewCoordinates.center();
    FloatPoint centerTopInRootViewCoordinates { centerOfTargetBounds.x(), selectionBoundsInRootViewCoordinates.y() };

    auto clickableNonEditableNode = [&] (const FloatPoint& locationInRootViewCoordinates) -> Node* {
        FloatPoint adjustedPoint;
        auto* hitNode = m_page->mainFrame().nodeRespondingToClickEvents(locationInRootViewCoordinates, adjustedPoint);
        if (!hitNode || is<HTMLBodyElement>(hitNode) || is<Document>(hitNode) || hitNode->hasEditableStyle())
            return nullptr;

        return hitNode;
    };

    // This heuristic attempts to find a list of rects to avoid when showing the callout menu on iOS.
    // First, hit-test several points above the bounds of the selection rect in search of clickable nodes that are not editable.
    // Secondly, hit-test several points around the edges of the selection rect and exclude any nodes found in the first round of
    // hit-testing if these nodes are also reachable by moving outwards from the left, right, or bottom edges of the selection.
    // Additionally, exclude any hit-tested nodes that are either very large relative to the size of the root view, or completely
    // encompass the selection bounds. The resulting rects are the bounds of these hit-tested nodes in root view coordinates.
    HashSet<Ref<Node>> hitTestedNodes;
    Vector<FloatRect> rectsToAvoidInRootViewCoordinates;
    const Vector<FloatPoint, 5> offsetsForHitTesting {{ -30, -50 }, { 30, -50 }, { -60, -35 }, { 60, -35 }, { 0, -20 }};
    for (auto offset : offsetsForHitTesting) {
        offset.scale(1 / scaleFactor);
        if (auto* hitNode = clickableNonEditableNode(centerTopInRootViewCoordinates + offset))
            hitTestedNodes.add(*hitNode);
    }

    const float marginForHitTestingSurroundingNodes = 80 / scaleFactor;
    Vector<FloatPoint, 3> exclusionHitTestLocations {
        { selectionBoundsInRootViewCoordinates.x() - marginForHitTestingSurroundingNodes, centerOfTargetBounds.y() },
        { centerOfTargetBounds.x(), selectionBoundsInRootViewCoordinates.maxY() + marginForHitTestingSurroundingNodes },
        { selectionBoundsInRootViewCoordinates.maxX() + marginForHitTestingSurroundingNodes, centerOfTargetBounds.y() }
    };

    for (auto& location : exclusionHitTestLocations) {
        if (auto* nodeToExclude = clickableNonEditableNode(location))
            hitTestedNodes.remove(*nodeToExclude);
    }

    for (auto& node : hitTestedNodes) {
        auto frameView = makeRefPtr(node->document().view());
        auto* renderer = node->renderer();
        if (!renderer || !frameView)
            continue;

        auto bounds = frameView->contentsToRootView(renderer->absoluteBoundingBoxRect());
        auto area = bounds.area();
        if (area.hasOverflowed() || area.unsafeGet() > contextMenuAreaLimit)
            continue;

        if (bounds.contains(enclosingIntRect(selectionBoundsInRootViewCoordinates)))
            continue;

        rectsToAvoidInRootViewCoordinates.append(WTFMove(bounds));
    }

    reply(WTFMove(rectsToAvoidInRootViewCoordinates));
}

void WebPage::getRectsForGranularityWithSelectionOffset(uint32_t granularity, int32_t offset, CallbackID callbackID)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    VisibleSelection selection = m_storedSelectionForAccessibility.isNone() ? frame.selection().selection() : m_storedSelectionForAccessibility;
    VisiblePosition selectionStart = selection.visibleStart();

    if (selectionStart.isNull()) {
        send(Messages::WebPageProxy::SelectionRectsCallback({ }, callbackID));
        return;
    }

    auto position = visiblePositionForPositionWithOffset(selectionStart, offset);
    SelectionDirection direction = offset < 0 ? DirectionBackward : DirectionForward;

    auto range = enclosingTextUnitOfGranularity(position, static_cast<WebCore::TextGranularity>(granularity), direction);
    if (!range || range->collapsed()) {
        send(Messages::WebPageProxy::SelectionRectsCallback({ }, callbackID));
        return;
    }

    Vector<WebCore::SelectionRect> selectionRects;
    range->collectSelectionRectsWithoutUnionInteriorLines(selectionRects);
    convertSelectionRectsToRootView(frame.view(), selectionRects);
    send(Messages::WebPageProxy::SelectionRectsCallback(selectionRects, callbackID));
}

void WebPage::storeSelectionForAccessibility(bool shouldStore)
{
    if (!shouldStore)
        m_storedSelectionForAccessibility = VisibleSelection();
    else {
        Frame& frame = m_page->focusController().focusedOrMainFrame();
        m_storedSelectionForAccessibility = frame.selection().selection();
    }
}

static RefPtr<Range> rangeNearPositionMatchesText(const VisiblePosition& position, RefPtr<Range> originalRange, const String& matchText, RefPtr<Range> selectionRange)
{
    auto range = Range::create(selectionRange->ownerDocument(), selectionRange->startPosition(), position.deepEquivalent().parentAnchoredEquivalent());
    unsigned targetOffset = TextIterator::rangeLength(range.ptr(), true);
    return findClosestPlainText(*selectionRange.get(), matchText, { }, targetOffset);
}

void WebPage::getRectsAtSelectionOffsetWithText(int32_t offset, const String& text, CallbackID callbackID)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    uint32_t length = text.length();
    VisibleSelection selection = m_storedSelectionForAccessibility.isNone() ? frame.selection().selection() : m_storedSelectionForAccessibility;
    VisiblePosition selectionStart = selection.visibleStart();
    VisiblePosition selectionEnd = selection.visibleEnd();

    if (selectionStart.isNull() || selectionEnd.isNull()) {
        send(Messages::WebPageProxy::SelectionRectsCallback({ }, callbackID));
        return;
    }

    auto startPosition = visiblePositionForPositionWithOffset(selectionStart, offset);
    auto endPosition = visiblePositionForPositionWithOffset(startPosition, length);
    auto range = Range::create(*frame.document(), startPosition, endPosition);

    if (range->collapsed()) {
        send(Messages::WebPageProxy::SelectionRectsCallback({ }, callbackID));
        return;
    }

    String rangeText = plainTextReplacingNoBreakSpace(range.ptr(), TextIteratorDefaultBehavior, true);
    if (rangeText != text) {
        auto selectionRange = selection.toNormalizedRange();
        // Try to search for a range which is the closest to the position within the selection range that matches the passed in text.
        if (auto wordRange = rangeNearPositionMatchesText(startPosition, range.ptr(), text, selectionRange)) {
            if (!wordRange->collapsed())
                range = *wordRange;
        }
    }

    Vector<WebCore::SelectionRect> selectionRects;
    range->collectSelectionRectsWithoutUnionInteriorLines(selectionRects);
    convertSelectionRectsToRootView(frame.view(), selectionRects);
    send(Messages::WebPageProxy::SelectionRectsCallback(selectionRects, callbackID));
}

VisiblePosition WebPage::visiblePositionInFocusedNodeForPoint(const Frame& frame, const IntPoint& point, bool isInteractingWithFocusedElement)
{
    IntPoint adjustedPoint(frame.view()->rootViewToContents(point));
    IntPoint constrainedPoint = m_focusedElement && isInteractingWithFocusedElement ? constrainPoint(adjustedPoint, frame, *m_focusedElement) : adjustedPoint;
    return frame.visiblePositionForPoint(constrainedPoint);
}

void WebPage::selectPositionAtPoint(const WebCore::IntPoint& point, bool isInteractingWithFocusedElement, CallbackID callbackID)
{
    auto& frame = m_page->focusController().focusedOrMainFrame();
    VisiblePosition position = visiblePositionInFocusedNodeForPoint(frame, point, isInteractingWithFocusedElement);
    
    if (position.isNotNull())
        frame.selection().setSelectedRange(Range::create(*frame.document(), position, position).ptr(), position.affinity(), WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
    send(Messages::WebPageProxy::VoidCallback(callbackID));
}

void WebPage::selectPositionAtBoundaryWithDirection(const WebCore::IntPoint& point, uint32_t granularity, uint32_t direction, bool isInteractingWithFocusedElement, CallbackID callbackID)
{
    auto& frame = m_page->focusController().focusedOrMainFrame();
    VisiblePosition position = visiblePositionInFocusedNodeForPoint(frame, point, isInteractingWithFocusedElement);

    if (position.isNotNull()) {
        position = positionOfNextBoundaryOfGranularity(position, static_cast<WebCore::TextGranularity>(granularity), static_cast<SelectionDirection>(direction));
        if (position.isNotNull())
            frame.selection().setSelectedRange(Range::create(*frame.document(), position, position).ptr(), UPSTREAM, WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
    }
    send(Messages::WebPageProxy::VoidCallback(callbackID));
}

void WebPage::moveSelectionAtBoundaryWithDirection(uint32_t granularity, uint32_t direction, CallbackID callbackID)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    
    if (!frame.selection().selection().isNone()) {
        bool isForward = (direction == DirectionForward || direction == DirectionRight);
        VisiblePosition position = (isForward) ? frame.selection().selection().visibleEnd() : frame.selection().selection().visibleStart();
        position = positionOfNextBoundaryOfGranularity(position, static_cast<WebCore::TextGranularity>(granularity), static_cast<SelectionDirection>(direction));
        if (position.isNotNull())
            frame.selection().setSelectedRange(Range::create(*frame.document(), position, position).ptr(), isForward? UPSTREAM : DOWNSTREAM, WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
    }
    send(Messages::WebPageProxy::VoidCallback(callbackID));
}

RefPtr<Range> WebPage::rangeForGranularityAtPoint(Frame& frame, const WebCore::IntPoint& point, uint32_t granularity, bool isInteractingWithFocusedElement)
{
    VisiblePosition position = visiblePositionInFocusedNodeForPoint(frame, point, isInteractingWithFocusedElement);

    RefPtr<Range> range;
    switch (static_cast<WebCore::TextGranularity>(granularity)) {
    case WordGranularity:
        range = wordRangeFromPosition(position);
        break;
    case SentenceGranularity:
        range = enclosingTextUnitOfGranularity(position, SentenceGranularity, DirectionForward);
        break;
    case ParagraphGranularity:
        range = enclosingTextUnitOfGranularity(position, ParagraphGranularity, DirectionForward);
        break;
    case DocumentGranularity:
        frame.selection().selectAll();
        break;
    default:
        break;
    }
    return range;
}

static inline bool rectIsTooBigForSelection(const IntRect& blockRect, const Frame& frame)
{
    const float factor = 0.97;
    return blockRect.height() > frame.view()->unobscuredContentRect().height() * factor;
}

void WebPage::setFocusedFrameBeforeSelectingTextAtLocation(const IntPoint& point)
{
    auto result = m_page->mainFrame().eventHandler().hitTestResultAtPoint(point, HitTestRequest::ReadOnly | HitTestRequest::Active | HitTestRequest::DisallowUserAgentShadowContent | HitTestRequest::AllowChildFrameContent);
    auto* hitNode = result.innerNode();
    if (hitNode && hitNode->renderer())
        m_page->focusController().setFocusedFrame(result.innerNodeFrame());
}

void WebPage::selectTextWithGranularityAtPoint(const WebCore::IntPoint& point, uint32_t granularity, bool isInteractingWithFocusedElement, CallbackID callbackID)
{
    setFocusedFrameBeforeSelectingTextAtLocation(point);

    auto& frame = m_page->focusController().focusedOrMainFrame();
    auto range = rangeForGranularityAtPoint(frame, point, granularity, isInteractingWithFocusedElement);
    if (range)
        frame.selection().setSelectedRange(range.get(), UPSTREAM, WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
    m_initialSelection = range;
    send(Messages::WebPageProxy::VoidCallback(callbackID));
}

void WebPage::beginSelectionInDirection(uint32_t direction, CallbackID callbackID)
{
    m_selectionAnchor = (static_cast<SelectionDirection>(direction) == DirectionLeft) ? Start : End;
    send(Messages::WebPageProxy::UnsignedCallback(m_selectionAnchor == Start, callbackID));
}

void WebPage::updateSelectionWithExtentPointAndBoundary(const WebCore::IntPoint& point, uint32_t granularity, bool isInteractingWithFocusedElement, CallbackID callbackID)
{
    auto& frame = m_page->focusController().focusedOrMainFrame();
    VisiblePosition position = visiblePositionInFocusedNodeForPoint(frame, point, isInteractingWithFocusedElement);
    RefPtr<Range> newRange = rangeForGranularityAtPoint(frame, point, granularity, isInteractingWithFocusedElement);
    
    if (position.isNull() || !m_initialSelection || !newRange) {
        send(Messages::WebPageProxy::UnsignedCallback(false, callbackID));
        return;
    }
    
    RefPtr<Range> range;
    VisiblePosition selectionStart = m_initialSelection->startPosition();
    VisiblePosition selectionEnd = m_initialSelection->endPosition();

    if (position > m_initialSelection->endPosition())
        selectionEnd = newRange->endPosition();
    else if (position < m_initialSelection->startPosition())
        selectionStart = newRange->startPosition();
    
    if (selectionStart.isNotNull() && selectionEnd.isNotNull())
        range = Range::create(*frame.document(), selectionStart, selectionEnd);
    
    if (range)
        frame.selection().setSelectedRange(range.get(), UPSTREAM, WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);
    
    send(Messages::WebPageProxy::UnsignedCallback(selectionStart == m_initialSelection->startPosition(), callbackID));
}

void WebPage::updateSelectionWithExtentPoint(const WebCore::IntPoint& point, bool isInteractingWithFocusedElement, CallbackID callbackID)
{
    auto& frame = m_page->focusController().focusedOrMainFrame();
    VisiblePosition position = visiblePositionInFocusedNodeForPoint(frame, point, isInteractingWithFocusedElement);

    if (position.isNull()) {
        send(Messages::WebPageProxy::UnsignedCallback(false, callbackID));
        return;
    }

    RefPtr<Range> range;
    VisiblePosition selectionStart;
    VisiblePosition selectionEnd;
    
    if (m_selectionAnchor == Start) {
        selectionStart = frame.selection().selection().visibleStart();
        selectionEnd = position;

        if (position <= selectionStart) {
            selectionStart = selectionStart.previous();
            selectionEnd = frame.selection().selection().visibleEnd();
            m_selectionAnchor = End;
        }
    } else {
        selectionStart = position;
        selectionEnd = frame.selection().selection().visibleEnd();
        
        if (position >= selectionEnd) {
            selectionStart = frame.selection().selection().visibleStart();
            selectionEnd = selectionEnd.next();
            m_selectionAnchor = Start;
        }
    }
    
    if (selectionStart.isNotNull() && selectionEnd.isNotNull())
        range = Range::create(*frame.document(), selectionStart, selectionEnd);

    if (range)
        frame.selection().setSelectedRange(range.get(), UPSTREAM, WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);

    send(Messages::WebPageProxy::UnsignedCallback(m_selectionAnchor == Start, callbackID));
}

void WebPage::convertSelectionRectsToRootView(FrameView* view, Vector<SelectionRect>& selectionRects)
{
    for (size_t i = 0; i < selectionRects.size(); ++i) {
        SelectionRect& currentRect = selectionRects[i];
        currentRect.setRect(view->contentsToRootView(currentRect.rect()));
    }
}

void WebPage::requestDictationContext(CallbackID callbackID)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    VisiblePosition startPosition = frame.selection().selection().start();
    VisiblePosition endPosition = frame.selection().selection().end();
    const unsigned dictationContextWordCount = 5;

    String selectedText;
    if (frame.selection().isRange())
        selectedText = plainTextReplacingNoBreakSpace(frame.selection().selection().toNormalizedRange().get());

    String contextBefore;
    if (startPosition != startOfEditableContent(startPosition)) {
        VisiblePosition currentPosition = startPosition;
        VisiblePosition lastPosition = startPosition;
        for (unsigned i = 0; i < dictationContextWordCount; ++i) {
            currentPosition = startOfWord(positionOfNextBoundaryOfGranularity(lastPosition, WordGranularity, DirectionBackward));
            if (currentPosition.isNull())
                break;
            lastPosition = currentPosition;
        }
        if (lastPosition.isNotNull() && lastPosition != startPosition)
            contextBefore = plainTextReplacingNoBreakSpace(Range::create(*frame.document(), lastPosition, startPosition).ptr());
    }

    String contextAfter;
    if (endPosition != endOfEditableContent(endPosition)) {
        VisiblePosition currentPosition = endPosition;
        VisiblePosition lastPosition = endPosition;
        for (unsigned i = 0; i < dictationContextWordCount; ++i) {
            currentPosition = endOfWord(positionOfNextBoundaryOfGranularity(lastPosition, WordGranularity, DirectionForward));
            if (currentPosition.isNull())
                break;
            lastPosition = currentPosition;
        }
        if (lastPosition.isNotNull() && lastPosition != endPosition)
            contextAfter = plainTextReplacingNoBreakSpace(Range::create(*frame.document(), endPosition, lastPosition).ptr());
    }

    send(Messages::WebPageProxy::SelectionContextCallback(selectedText, contextBefore, contextAfter, callbackID));
}

void WebPage::replaceSelectedText(const String& oldText, const String& newText)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    RefPtr<Range> wordRange = frame.selection().isCaret() ? wordRangeFromPosition(frame.selection().selection().start()) : frame.selection().toNormalizedRange();
    if (plainTextReplacingNoBreakSpace(wordRange.get()) != oldText)
        return;
    
    frame.editor().setIgnoreSelectionChanges(true);
    frame.selection().setSelectedRange(wordRange.get(), UPSTREAM, WebCore::FrameSelection::ShouldCloseTyping::Yes);
    frame.editor().insertText(newText, 0);
    frame.editor().setIgnoreSelectionChanges(false);
}

void WebPage::replaceDictatedText(const String& oldText, const String& newText)
{
    Frame& frame = m_page->focusController().focusedOrMainFrame();
    if (frame.selection().isNone())
        return;
    
    if (frame.selection().isRange()) {
        frame.editor().deleteSelectionWithSmartDelete(false);
        return;
    }
    VisiblePosition position = frame.selection().selection().start();
    for (size_t i = 0; i < oldText.length(); ++i)
        position = position.previous();
    if (position.isNull())
        position = startOfDocument(static_cast<Node*>(frame.document()->documentElement()));
    auto range = Range::create(*frame.document(), position, frame.selection().selection().start());

    if (plainTextReplacingNoBreakSpace(range.ptr()) != oldText)
        return;

    // We don't want to notify the client that the selection has changed until we are done inserting the new text.
    frame.editor().setIgnoreSelectionChanges(true);
    frame.selection().setSelectedRange(range.ptr(), UPSTREAM, WebCore::FrameSelection::ShouldCloseTyping::Yes);
    frame.editor().insertText(newText, 0);
    frame.editor().setIgnoreSelectionChanges(false);
}

void WebPage::requestAutocorrectionData(const String& textForAutocorrection, CompletionHandler<void(WebAutocorrectionData)>&& reply)
{
    auto& frame = m_page->focusController().focusedOrMainFrame();
    if (!frame.selection().isCaret()) {
        reply({ });
        return;
    }

    VisiblePosition position = frame.selection().selection().start();
    auto range = wordRangeFromPosition(position);
    if (!range) {
        reply({ });
        return;
    }

    auto textForRange = plainTextReplacingNoBreakSpace(range.get());
    const unsigned maxSearchAttempts = 5;
    for (size_t i = 0;  i < maxSearchAttempts && textForRange != textForAutocorrection; ++i)
    {
        position = range->startPosition().previous();
        if (position.isNull() || position == range->startPosition())
            break;
        range = Range::create(*frame.document(), wordRangeFromPosition(position)->startPosition(), range->endPosition());
        textForRange = plainTextReplacingNoBreakSpace(range.get());
    }

    Vector<SelectionRect> selectionRects;
    if (textForRange == textForAutocorrection)
        range->collectSelectionRects(selectionRects);

    Vector<FloatRect> rectsForText;
    rectsForText.grow(selectionRects.size());

    convertSelectionRectsToRootView(frame.view(), selectionRects);
    for (size_t i = 0; i < selectionRects.size(); i++)
        rectsForText[i] = selectionRects[i].rect();

    bool multipleFonts = false;
    CTFontRef font = nil;
    if (auto* coreFont = frame.editor().fontForSelection(multipleFonts))
        font = coreFont->getCTFont();

    reply({ WTFMove(rectsForText), (__bridge UIFont *)font });
}

void WebPage::applyAutocorrection(const String& correction, const String& originalText, CallbackID callbackID)
{
    send(Messages::WebPageProxy::StringCallback(applyAutocorrectionInternal(correction, originalText) ? correction : String(), callbackID));
}

Seconds WebPage::eventThrottlingDelay() const
{
    auto behaviorOverride = m_page->eventThrottlingBehaviorOverride();
    if (behaviorOverride) {
        switch (behaviorOverride.value()) {
        case EventThrottlingBehavior::Responsive:
            return 0_s;
        case EventThrottlingBehavior::Unresponsive:
            return 1_s;
        }
    }

    if (m_isInStableState || m_estimatedLatency <= Seconds(1.0 / 60))
        return 0_s;

    return std::min(m_estimatedLatency * 2, 1_s);
}

void WebPage::syncApplyAutocorrection(const String& correction, const String& originalText, CompletionHandler<void(bool)>&& reply)
{
    reply(applyAutocorrectionInternal(correction, originalText));
}

bool WebPage::applyAutocorrectionInternal(const String& correction, const String& originalText)
{
    auto& frame = m_page->focusController().focusedOrMainFrame();
    if (!frame.selection().isCaretOrRange())
        return false;

    RefPtr<Range> range;
    String textForRange;
    auto originalTextWithFoldedQuoteMarks = foldQuoteMarks(originalText);

    if (frame.selection().isCaret()) {
        VisiblePosition position = frame.selection().selection().start();
        range = wordRangeFromPosition(position);
        textForRange = plainTextReplacingNoBreakSpace(range.get());
        if (foldQuoteMarks(textForRange) != originalTextWithFoldedQuoteMarks) {
            // Search for the original text before the selection caret.
            for (size_t i = 0; i < originalText.length(); ++i)
                position = position.previous();
            if (position.isNull())
                position = startOfDocument(static_cast<Node*>(frame.document()->documentElement()));
            range = Range::create(*frame.document(), position, frame.selection().selection().start());
            if (range)
                textForRange = (range) ? plainTextReplacingNoBreakSpace(range.get()) : emptyString();
            unsigned loopCount = 0;
            const unsigned maxPositionsAttempts = 10;
            while (textForRange.length() && textForRange.length() > originalText.length() && loopCount < maxPositionsAttempts) {
                position = position.next();
                if (position.isNotNull() && position >= frame.selection().selection().start())
                    range = nullptr;
                else
                    range = Range::create(*frame.document(), position, frame.selection().selection().start());
                textForRange = (range) ? plainTextReplacingNoBreakSpace(range.get()) : emptyString();
                loopCount++;
            }
        }
    } else {
        // Range selection.
        range = frame.selection().toNormalizedRange();
        if (!range)
            return false;

        textForRange = plainTextReplacingNoBreakSpace(range.get());
    }

    if (foldQuoteMarks(textForRange) != originalTextWithFoldedQuoteMarks)
        return false;
    
    // Correctly determine affinity, using logic currently only present in VisiblePosition
    EAffinity affinity = DOWNSTREAM;
    if (range && range->collapsed())
        affinity = VisiblePosition(range->startPosition(), UPSTREAM).affinity();
    
    frame.selection().setSelectedRange(range.get(), affinity, WebCore::FrameSelection::ShouldCloseTyping::Yes);
    if (correction.length())
        frame.editor().insertText(correction, 0, originalText.isEmpty() ? TextEventInputKeyboard : TextEventInputAutocompletion);
    else if (originalText.length())
        frame.editor().deleteWithDirection(DirectionBackward, CharacterGranularity, false, true);
    return true;
}

WebAutocorrectionContext WebPage::autocorrectionContext()
{
    String contextBefore;
    String markedText;
    String selectedText;
    String contextAfter;
    EditingRange markedTextRange;

    auto& frame = m_page->focusController().focusedOrMainFrame();
    RefPtr<Range> range;
    VisiblePosition startPosition = frame.selection().selection().start();
    VisiblePosition endPosition = frame.selection().selection().end();
    const unsigned minContextWordCount = 3;
    const unsigned minContextLenght = 12;
    const unsigned maxContextLength = 30;

    if (frame.selection().isRange())
        selectedText = plainTextReplacingNoBreakSpace(frame.selection().selection().toNormalizedRange().get());

    if (auto compositionRange = frame.editor().compositionRange()) {
        range = Range::create(*frame.document(), compositionRange->startPosition(), startPosition);
        String markedTextBefore;
        if (range)
            markedTextBefore = plainTextReplacingNoBreakSpace(range.get());
        range = Range::create(*frame.document(), endPosition, compositionRange->endPosition());
        String markedTextAfter;
        if (range)
            markedTextAfter = plainTextReplacingNoBreakSpace(range.get());
        markedText = markedTextBefore + selectedText + markedTextAfter;
        if (!markedText.isEmpty()) {
            markedTextRange.location = markedTextBefore.length();
            markedTextRange.length = selectedText.length();
        }
    } else {
        if (startPosition != startOfEditableContent(startPosition)) {
            VisiblePosition currentPosition = startPosition;
            VisiblePosition previousPosition;
            unsigned totalContextLength = 0;
            for (unsigned i = 0; i < minContextWordCount; ++i) {
                if (contextBefore.length() >= minContextLenght)
                    break;
                previousPosition = startOfWord(positionOfNextBoundaryOfGranularity(currentPosition, WordGranularity, DirectionBackward));
                if (previousPosition.isNull())
                    break;
                String currentWord = plainTextReplacingNoBreakSpace(Range::create(*frame.document(), previousPosition, currentPosition).ptr());
                totalContextLength += currentWord.length();
                if (totalContextLength >= maxContextLength)
                    break;
                currentPosition = previousPosition;
            }
            if (currentPosition.isNotNull() && currentPosition != startPosition) {
                contextBefore = plainTextReplacingNoBreakSpace(Range::create(*frame.document(), currentPosition, startPosition).ptr());
                if (atBoundaryOfGranularity(currentPosition, ParagraphGranularity, DirectionBackward))
                    contextBefore = makeString("\n "_s, contextBefore);
            }
        }

        if (endPosition != endOfEditableContent(endPosition)) {
            VisiblePosition nextPosition;
            if (!atBoundaryOfGranularity(endPosition, WordGranularity, DirectionForward) && withinTextUnitOfGranularity(endPosition, WordGranularity, DirectionForward))
                nextPosition = positionOfNextBoundaryOfGranularity(endPosition, WordGranularity, DirectionForward);
            if (nextPosition.isNotNull())
                contextAfter = plainTextReplacingNoBreakSpace(Range::create(*frame.document(), endPosition, nextPosition).ptr());
        }
    }

    WebAutocorrectionContext correction;
    correction.contextBefore = WTFMove(contextBefore);
    correction.markedText = WTFMove(markedText);
    correction.selectedText = WTFMove(selectedText);
    correction.contextAfter = WTFMove(contextAfter);
    correction.markedTextRange = WTFMove(markedTextRange);
    return correction;
}

void WebPage::requestAutocorrectionContext()
{
    send(Messages::WebPageProxy::HandleAutocorrectionContext(autocorrectionContext()));
}

static HTMLAnchorElement* containingLinkElement(Element* element)
{
    for (auto& currentElement : elementLineage(element)) {
        if (currentElement.isLink() && is<HTMLAnchorElement>(currentElement))
            return downcast<HTMLAnchorElement>(&currentElement);
    }
    return nullptr;
}

static inline bool isAssistableElement(Element& element)
{
    if (is<HTMLSelectElement>(element))
        return true;
    if (is<HTMLTextAreaElement>(element))
        return true;
    if (is<HTMLImageElement>(element) && downcast<HTMLImageElement>(element).hasEditableImageAttribute())
        return true;
    if (is<HTMLInputElement>(element)) {
        HTMLInputElement& inputElement = downcast<HTMLInputElement>(element);
        // FIXME: This laundry list of types is not a good way to factor this. Need a suitable function on HTMLInputElement itself.
#if ENABLE(INPUT_TYPE_COLOR)
        if (inputElement.isColorControl())
            return true;
#endif
        return inputElement.isTextField() || inputElement.isDateField() || inputElement.isDateTimeLocalField() || inputElement.isMonthField() || inputElement.isTimeField();
    }
    if (is<HTMLIFrameElement>(element))
        return false;
    return element.isContentEditable();
}

void WebPage::getPositionInformation(const InteractionInformationRequest& request, CompletionHandler<void(InteractionInformationAtPosition&&)>&& reply)
{
    // Avoid UIProcess hangs when the WebContent process is stuck on a sync IPC.
    if (IPC::UnboundedSynchronousIPCScope::hasOngoingUnboundedSyncIPC()) {
        RELEASE_LOG_ERROR_IF_ALLOWED(Process, "getPositionInformation - Not processing because the process is stuck on unbounded sync IPC");
        return reply({ });
    }

    m_pendingSynchronousPositionInformationReply = WTFMove(reply);

    auto information = positionInformation(request);

    if (auto reply = WTFMove(m_pendingSynchronousPositionInformationReply))
        reply(WTFMove(information));
}
    
static void focusedElementPositionInformation(WebPage& page, Element& focusedElement, const InteractionInformationRequest& request, InteractionInformationAtPosition& info)
{
    const Frame& frame = page.corePage()->focusController().focusedOrMainFrame();
    if (!frame.editor().hasComposition())
        return;

    const uint32_t kHitAreaWidth = 66;
    const uint32_t kHitAreaHeight = 66;
    FrameView& view = *frame.view();
    IntPoint adjustedPoint(view.rootViewToContents(request.point));
    IntPoint constrainedPoint = constrainPoint(adjustedPoint, frame, focusedElement);
    VisiblePosition position = frame.visiblePositionForPoint(constrainedPoint);

    RefPtr<Range> compositionRange = frame.editor().compositionRange();
    if (!compositionRange)
        return;

    if (position < compositionRange->startPosition())
        position = compositionRange->startPosition();
    else if (position > compositionRange->endPosition())
        position = compositionRange->endPosition();
    IntRect caretRect = view.contentsToRootView(position.absoluteCaretBounds());
    float deltaX = abs(caretRect.x() + (caretRect.width() / 2) - request.point.x());
    float deltaYFromTheTop = abs(caretRect.y() - request.point.y());
    float deltaYFromTheBottom = abs(caretRect.y() + caretRect.height() - request.point.y());

    info.isNearMarkedText = !(deltaX > kHitAreaWidth || deltaYFromTheTop > kHitAreaHeight || deltaYFromTheBottom > kHitAreaHeight);
}

static void linkIndicatorPositionInformation(WebPage& page, Element& linkElement, const InteractionInformationRequest& request, InteractionInformationAtPosition& info)
{
    if (!request.includeLinkIndicator)
        return;

    auto linkRange = rangeOfContents(linkElement);
    float deviceScaleFactor = page.corePage()->deviceScaleFactor();
    const float marginInPoints = request.linkIndicatorShouldHaveLegacyMargins ? 4 : 0;

    auto textIndicator = TextIndicator::createWithRange(linkRange.get(),
        TextIndicatorOptionTightlyFitContent | TextIndicatorOptionRespectTextColor | TextIndicatorOptionPaintBackgrounds |
        TextIndicatorOptionUseBoundingRectAndPaintAllContentForComplexRanges | TextIndicatorOptionIncludeMarginIfRangeMatchesSelection | TextIndicatorOptionComputeEstimatedBackgroundColor,
        TextIndicatorPresentationTransition::None, FloatSize(marginInPoints * deviceScaleFactor, marginInPoints * deviceScaleFactor));
        
    if (textIndicator)
        info.linkIndicator = textIndicator->data();
}
    
#if ENABLE(DATA_DETECTION)
static void dataDetectorLinkPositionInformation(Element& element, InteractionInformationAtPosition& info)
{
    if (!DataDetection::isDataDetectorLink(element))
        return;
    
    info.isDataDetectorLink = true;
    const int dataDetectionExtendedContextLength = 350;
    info.dataDetectorIdentifier = DataDetection::dataDetectorIdentifier(element);
    info.dataDetectorResults = element.document().frame()->dataDetectionResults();

    if (!DataDetection::requiresExtendedContext(element))
        return;
    
    auto linkRange = Range::create(element.document());
    linkRange->selectNodeContents(element);
    info.textBefore = plainTextReplacingNoBreakSpace(rangeExpandedByCharactersInDirectionAtWordBoundary(linkRange->startPosition(),
        dataDetectionExtendedContextLength, DirectionBackward).get(), TextIteratorDefaultBehavior, true);
    info.textAfter = plainTextReplacingNoBreakSpace(rangeExpandedByCharactersInDirectionAtWordBoundary(linkRange->endPosition(),
        dataDetectionExtendedContextLength, DirectionForward).get(), TextIteratorDefaultBehavior, true);
}
#endif

static void imagePositionInformation(WebPage& page, Element& element, const InteractionInformationRequest& request, InteractionInformationAtPosition& info)
{
    auto& renderImage = downcast<RenderImage>(*(element.renderer()));
    if (!renderImage.cachedImage() || renderImage.cachedImage()->errorOccurred())
        return;

    auto* image = renderImage.cachedImage()->imageForRenderer(&renderImage);
    if (!image || image->width() <= 1 || image->height() <= 1)
        return;

    info.isImage = true;
    info.imageURL = element.document().completeURL(renderImage.cachedImage()->url());
    info.isAnimatedImage = image->isAnimated();

    if (!request.includeSnapshot)
        return;

    FloatSize screenSizeInPixels = screenSize();
    FloatSize imageSize = renderImage.cachedImage()->imageSizeForRenderer(&renderImage);
    
    screenSizeInPixels.scale(page.corePage()->deviceScaleFactor());
    FloatSize scaledSize = largestRectWithAspectRatioInsideRect(imageSize.width() / imageSize.height(), FloatRect(0, 0, screenSizeInPixels.width(), screenSizeInPixels.height())).size();
    FloatSize bitmapSize = scaledSize.width() < imageSize.width() ? scaledSize : imageSize;
    
    // FIXME: Only select ExtendedColor on images known to need wide gamut
    ShareableBitmap::Configuration bitmapConfiguration;
    bitmapConfiguration.colorSpace.cgColorSpace = screenColorSpace(page.corePage()->mainFrame().view());

    auto sharedBitmap = ShareableBitmap::createShareable(IntSize(bitmapSize), bitmapConfiguration);
    if (!sharedBitmap)
        return;

    auto graphicsContext = sharedBitmap->createGraphicsContext();
    if (!graphicsContext)
        return;

    graphicsContext->drawImage(*image, FloatRect(0, 0, bitmapSize.width(), bitmapSize.height()), { renderImage.imageOrientation() });
    info.image = sharedBitmap;
}

static void boundsPositionInformation(RenderElement& renderer, InteractionInformationAtPosition& info)
{
    if (renderer.isRenderImage())
        info.bounds = downcast<RenderImage>(renderer).absoluteContentQuad().enclosingBoundingBox();
    else
        info.bounds = renderer.absoluteBoundingBoxRect();

    if (!renderer.document().frame()->isMainFrame()) {
        FrameView *view = renderer.document().frame()->view();
        info.bounds = view->contentsToRootView(info.bounds);
    }
}

static void elementPositionInformation(WebPage& page, Element& element, const InteractionInformationRequest& request, InteractionInformationAtPosition& info)
{
    Element* linkElement = nullptr;
    if (element.renderer() && element.renderer()->isRenderImage())
        linkElement = containingLinkElement(&element);
    else if (element.isLink())
        linkElement = &element;

    info.isElement = true;
    info.idAttribute = element.getIdAttribute();

    info.title = element.attributeWithoutSynchronization(HTMLNames::titleAttr).string();
    if (linkElement && info.title.isEmpty())
        info.title = element.innerText();
    if (element.renderer())
        info.touchCalloutEnabled = element.renderer()->style().touchCalloutEnabled();

    if (linkElement) {
        info.isLink = true;
        info.url = linkElement->document().completeURL(stripLeadingAndTrailingHTMLSpaces(linkElement->getAttribute(HTMLNames::hrefAttr)));

        linkIndicatorPositionInformation(page, *linkElement, request, info);
#if ENABLE(DATA_DETECTION)
        dataDetectorLinkPositionInformation(element, info);
#endif
    }

    auto* elementForScrollTesting = linkElement ? linkElement : &element;
    if (auto* renderer = elementForScrollTesting->renderer()) {
#if ENABLE(ASYNC_SCROLLING)
        if (auto* scrollingCoordinator = page.scrollingCoordinator())
            info.containerScrollingNodeID = scrollingCoordinator->scrollableContainerNodeID(*renderer);
#endif
    }

    if (auto* renderer = element.renderer()) {
        if (renderer->isRenderImage())
            imagePositionInformation(page, element, request, info);
        boundsPositionInformation(*renderer, info);
    }
}
    
static void selectionPositionInformation(WebPage& page, const InteractionInformationRequest& request, InteractionInformationAtPosition& info)
{
    HitTestResult result = page.corePage()->mainFrame().eventHandler().hitTestResultAtPoint(request.point, HitTestRequest::ReadOnly | HitTestRequest::Active | HitTestRequest::DisallowUserAgentShadowContent | HitTestRequest::AllowChildFrameContent);
    Node* hitNode = result.innerNode();

    // Hit test could return HTMLHtmlElement that has no renderer, if the body is smaller than the document.
    if (!hitNode || !hitNode->renderer())
        return;

    RenderObject* renderer = hitNode->renderer();
    info.bounds = renderer->absoluteBoundingBoxRect(true);
    // We don't want to select blocks that are larger than 97% of the visible area of the document.
    if (is<HTMLAttachmentElement>(*hitNode)) {
        info.isAttachment = true;
        HTMLAttachmentElement& attachment = downcast<HTMLAttachmentElement>(*hitNode);
        info.title = attachment.attachmentTitle();
        linkIndicatorPositionInformation(page, attachment, request, info);
        if (attachment.file())
            info.url = URL::fileURLWithFileSystemPath(downcast<HTMLAttachmentElement>(*hitNode).file()->path());
    } else {
        info.isSelectable = renderer->style().userSelect() != UserSelect::None;
        if (info.isSelectable && !hitNode->isTextNode())
            info.isSelectable = !isAssistableElement(*downcast<Element>(hitNode)) && !rectIsTooBigForSelection(info.bounds, *result.innerNodeFrame());
    }

#if PLATFORM(MACCATALYST)
    bool isInsideFixedPosition;
    VisiblePosition caretPosition(renderer->positionForPoint(request.point, nullptr));
    info.caretRect = caretPosition.absoluteCaretBounds(&isInsideFixedPosition);
#endif
}

#if ENABLE(DATALIST_ELEMENT)
static void textInteractionPositionInformation(WebPage& page, const HTMLInputElement& input, const InteractionInformationRequest& request, InteractionInformationAtPosition& info)
{
    if (!input.list())
        return;

    HitTestResult result = page.corePage()->mainFrame().eventHandler().hitTestResultAtPoint(request.point, HitTestRequest::ReadOnly | HitTestRequest::Active | HitTestRequest::AllowChildFrameContent);
    if (result.innerNode() == input.dataListButtonElement())
        info.preventTextInteraction = true;
}
#endif

RefPtr<ShareableBitmap> WebPage::shareableBitmapSnapshotForNode(Element& element)
{
    // Ensure that the image contains at most 600K pixels, so that it is not too big.
    if (RefPtr<WebImage> snapshot = snapshotNode(element, SnapshotOptionsShareable, 600 * 1024))
        return &snapshot->bitmap();
    return nullptr;
}

InteractionInformationAtPosition WebPage::positionInformation(const InteractionInformationRequest& request)
{
    InteractionInformationAtPosition info;
    info.request = request;

    FloatPoint adjustedPoint;
    Node* hitNode = m_page->mainFrame().nodeRespondingToClickEvents(request.point, adjustedPoint);

    info.nodeAtPositionIsFocusedElement = hitNode == m_focusedElement;
    info.adjustedPointForNodeRespondingToClickEvents = adjustedPoint;

#if ENABLE(DATA_INTERACTION)
    info.hasSelectionAtPosition = m_page->hasSelectionAtPosition(adjustedPoint);
#endif

    if (m_focusedElement)
        focusedElementPositionInformation(*this, *m_focusedElement, request, info);

    if (is<Element>(hitNode)) {
        Element& element = downcast<Element>(*hitNode);
        elementPositionInformation(*this, element, request, info);

        if (info.isLink && !info.isImage && request.includeSnapshot)
            info.image = shareableBitmapSnapshotForNode(element);
    }

    if (!(info.isLink || info.isImage))
        selectionPositionInformation(*this, request, info);

    // Prevent the callout bar from showing when tapping on the datalist button.
#if ENABLE(DATALIST_ELEMENT)
    if (is<HTMLInputElement>(hitNode)) {
        const HTMLInputElement& input = downcast<HTMLInputElement>(*hitNode);
        textInteractionPositionInformation(*this, input, request, info);
    }
#endif

    return info;
}

void WebPage::requestPositionInformation(const InteractionInformationRequest& request)
{
    send(Messages::WebPageProxy::DidReceivePositionInformation(positionInformation(request)));
}

void WebPage::startInteractionWithElementAtPosition(const WebCore::IntPoint& point)
{
    FloatPoint adjustedPoint;
    m_interactionNode = m_page->mainFrame().nodeRespondingToClickEvents(point, adjustedPoint);
}

void WebPage::stopInteraction()
{
    m_interactionNode = nullptr;
}

void WebPage::performActionOnElement(uint32_t action)
{
    if (!is<HTMLElement>(m_interactionNode.get()))
        return;

    HTMLElement& element = downcast<HTMLElement>(*m_interactionNode);
    if (!element.renderer())
        return;

    if (static_cast<SheetAction>(action) == SheetAction::Copy) {
        if (is<RenderImage>(*element.renderer())) {
            URL url;
            String title;
            if (auto* linkElement = containingLinkElement(&element)) {
                url = linkElement->href();
                title = linkElement->attributeWithoutSynchronization(HTMLNames::titleAttr);
                if (!title.length())
                    title = linkElement->textContent();
                title = stripLeadingAndTrailingHTMLSpaces(title);
            }
            m_interactionNode->document().frame()->editor().writeImageToPasteboard(*Pasteboard::createForCopyAndPaste(), element, url, title);
        } else if (element.isLink()) {
            m_interactionNode->document().frame()->editor().copyURL(element.document().completeURL(stripLeadingAndTrailingHTMLSpaces(element.attributeWithoutSynchronization(HTMLNames::hrefAttr))), element.textContent());
        }
    } else if (static_cast<SheetAction>(action) == SheetAction::SaveImage) {
        if (!is<RenderImage>(*element.renderer()))
            return;
        CachedImage* cachedImage = downcast<RenderImage>(*element.renderer()).cachedImage();
        if (!cachedImage)
            return;
        RefPtr<SharedBuffer> buffer = cachedImage->resourceBuffer();
        if (!buffer)
            return;
        uint64_t bufferSize = buffer->size();
        RefPtr<SharedMemory> sharedMemoryBuffer = SharedMemory::allocate(bufferSize);
        memcpy(sharedMemoryBuffer->data(), buffer->data(), bufferSize);
        SharedMemory::Handle handle;
        sharedMemoryBuffer->createHandle(handle, SharedMemory::Protection::ReadOnly);
        send(Messages::WebPageProxy::SaveImageToLibrary(handle, bufferSize));
    }
}

static inline Element* nextAssistableElement(Node* startNode, Page& page, bool isForward)
{
    if (!is<Element>(startNode))
        return nullptr;

    Element* nextElement = downcast<Element>(startNode);
    do {
        nextElement = isForward
            ? page.focusController().nextFocusableElement(*nextElement)
            : page.focusController().previousFocusableElement(*nextElement);
    } while (nextElement && !isAssistableElement(*nextElement));

    return nextElement;
}

void WebPage::focusNextFocusedElement(bool isForward, CallbackID callbackID)
{
    Element* nextElement = nextAssistableElement(m_focusedElement.get(), *m_page, isForward);
    m_userIsInteracting = true;
    if (nextElement)
        nextElement->focus();
    m_userIsInteracting = false;
    send(Messages::WebPageProxy::VoidCallback(callbackID));
}

void WebPage::getFocusedElementInformation(FocusedElementInformation& information)
{
    layoutIfNeeded();

    information.lastInteractionLocation = m_lastInteractionLocation;

    if (auto* renderer = m_focusedElement->renderer()) {
        information.elementRect = rootViewInteractionBoundsForElement(*m_focusedElement);
        information.nodeFontSize = renderer->style().fontDescription().computedSize();

        bool inFixed = false;
        renderer->localToContainerPoint(FloatPoint(), nullptr, UseTransforms, &inFixed);
        information.insideFixedPosition = inFixed;
        information.isRTL = renderer->style().direction() == TextDirection::RTL;
    } else
        information.elementRect = IntRect();

    if (is<HTMLElement>(m_focusedElement))
        information.isSpellCheckingEnabled = downcast<HTMLElement>(*m_focusedElement).spellcheck();

    information.minimumScaleFactor = minimumPageScaleFactor();
    information.maximumScaleFactor = maximumPageScaleFactor();
    information.maximumScaleFactorIgnoringAlwaysScalable = maximumPageScaleFactorIgnoringAlwaysScalable();
    information.allowsUserScaling = m_viewportConfiguration.allowsUserScaling();
    information.allowsUserScalingIgnoringAlwaysScalable = m_viewportConfiguration.allowsUserScalingIgnoringAlwaysScalable();
    if (auto* nextElement = nextAssistableElement(m_focusedElement.get(), *m_page, true)) {
        information.nextNodeRect = rootViewBoundsForElement(*nextElement);
        information.hasNextNode = true;
    }
    if (auto* previousElement = nextAssistableElement(m_focusedElement.get(), *m_page, false)) {
        information.previousNodeRect = rootViewBoundsForElement(*previousElement);
        information.hasPreviousNode = true;
    }
    information.focusedElementIdentifier = m_currentFocusedElementIdentifier;

    if (is<LabelableElement>(*m_focusedElement)) {
        auto labels = downcast<LabelableElement>(*m_focusedElement).labels();
        Vector<Ref<Element>> associatedLabels;
        for (unsigned index = 0; index < labels->length(); ++index) {
            if (is<Element>(labels->item(index)) && labels->item(index)->renderer())
                associatedLabels.append(downcast<Element>(*labels->item(index)));
        }
        for (auto& labelElement : associatedLabels) {
            auto text = labelElement->innerText();
            if (!text.isEmpty()) {
                information.label = WTFMove(text);
                break;
            }
        }
    }

    information.title = m_focusedElement->title();
    information.ariaLabel = m_focusedElement->attributeWithoutSynchronization(HTMLNames::aria_labelAttr);

    if (is<HTMLSelectElement>(*m_focusedElement)) {
        HTMLSelectElement& element = downcast<HTMLSelectElement>(*m_focusedElement);
        information.elementType = InputType::Select;
        const Vector<HTMLElement*>& items = element.listItems();
        size_t count = items.size();
        int parentGroupID = 0;
        // The parent group ID indicates the group the option belongs to and is 0 for group elements.
        // If there are option elements in between groups, they are given it's own group identifier.
        // If a select does not have groups, all the option elements have group ID 0.
        for (size_t i = 0; i < count; ++i) {
            HTMLElement* item = items[i];
            if (is<HTMLOptionElement>(*item)) {
                HTMLOptionElement& option = downcast<HTMLOptionElement>(*item);
                information.selectOptions.append(OptionItem(option.text(), false, parentGroupID, option.selected(), option.hasAttributeWithoutSynchronization(WebCore::HTMLNames::disabledAttr)));
            } else if (is<HTMLOptGroupElement>(*item)) {
                HTMLOptGroupElement& group = downcast<HTMLOptGroupElement>(*item);
                parentGroupID++;
                information.selectOptions.append(OptionItem(group.groupLabelText(), true, 0, false, group.hasAttributeWithoutSynchronization(WebCore::HTMLNames::disabledAttr)));
            }
        }
        information.selectedIndex = element.selectedIndex();
        information.isMultiSelect = element.multiple();
    } else if (is<HTMLTextAreaElement>(*m_focusedElement)) {
        HTMLTextAreaElement& element = downcast<HTMLTextAreaElement>(*m_focusedElement);
        information.autocapitalizeType = element.autocapitalizeType();
        information.isAutocorrect = element.shouldAutocorrect();
        information.elementType = InputType::TextArea;
        information.isReadOnly = element.isReadOnly();
        information.value = element.value();
        information.autofillFieldName = WebCore::toAutofillFieldName(element.autofillData().fieldName);
        information.placeholder = element.attributeWithoutSynchronization(HTMLNames::placeholderAttr);
        information.inputMode = element.canonicalInputMode();
    } else if (is<HTMLInputElement>(*m_focusedElement)) {
        HTMLInputElement& element = downcast<HTMLInputElement>(*m_focusedElement);
        HTMLFormElement* form = element.form();
        if (form)
            information.formAction = form->getURLAttribute(WebCore::HTMLNames::actionAttr);
        if (auto autofillElements = WebCore::AutofillElements::computeAutofillElements(element)) {
            information.acceptsAutofilledLoginCredentials = true;
            information.isAutofillableUsernameField = autofillElements->username() == m_focusedElement;
        }
        information.representingPageURL = element.document().urlForBindings();
        information.autocapitalizeType = element.autocapitalizeType();
        information.isAutocorrect = element.shouldAutocorrect();
        information.placeholder = element.attributeWithoutSynchronization(HTMLNames::placeholderAttr);
        if (element.isPasswordField())
            information.elementType = InputType::Password;
        else if (element.isSearchField())
            information.elementType = InputType::Search;
        else if (element.isEmailField())
            information.elementType = InputType::Email;
        else if (element.isTelephoneField())
            information.elementType = InputType::Phone;
        else if (element.isNumberField())
            information.elementType = element.getAttribute("pattern") == "\\d*" || element.getAttribute("pattern") == "[0-9]*" ? InputType::NumberPad : InputType::Number;
        else if (element.isDateTimeLocalField())
            information.elementType = InputType::DateTimeLocal;
        else if (element.isDateField())
            information.elementType = InputType::Date;
        else if (element.isDateTimeField())
            information.elementType = InputType::DateTime;
        else if (element.isTimeField())
            information.elementType = InputType::Time;
        else if (element.isWeekField())
            information.elementType = InputType::Week;
        else if (element.isMonthField())
            information.elementType = InputType::Month;
        else if (element.isURLField())
            information.elementType = InputType::URL;
        else if (element.isText()) {
            const AtomString& pattern = element.attributeWithoutSynchronization(HTMLNames::patternAttr);
            if (pattern == "\\d*" || pattern == "[0-9]*")
                information.elementType = InputType::NumberPad;
            else {
                information.elementType = InputType::Text;
                if (!information.formAction.isEmpty()
                    && (element.getNameAttribute().contains("search") || element.getIdAttribute().contains("search") || element.attributeWithoutSynchronization(HTMLNames::titleAttr).contains("search")))
                    information.elementType = InputType::Search;
            }
        }
#if ENABLE(INPUT_TYPE_COLOR)
        else if (element.isColorControl()) {
            information.elementType = InputType::Color;
#if ENABLE(DATALIST_ELEMENT)
            information.suggestedColors = element.suggestedColors();
#endif
        }
#endif

#if ENABLE(DATALIST_ELEMENT)
        information.hasSuggestions = !!element.list();
#endif
        information.inputMode = element.canonicalInputMode();
        information.isReadOnly = element.isReadOnly();
        information.value = element.value();
        information.valueAsNumber = element.valueAsNumber();
        information.autofillFieldName = WebCore::toAutofillFieldName(element.autofillData().fieldName);
    } else if (is<HTMLImageElement>(*m_focusedElement) && downcast<HTMLImageElement>(*m_focusedElement).hasEditableImageAttribute()) {
        information.elementType = InputType::Drawing;
        information.embeddedViewID = downcast<HTMLImageElement>(*m_focusedElement).editableImageViewID();
    } else if (m_focusedElement->hasEditableStyle()) {
        information.elementType = InputType::ContentEditable;
        if (is<HTMLElement>(*m_focusedElement)) {
            auto& focusedElement = downcast<HTMLElement>(*m_focusedElement);
            information.isAutocorrect = focusedElement.shouldAutocorrect();
            information.autocapitalizeType = focusedElement.autocapitalizeType();
            information.inputMode = focusedElement.canonicalInputMode();
            information.shouldSynthesizeKeyEventsForEditing = focusedElement.document().settings().syntheticEditingCommandsEnabled();
        } else {
            information.isAutocorrect = true;
            information.autocapitalizeType = AutocapitalizeTypeDefault;
        }
        information.isReadOnly = false;
    }

    if (m_focusedElement->document().quirks().shouldSuppressAutocorrectionAndAutocaptializationInHiddenEditableAreas() && isTransparentOrFullyClipped(*m_focusedElement)) {
        information.autocapitalizeType = AutocapitalizeTypeNone;
        information.isAutocorrect = false;
    }

    auto& quirks = m_focusedElement->document().quirks();
    information.shouldAvoidResizingWhenInputViewBoundsChange = quirks.shouldAvoidResizingWhenInputViewBoundsChange();
    information.shouldAvoidScrollingWhenFocusedContentIsVisible = quirks.shouldAvoidScrollingWhenFocusedContentIsVisible();
}

void WebPage::autofillLoginCredentials(const String& username, const String& password)
{
    if (is<HTMLInputElement>(m_focusedElement.get())) {
        if (auto autofillElements = AutofillElements::computeAutofillElements(downcast<HTMLInputElement>(*m_focusedElement)))
            autofillElements->autofill(username, password);
    }
}

// WebCore stores the page scale factor as float instead of double. When we get a scale from WebCore,
// we need to ignore differences that are within a small rounding error on floats.
static inline bool areEssentiallyEqualAsFloat(float a, float b)
{
    return WTF::areEssentiallyEqual(a, b);
}

void WebPage::setViewportConfigurationViewLayoutSize(const FloatSize& size, double scaleFactor, double minimumEffectiveDeviceWidth)
{
    LOG_WITH_STREAM(VisibleRects, stream << "WebPage " << m_pageID << " setViewportConfigurationViewLayoutSize " << size << " scaleFactor " << scaleFactor << " minimumEffectiveDeviceWidth " << minimumEffectiveDeviceWidth);

    auto previousLayoutSizeScaleFactor = m_viewportConfiguration.layoutSizeScaleFactor();
    auto clampedMinimumEffectiveDevice = m_viewportConfiguration.isKnownToLayOutWiderThanViewport() ? WTF::nullopt : Optional<double>(minimumEffectiveDeviceWidth);
    if (!m_viewportConfiguration.setViewLayoutSize(size, scaleFactor, WTFMove(clampedMinimumEffectiveDevice)))
        return;

    auto zoomToInitialScale = ZoomToInitialScale::No;
    auto newInitialScale = m_viewportConfiguration.initialScale();
    auto currentPageScaleFactor = pageScaleFactor();
    if (scaleFactor > previousLayoutSizeScaleFactor && newInitialScale > currentPageScaleFactor)
        zoomToInitialScale = ZoomToInitialScale::Yes;
    else if (scaleFactor < previousLayoutSizeScaleFactor && newInitialScale < currentPageScaleFactor)
        zoomToInitialScale = ZoomToInitialScale::Yes;

    viewportConfigurationChanged(zoomToInitialScale);
}

void WebPage::setMaximumUnobscuredSize(const FloatSize& maximumUnobscuredSize)
{
    m_maximumUnobscuredSize = maximumUnobscuredSize;
    updateViewportSizeForCSSViewportUnits();
}

void WebPage::setDeviceOrientation(int32_t deviceOrientation)
{
    if (deviceOrientation == m_deviceOrientation)
        return;
    m_deviceOrientation = deviceOrientation;
    m_page->mainFrame().orientationChanged();
}

void WebPage::setOverrideViewportArguments(const Optional<WebCore::ViewportArguments>& arguments)
{
    m_page->setOverrideViewportArguments(arguments);
}

void WebPage::dynamicViewportSizeUpdate(const FloatSize& viewLayoutSize, const WebCore::FloatSize& maximumUnobscuredSize, const FloatRect& targetExposedContentRect, const FloatRect& targetUnobscuredRect, const WebCore::FloatRect& targetUnobscuredRectInScrollViewCoordinates, const WebCore::FloatBoxExtent& targetUnobscuredSafeAreaInsets, double targetScale, int32_t deviceOrientation, DynamicViewportSizeUpdateID dynamicViewportSizeUpdateID)
{
    SetForScope<bool> dynamicSizeUpdateGuard(m_inDynamicSizeUpdate, true);
    // FIXME: this does not handle the cases where the content would change the content size or scroll position from JavaScript.
    // To handle those cases, we would need to redo this computation on every change until the next visible content rect update.
    LOG_WITH_STREAM(VisibleRects, stream << "\nWebPage::dynamicViewportSizeUpdate - viewLayoutSize " << viewLayoutSize << " targetUnobscuredRect " << targetUnobscuredRect << " targetExposedContentRect " << targetExposedContentRect << " targetScale " << targetScale);

    FrameView& frameView = *m_page->mainFrame().view();
    IntSize oldContentSize = frameView.contentsSize();
    float oldPageScaleFactor = m_page->pageScaleFactor();

    m_dynamicSizeUpdateHistory.add(std::make_pair(oldContentSize, oldPageScaleFactor), frameView.scrollPosition());

    RefPtr<Node> oldNodeAtCenter;
    double visibleHorizontalFraction = 1;
    float relativeHorizontalPositionInNodeAtCenter = 0;
    float relativeVerticalPositionInNodeAtCenter = 0;
    {
        visibleHorizontalFraction = frameView.unobscuredContentSize().width() / oldContentSize.width();
        IntPoint unobscuredContentRectCenter = frameView.unobscuredContentRect().center();

        HitTestResult hitTestResult = HitTestResult(unobscuredContentRectCenter);

        if (auto* document = frameView.frame().document())
            document->hitTest(HitTestRequest(), hitTestResult);

        if (Node* node = hitTestResult.innerNode()) {
            if (RenderObject* renderer = node->renderer()) {
                FrameView& containingView = *node->document().frame()->view();
                FloatRect boundingBox = containingView.contentsToRootView(renderer->absoluteBoundingBoxRect(true));
                relativeHorizontalPositionInNodeAtCenter = (unobscuredContentRectCenter.x() - boundingBox.x()) / boundingBox.width();
                relativeVerticalPositionInNodeAtCenter = (unobscuredContentRectCenter.y() - boundingBox.y()) / boundingBox.height();
                oldNodeAtCenter = node;
            }
        }
    }

    LOG_WITH_STREAM(VisibleRects, stream << "WebPage::dynamicViewportSizeUpdate setting view layout size to " << viewLayoutSize);
    bool viewportChanged = m_viewportConfiguration.setIsKnownToLayOutWiderThanViewport(false);
    viewportChanged |= m_viewportConfiguration.setViewLayoutSize(viewLayoutSize);
    if (viewportChanged)
        viewportConfigurationChanged();

    IntSize newLayoutSize = m_viewportConfiguration.layoutSize();

#if ENABLE(TEXT_AUTOSIZING)
    if (setFixedLayoutSize(newLayoutSize))
        resetTextAutosizing();
#endif
    setMaximumUnobscuredSize(maximumUnobscuredSize);
    m_page->setUnobscuredSafeAreaInsets(targetUnobscuredSafeAreaInsets);

    frameView.updateLayoutAndStyleIfNeededRecursive();

    IntSize newContentSize = frameView.contentsSize();

    double scale = scaleAfterViewportWidthChange(targetScale, m_userHasChangedPageScaleFactor, m_viewportConfiguration, targetUnobscuredRectInScrollViewCoordinates.width(), newContentSize, oldContentSize, visibleHorizontalFraction);
    FloatRect newUnobscuredContentRect = targetUnobscuredRect;
    FloatRect newExposedContentRect = targetExposedContentRect;

    bool scaleChanged = !areEssentiallyEqualAsFloat(scale, targetScale);
    if (scaleChanged) {
        // The target scale the UI is using cannot be reached by the content. We need to compute new targets based
        // on the viewport constraint and report everything back to the UIProcess.

        // 1) Compute a new unobscured rect centered around the original one.
        double scaleDifference = targetScale / scale;
        double newUnobscuredRectWidth = targetUnobscuredRect.width() * scaleDifference;
        double newUnobscuredRectHeight = targetUnobscuredRect.height() * scaleDifference;
        double newUnobscuredRectX = targetUnobscuredRect.x() - (newUnobscuredRectWidth - targetUnobscuredRect.width()) / 2;
        double newUnobscuredRectY = targetUnobscuredRect.y() - (newUnobscuredRectHeight - targetUnobscuredRect.height()) / 2;
        newUnobscuredContentRect = FloatRect(newUnobscuredRectX, newUnobscuredRectY, newUnobscuredRectWidth, newUnobscuredRectHeight);

        // 2) Extend our new unobscuredRect by the obscured margins to get a new exposed rect.
        double obscuredTopMargin = (targetUnobscuredRect.y() - targetExposedContentRect.y()) * scaleDifference;
        double obscuredLeftMargin = (targetUnobscuredRect.x() - targetExposedContentRect.x()) * scaleDifference;
        double obscuredBottomMargin = (targetExposedContentRect.maxY() - targetUnobscuredRect.maxY()) * scaleDifference;
        double obscuredRightMargin = (targetExposedContentRect.maxX() - targetUnobscuredRect.maxX()) * scaleDifference;
        newExposedContentRect = FloatRect(newUnobscuredRectX - obscuredLeftMargin,
                                          newUnobscuredRectY - obscuredTopMargin,
                                          newUnobscuredRectWidth + obscuredLeftMargin + obscuredRightMargin,
                                          newUnobscuredRectHeight + obscuredTopMargin + obscuredBottomMargin);
    }

    if (oldContentSize != newContentSize || scaleChanged) {
        // Snap the new unobscured rect back into the content rect.
        newUnobscuredContentRect.setWidth(std::min(static_cast<float>(newContentSize.width()), newUnobscuredContentRect.width()));
        newUnobscuredContentRect.setHeight(std::min(static_cast<float>(newContentSize.height()), newUnobscuredContentRect.height()));

        bool positionWasRestoredFromSizeUpdateHistory = false;
        const auto& previousPosition = m_dynamicSizeUpdateHistory.find(std::pair<IntSize, float>(newContentSize, scale));
        if (previousPosition != m_dynamicSizeUpdateHistory.end()) {
            IntPoint restoredPosition = previousPosition->value;
            FloatPoint deltaPosition(restoredPosition.x() - newUnobscuredContentRect.x(), restoredPosition.y() - newUnobscuredContentRect.y());
            newUnobscuredContentRect.moveBy(deltaPosition);
            newExposedContentRect.moveBy(deltaPosition);
            positionWasRestoredFromSizeUpdateHistory = true;
        } else if (oldContentSize != newContentSize) {
            FloatPoint newRelativeContentCenter;

            if (RenderObject* renderer = oldNodeAtCenter ? oldNodeAtCenter->renderer() : nullptr) {
                FrameView& containingView = *oldNodeAtCenter->document().frame()->view();
                FloatRect newBoundingBox = containingView.contentsToRootView(renderer->absoluteBoundingBoxRect(true));
                newRelativeContentCenter = FloatPoint(newBoundingBox.x() + relativeHorizontalPositionInNodeAtCenter * newBoundingBox.width(), newBoundingBox.y() + relativeVerticalPositionInNodeAtCenter * newBoundingBox.height());
            } else
                newRelativeContentCenter = relativeCenterAfterContentSizeChange(targetUnobscuredRect, oldContentSize, newContentSize);

            FloatPoint newUnobscuredContentRectCenter = newUnobscuredContentRect.center();
            FloatPoint positionDelta(newRelativeContentCenter.x() - newUnobscuredContentRectCenter.x(), newRelativeContentCenter.y() - newUnobscuredContentRectCenter.y());
            newUnobscuredContentRect.moveBy(positionDelta);
            newExposedContentRect.moveBy(positionDelta);
        }

        // Make the top/bottom edges "sticky" within 1 pixel.
        if (!positionWasRestoredFromSizeUpdateHistory) {
            if (targetUnobscuredRect.maxY() > oldContentSize.height() - 1) {
                float bottomVerticalPosition = newContentSize.height() - newUnobscuredContentRect.height();
                newUnobscuredContentRect.setY(bottomVerticalPosition);
                newExposedContentRect.setY(bottomVerticalPosition);
            }
            if (targetUnobscuredRect.y() < 1) {
                newUnobscuredContentRect.setY(0);
                newExposedContentRect.setY(0);
            }

            bool likelyResponsiveDesignViewport = newLayoutSize.width() == viewLayoutSize.width() && areEssentiallyEqualAsFloat(scale, 1);
            bool contentBleedsOutsideLayoutWidth = newContentSize.width() > newLayoutSize.width();
            bool originalScrollPositionWasOnTheLeftEdge = targetUnobscuredRect.x() <= 0;
            if (likelyResponsiveDesignViewport && contentBleedsOutsideLayoutWidth && originalScrollPositionWasOnTheLeftEdge) {
                // This is a special heuristics for "responsive" design with odd layout. It is quite common for responsive design
                // to have content "bleeding" outside of the minimal layout width, usually from an image or table larger than expected.
                // In those cases, the design usually does not adapt to the new width and remain at the newLayoutSize except for the
                // large boxes.
                // It is worth revisiting this special case as web developers get better with responsive design.
                newExposedContentRect.setX(0);
                newUnobscuredContentRect.setX(0);
            }
        }

        float horizontalAdjustment = 0;
        if (newUnobscuredContentRect.maxX() > newContentSize.width())
            horizontalAdjustment -= newUnobscuredContentRect.maxX() - newContentSize.width();
        float verticalAdjustment = 0;
        if (newUnobscuredContentRect.maxY() > newContentSize.height())
            verticalAdjustment -= newUnobscuredContentRect.maxY() - newContentSize.height();
        if (newUnobscuredContentRect.x() < 0)
            horizontalAdjustment += - newUnobscuredContentRect.x();
        if (newUnobscuredContentRect.y() < 0)
            verticalAdjustment += - newUnobscuredContentRect.y();

        FloatPoint adjustmentDelta(horizontalAdjustment, verticalAdjustment);
        newUnobscuredContentRect.moveBy(adjustmentDelta);
        newExposedContentRect.moveBy(adjustmentDelta);
    }

    frameView.setScrollVelocity({ 0, 0, 0, MonotonicTime::now() });

    IntPoint roundedUnobscuredContentRectPosition = roundedIntPoint(newUnobscuredContentRect.location());
    frameView.setUnobscuredContentSize(newUnobscuredContentRect.size());
    m_drawingArea->setExposedContentRect(newExposedContentRect);

    scalePage(scale, roundedUnobscuredContentRectPosition);

    frameView.updateLayoutAndStyleIfNeededRecursive();

    auto& settings = frameView.frame().settings();
    LayoutRect documentRect = IntRect(frameView.scrollOrigin(), frameView.contentsSize());
    auto layoutViewportSize = FrameView::expandedLayoutViewportSize(frameView.baseLayoutViewportSize(), LayoutSize(documentRect.size()), settings.layoutViewportHeightExpansionFactor());
    LayoutRect layoutViewportRect = FrameView::computeUpdatedLayoutViewportRect(frameView.layoutViewportRect(), documentRect, LayoutSize(newUnobscuredContentRect.size()), LayoutRect(newUnobscuredContentRect), layoutViewportSize, frameView.minStableLayoutViewportOrigin(), frameView.maxStableLayoutViewportOrigin(), FrameView::LayoutViewportConstraint::ConstrainedToDocumentRect);
    frameView.setLayoutViewportOverrideRect(layoutViewportRect);
    frameView.layoutOrVisualViewportChanged();

    frameView.setCustomSizeForResizeEvent(expandedIntSize(targetUnobscuredRectInScrollViewCoordinates.size()));
    setDeviceOrientation(deviceOrientation);
    frameView.setScrollOffset(roundedUnobscuredContentRectPosition);

#if ENABLE(VIEWPORT_RESIZING)
    if (immediatelyShrinkToFitContent())
        viewportConfigurationChanged();
#endif

    m_drawingArea->scheduleCompositingLayerFlush();

    m_pendingDynamicViewportSizeUpdateID = dynamicViewportSizeUpdateID;
}

void WebPage::resetViewportDefaultConfiguration(WebFrame* frame, bool hasMobileDocType)
{
    LOG_WITH_STREAM(VisibleRects, stream << "WebPage " << m_pageID << " resetViewportDefaultConfiguration");
    if (m_useTestingViewportConfiguration) {
        m_viewportConfiguration.setDefaultConfiguration(ViewportConfiguration::testingParameters());
        return;
    }

    auto parametersForStandardFrame = [&] {
        if (shouldIgnoreMetaViewport())
            return m_viewportConfiguration.nativeWebpageParameters();
        return ViewportConfiguration::webpageParameters();
    };

    if (!frame) {
        m_viewportConfiguration.setDefaultConfiguration(parametersForStandardFrame());
        return;
    }

    if (hasMobileDocType) {
        m_viewportConfiguration.setDefaultConfiguration(ViewportConfiguration::xhtmlMobileParameters());
        return;
    }

    auto* document = frame->coreFrame()->document();
    if (document->isImageDocument())
        m_viewportConfiguration.setDefaultConfiguration(ViewportConfiguration::imageDocumentParameters());
    else if (document->isTextDocument())
        m_viewportConfiguration.setDefaultConfiguration(ViewportConfiguration::textDocumentParameters());
    else
        m_viewportConfiguration.setDefaultConfiguration(parametersForStandardFrame());
}

#if ENABLE(TEXT_AUTOSIZING)
void WebPage::resetIdempotentTextAutosizingIfNeeded(double previousInitialScale)
{
    if (!m_page->settings().textAutosizingEnabled() || !m_page->settings().textAutosizingUsesIdempotentMode())
        return;

    const float minimumScaleChangeBeforeRecomputingTextAutosizing = 0.01;
    if (std::abs(previousInitialScale - m_page->initialScale()) < minimumScaleChangeBeforeRecomputingTextAutosizing)
        return;

    if (m_page->initialScale() >= 1 && previousInitialScale >= 1)
        return;

    if (!m_page->mainFrame().view())
        return;

    auto textAutoSizingDelay = [&] {
        auto& frameView = *m_page->mainFrame().view();
        auto isVisaullyNonEmpty = frameView.isVisuallyNonEmpty();
        auto willBeVisuallyNonEmptySoon = !isVisaullyNonEmpty && frameView.qualifiesAsVisuallyNonEmpty();
        if (willBeVisuallyNonEmptySoon) {
            // Be a bit more agressive on the first display.
            const Seconds shortTextAutoSizingDelayOnViewportChange = 20_ms;
            return shortTextAutoSizingDelayOnViewportChange;
        } 
        if (!isVisaullyNonEmpty) {
            // We don't anticipate any paining after the next upcoming layout.
            const Seconds longTextAutoSizingDelayOnViewportChange = 100_ms;
            return longTextAutoSizingDelayOnViewportChange;
        }
        const Seconds defaultTextAutoSizingDelayOnViewportChange = 80_ms;
        return defaultTextAutoSizingDelayOnViewportChange;
    };

    // We don't need to update text sizing eagerly. There might be multiple incoming dynamic viewport changes.
    m_textAutoSizingAdjustmentTimer.startOneShot(textAutoSizingDelay());
}

void WebPage::resetTextAutosizing()
{
    for (Frame* frame = &m_page->mainFrame(); frame; frame = frame->tree().traverseNext()) {
        Document* document = frame->document();
        if (!document || !document->renderView())
            continue;
        document->renderView()->resetTextAutosizing();
    }
}
#endif

#if ENABLE(VIEWPORT_RESIZING)

void WebPage::scheduleShrinkToFitContent()
{
    if (m_isClosed)
        return;

    m_shrinkToFitContentTimer.restart();
}

void WebPage::shrinkToFitContentTimerFired()
{
    if (immediatelyShrinkToFitContent())
        viewportConfigurationChanged(ZoomToInitialScale::Yes);
}

bool WebPage::immediatelyShrinkToFitContent()
{
    if (m_isClosed)
        return false;

    if (!m_page->settings().allowViewportShrinkToFitContent())
        return false;

    if (m_useTestingViewportConfiguration)
        return false;

    if (!shouldIgnoreMetaViewport())
        return false;

    if (!m_viewportConfiguration.viewportArguments().shrinkToFit)
        return false;

    if (m_viewportConfiguration.canIgnoreScalingConstraints())
        return false;

    auto mainFrame = makeRefPtr(m_mainFrame->coreFrame());
    if (!mainFrame)
        return false;

    auto view = makeRefPtr(mainFrame->view());
    auto mainDocument = makeRefPtr(mainFrame->document());
    if (!view || !mainDocument)
        return false;

    mainDocument->updateLayout();

    static const int toleratedHorizontalScrollingDistance = 20;
    static const int maximumExpandedLayoutWidth = 1280;

    auto scaledViewWidth = [&] () -> int {
        return std::round(m_viewportConfiguration.viewLayoutSize().width() / m_viewportConfiguration.initialScale());
    };

    int originalContentWidth = view->contentsWidth();
    int originalViewWidth = scaledViewWidth();
    int originalLayoutWidth = m_viewportConfiguration.layoutWidth();
    int originalHorizontalOverflowAmount = originalContentWidth - originalViewWidth;
    if (originalHorizontalOverflowAmount <= toleratedHorizontalScrollingDistance || originalLayoutWidth >= maximumExpandedLayoutWidth || originalContentWidth <= originalViewWidth)
        return false;

    auto changeMinimumEffectiveDeviceWidth = [this, mainDocument] (int targetLayoutWidth) -> bool {
        if (m_viewportConfiguration.setMinimumEffectiveDeviceWidth(targetLayoutWidth)) {
            viewportConfigurationChanged();
            mainDocument->updateLayout();
            return true;
        }
        return false;
    };

    m_viewportConfiguration.setIsKnownToLayOutWiderThanViewport(true);
    double originalMinimumDeviceWidth = m_viewportConfiguration.minimumEffectiveDeviceWidth();
    if (changeMinimumEffectiveDeviceWidth(std::min(maximumExpandedLayoutWidth, originalContentWidth)) && view->contentsWidth() - scaledViewWidth() > originalHorizontalOverflowAmount) {
        changeMinimumEffectiveDeviceWidth(originalMinimumDeviceWidth);
        m_viewportConfiguration.setIsKnownToLayOutWiderThanViewport(false);
    }

    // FIXME (197429): Consider additionally logging an error message to the console if a responsive meta viewport tag was used.
    RELEASE_LOG(ViewportSizing, "Shrink-to-fit: content width %d => %d; layout width %d => %d", originalContentWidth, view->contentsWidth(), originalLayoutWidth, m_viewportConfiguration.layoutWidth());
    return true;
}

#endif // ENABLE(VIEWPORT_RESIZING)

bool WebPage::shouldIgnoreMetaViewport() const
{
    if (auto* mainDocument = m_page->mainFrame().document()) {
        auto* loader = mainDocument->loader();
        if (loader && loader->metaViewportPolicy() == WebCore::MetaViewportPolicy::Ignore)
            return true;
    }
    return m_page->settings().shouldIgnoreMetaViewport();
}

void WebPage::viewportConfigurationChanged(ZoomToInitialScale zoomToInitialScale)
{
    double initialScale = m_viewportConfiguration.initialScale();
#if ENABLE(TEXT_AUTOSIZING)
    double previousInitialScale = m_page->initialScale();
    m_page->setInitialScale(initialScale);
    resetIdempotentTextAutosizingIfNeeded(previousInitialScale);

    if (setFixedLayoutSize(m_viewportConfiguration.layoutSize()))
        resetTextAutosizing();
#endif
    double scale;
    if (m_userHasChangedPageScaleFactor && zoomToInitialScale == ZoomToInitialScale::No)
        scale = std::max(std::min(pageScaleFactor(), m_viewportConfiguration.maximumScale()), m_viewportConfiguration.minimumScale());
    else
        scale = initialScale;

    LOG_WITH_STREAM(VisibleRects, stream << "WebPage " << m_pageID << " viewportConfigurationChanged - setting zoomedOutPageScaleFactor to " << m_viewportConfiguration.minimumScale() << " and scale to " << scale);

    m_page->setZoomedOutPageScaleFactor(m_viewportConfiguration.minimumScale());

    updateViewportSizeForCSSViewportUnits();

    FrameView& frameView = *mainFrameView();
    IntPoint scrollPosition = frameView.scrollPosition();
    if (!m_hasReceivedVisibleContentRectsAfterDidCommitLoad) {
        FloatSize minimumLayoutSizeInScrollViewCoordinates = m_viewportConfiguration.viewLayoutSize();
        minimumLayoutSizeInScrollViewCoordinates.scale(1 / scale);
        IntSize minimumLayoutSizeInDocumentCoordinates = roundedIntSize(minimumLayoutSizeInScrollViewCoordinates);
        frameView.setUnobscuredContentSize(minimumLayoutSizeInDocumentCoordinates);
        frameView.setScrollVelocity({ 0, 0, 0, MonotonicTime::now() });

        // FIXME: We could send down the obscured margins to find a better exposed rect and unobscured rect.
        // It is not a big deal at the moment because the tile coverage will always extend past the obscured bottom inset.
        if (!m_hasRestoredExposedContentRectAfterDidCommitLoad)
            m_drawingArea->setExposedContentRect(FloatRect(scrollPosition, minimumLayoutSizeInDocumentCoordinates));
    }
    scalePage(scale, scrollPosition);
    
    if (!m_hasReceivedVisibleContentRectsAfterDidCommitLoad) {
        // This takes scale into account, so do after the scale change.
        frameView.setCustomFixedPositionLayoutRect(enclosingIntRect(frameView.viewportConstrainedObjectsRect()));

        frameView.setCustomSizeForResizeEvent(expandedIntSize(m_viewportConfiguration.minimumLayoutSize()));
    }
}

void WebPage::updateViewportSizeForCSSViewportUnits()
{
    FloatSize largestUnobscuredSize = m_maximumUnobscuredSize;
    if (largestUnobscuredSize.isEmpty())
        largestUnobscuredSize = m_viewportConfiguration.viewLayoutSize();

    FrameView& frameView = *mainFrameView();
    largestUnobscuredSize.scale(1 / m_viewportConfiguration.initialScaleIgnoringContentSize());
    frameView.setViewportSizeForCSSViewportUnits(roundedIntSize(largestUnobscuredSize));
}

void WebPage::applicationWillResignActive()
{
    [[NSNotificationCenter defaultCenter] postNotificationName:WebUIApplicationWillResignActiveNotification object:nil];
    if (m_page)
        m_page->applicationWillResignActive();
}

void WebPage::applicationDidEnterBackground(bool isSuspendedUnderLock)
{
    [[NSNotificationCenter defaultCenter] postNotificationName:WebUIApplicationDidEnterBackgroundNotification object:nil userInfo:@{@"isSuspendedUnderLock": [NSNumber numberWithBool:isSuspendedUnderLock]}];

    m_isSuspendedUnderLock = isSuspendedUnderLock;
    freezeLayerTree(LayerTreeFreezeReason::BackgroundApplication);

    if (m_page)
        m_page->applicationDidEnterBackground();
}

void WebPage::applicationDidFinishSnapshottingAfterEnteringBackground()
{
    markLayersVolatile();
}

void WebPage::applicationWillEnterForeground(bool isSuspendedUnderLock)
{
    m_isSuspendedUnderLock = false;
    cancelMarkLayersVolatile();

    unfreezeLayerTree(LayerTreeFreezeReason::BackgroundApplication);

    [[NSNotificationCenter defaultCenter] postNotificationName:WebUIApplicationWillEnterForegroundNotification object:nil userInfo:@{@"isSuspendedUnderLock": @(isSuspendedUnderLock)}];

    if (m_page)
        m_page->applicationWillEnterForeground();
}

void WebPage::applicationDidBecomeActive()
{
    [[NSNotificationCenter defaultCenter] postNotificationName:WebUIApplicationDidBecomeActiveNotification object:nil];
    if (m_page)
        m_page->applicationDidBecomeActive();
}

static inline void adjustVelocityDataForBoundedScale(VelocityData& velocityData, double exposedRectScale, double minimumScale, double maximumScale)
{
    if (velocityData.scaleChangeRate) {
        velocityData.horizontalVelocity = 0;
        velocityData.verticalVelocity = 0;
    }

    if (exposedRectScale >= maximumScale || exposedRectScale <= minimumScale)
        velocityData.scaleChangeRate = 0;
}

Optional<float> WebPage::scaleFromUIProcess(const VisibleContentRectUpdateInfo& visibleContentRectUpdateInfo) const
{
    auto transactionIDForLastScaleFromUIProcess = visibleContentRectUpdateInfo.lastLayerTreeTransactionID();
    if (m_lastTransactionIDWithScaleChange > transactionIDForLastScaleFromUIProcess)
        return WTF::nullopt;

    float scaleFromUIProcess = visibleContentRectUpdateInfo.scale();
    float currentScale = m_page->pageScaleFactor();

    double scaleNoiseThreshold = 0.005;
    if (!m_isInStableState && fabs(scaleFromUIProcess - currentScale) < scaleNoiseThreshold) {
        // Tiny changes of scale during interactive zoom cause content to jump by one pixel, creating
        // visual noise. We filter those useless updates.
        scaleFromUIProcess = currentScale;
    }
    
    scaleFromUIProcess = std::min<float>(m_viewportConfiguration.maximumScale(), std::max<float>(m_viewportConfiguration.minimumScale(), scaleFromUIProcess));
    if (areEssentiallyEqualAsFloat(currentScale, scaleFromUIProcess))
        return WTF::nullopt;

    return scaleFromUIProcess;
}

static bool selectionIsInsideFixedPositionContainer(Frame& frame)
{
    auto& selection = frame.selection().selection();
    if (selection.isNone())
        return false;

    bool isInsideFixedPosition = false;
    if (selection.isCaret()) {
        frame.selection().absoluteCaretBounds(&isInsideFixedPosition);
        return isInsideFixedPosition;
    }

    selection.visibleStart().absoluteCaretBounds(&isInsideFixedPosition);
    if (isInsideFixedPosition)
        return true;

    selection.visibleEnd().absoluteCaretBounds(&isInsideFixedPosition);
    return isInsideFixedPosition;
}

void WebPage::updateVisibleContentRects(const VisibleContentRectUpdateInfo& visibleContentRectUpdateInfo, MonotonicTime oldestTimestamp)
{
    LOG_WITH_STREAM(VisibleRects, stream << "\nWebPage " << m_pageID << " updateVisibleContentRects " << visibleContentRectUpdateInfo);

    // Skip any VisibleContentRectUpdate that have been queued before DidCommitLoad suppresses the updates in the UIProcess.
    if (visibleContentRectUpdateInfo.lastLayerTreeTransactionID() < m_mainFrame->firstLayerTreeTransactionIDAfterDidCommitLoad() && !visibleContentRectUpdateInfo.isFirstUpdateForNewViewSize())
        return;

    m_hasReceivedVisibleContentRectsAfterDidCommitLoad = true;
    m_isInStableState = visibleContentRectUpdateInfo.inStableState();

    auto scaleFromUIProcess = this->scaleFromUIProcess(visibleContentRectUpdateInfo);

    // Skip progressively redrawing tiles if pinch-zooming while the system is under memory pressure.
    if (scaleFromUIProcess && !m_isInStableState && MemoryPressureHandler::singleton().isUnderMemoryPressure())
        return;

    if (m_isInStableState)
        m_hasStablePageScaleFactor = true;
    else {
        if (!m_oldestNonStableUpdateVisibleContentRectsTimestamp)
            m_oldestNonStableUpdateVisibleContentRectsTimestamp = oldestTimestamp;
    }

    float scaleToUse = scaleFromUIProcess.valueOr(m_page->pageScaleFactor());
    FloatRect exposedContentRect = visibleContentRectUpdateInfo.exposedContentRect();
    FloatRect adjustedExposedContentRect = adjustExposedRectForNewScale(exposedContentRect, visibleContentRectUpdateInfo.scale(), scaleToUse);
    m_drawingArea->setExposedContentRect(adjustedExposedContentRect);

    IntPoint scrollPosition = roundedIntPoint(visibleContentRectUpdateInfo.unobscuredContentRect().location());

    bool hasSetPageScale = false;
    if (scaleFromUIProcess) {
        m_scaleWasSetByUIProcess = true;
        m_hasStablePageScaleFactor = m_isInStableState;

        m_dynamicSizeUpdateHistory.clear();

        m_page->setPageScaleFactor(scaleFromUIProcess.value(), scrollPosition, m_isInStableState);
        hasSetPageScale = true;
        send(Messages::WebPageProxy::PageScaleFactorDidChange(scaleFromUIProcess.value()));
    }
    
    if (!hasSetPageScale && m_isInStableState) {
        m_page->setPageScaleFactor(scaleToUse, scrollPosition, true);
        hasSetPageScale = true;
    }

    auto& frame = m_page->mainFrame();
    FrameView& frameView = *frame.view();
    if (scrollPosition != frameView.scrollPosition())
        m_dynamicSizeUpdateHistory.clear();

    if (m_viewportConfiguration.setCanIgnoreScalingConstraints(m_ignoreViewportScalingConstraints || visibleContentRectUpdateInfo.allowShrinkToFit()))
        viewportConfigurationChanged();

    frameView.setUnobscuredContentSize(visibleContentRectUpdateInfo.unobscuredContentRect().size());
    m_page->setContentInsets(visibleContentRectUpdateInfo.contentInsets());
    m_page->setObscuredInsets(visibleContentRectUpdateInfo.obscuredInsets());
    m_page->setUnobscuredSafeAreaInsets(visibleContentRectUpdateInfo.unobscuredSafeAreaInsets());
    m_page->setEnclosedInScrollableAncestorView(visibleContentRectUpdateInfo.enclosedInScrollableAncestorView());

    VelocityData scrollVelocity = visibleContentRectUpdateInfo.scrollVelocity();
    adjustVelocityDataForBoundedScale(scrollVelocity, visibleContentRectUpdateInfo.scale(), m_viewportConfiguration.minimumScale(), m_viewportConfiguration.maximumScale());
    frameView.setScrollVelocity(scrollVelocity);

    if (m_isInStableState) {
        if (visibleContentRectUpdateInfo.unobscuredContentRect() != visibleContentRectUpdateInfo.unobscuredContentRectRespectingInputViewBounds())
            frameView.setVisualViewportOverrideRect(LayoutRect(visibleContentRectUpdateInfo.unobscuredContentRectRespectingInputViewBounds()));
        else
            frameView.setVisualViewportOverrideRect(WTF::nullopt);

        LOG_WITH_STREAM(VisibleRects, stream << "WebPage::updateVisibleContentRects - setLayoutViewportOverrideRect " << visibleContentRectUpdateInfo.customFixedPositionRect());
        frameView.setLayoutViewportOverrideRect(LayoutRect(visibleContentRectUpdateInfo.customFixedPositionRect()));
        if (selectionIsInsideFixedPositionContainer(frame)) {
            // Ensure that the next layer tree commit contains up-to-date caret/selection rects.
            frameView.frame().selection().setCaretRectNeedsUpdate();
            scheduleFullEditorStateUpdate();
        }

        frameView.layoutOrVisualViewportChanged();
    }

    if (!visibleContentRectUpdateInfo.isChangingObscuredInsetsInteractively())
        frameView.setCustomSizeForResizeEvent(expandedIntSize(visibleContentRectUpdateInfo.unobscuredRectInScrollViewCoordinates().size()));

    if (ScrollingCoordinator* scrollingCoordinator = this->scrollingCoordinator()) {
        ViewportRectStability viewportStability = ViewportRectStability::Stable;
        ScrollingLayerPositionAction layerAction = ScrollingLayerPositionAction::Sync;
        
        if (visibleContentRectUpdateInfo.isChangingObscuredInsetsInteractively()) {
            viewportStability = ViewportRectStability::ChangingObscuredInsetsInteractively;
            layerAction = ScrollingLayerPositionAction::SetApproximate;
        } else if (!m_isInStableState) {
            viewportStability = ViewportRectStability::Unstable;
            layerAction = ScrollingLayerPositionAction::SetApproximate;
        }
        scrollingCoordinator->reconcileScrollingState(frameView, scrollPosition, visibleContentRectUpdateInfo.customFixedPositionRect(), ScrollType::User, viewportStability, layerAction);
    }
}

void WebPage::willStartUserTriggeredZooming()
{
    m_page->diagnosticLoggingClient().logDiagnosticMessage(DiagnosticLoggingKeys::webViewKey(), DiagnosticLoggingKeys::userZoomActionKey(), ShouldSample::No);
    m_userHasChangedPageScaleFactor = true;
}

#if ENABLE(IOS_TOUCH_EVENTS)
void WebPage::dispatchAsynchronousTouchEvents(const Vector<WebTouchEvent, 1>& queue)
{
    bool ignored;
    for (const WebTouchEvent& event : queue)
        dispatchTouchEvent(event, ignored);
}
#endif

void WebPage::computePagesForPrintingAndDrawToPDF(WebCore::FrameIdentifier frameID, const PrintInfo& printInfo, CallbackID callbackID, Messages::WebPage::ComputePagesForPrintingAndDrawToPDF::DelayedReply&& reply)
{
    if (printInfo.snapshotFirstPage) {
        reply(1);
        IntSize snapshotSize { FloatSize { printInfo.availablePaperWidth, printInfo.availablePaperHeight } };
        IntRect snapshotRect { {0, 0}, snapshotSize };

        auto& frameView = *m_page->mainFrame().view();
        auto originalLayoutViewportOverrideRect = frameView.layoutViewportOverrideRect();
        frameView.setLayoutViewportOverrideRect(LayoutRect(snapshotRect));

        auto pdfData = pdfSnapshotAtSize(snapshotRect, snapshotSize, 0);

        frameView.setLayoutViewportOverrideRect(originalLayoutViewportOverrideRect);
        send(Messages::WebPageProxy::DrawToPDFCallback(IPC::DataReference(CFDataGetBytePtr(pdfData.get()), CFDataGetLength(pdfData.get())), callbackID));
        return;
    }

    Vector<WebCore::IntRect> pageRects;
    double totalScaleFactor;
    auto margin = printInfo.margin;
    computePagesForPrintingImpl(frameID, printInfo, pageRects, totalScaleFactor, margin);

    ASSERT(pageRects.size() >= 1);
    std::size_t pageCount = pageRects.size();
    ASSERT(pageCount <= std::numeric_limits<uint32_t>::max());
    reply(pageCount);

    RetainPtr<CFMutableDataRef> pdfPageData;
    drawPagesToPDFImpl(frameID, printInfo, 0, pageCount, pdfPageData);
    send(Messages::WebPageProxy::DrawToPDFCallback(IPC::DataReference(CFDataGetBytePtr(pdfPageData.get()), CFDataGetLength(pdfPageData.get())), callbackID));

    endPrinting();
}

void WebPage::contentSizeCategoryDidChange(const String& contentSizeCategory)
{
    RenderThemeIOS::setContentSizeCategory(contentSizeCategory);
    Page::updateStyleForAllPagesAfterGlobalChangeInEnvironment();
}

String WebPage::platformUserAgent(const URL&) const
{
    if (!m_page->settings().needsSiteSpecificQuirks())
        return String();

    auto document = m_mainFrame->coreFrame()->document();
    if (!document)
        return String();

    if (document->quirks().shouldAvoidUsingIOS13ForGmail() && osNameForUserAgent() == "iPhone OS")
        return standardUserAgentWithApplicationName({ }, "12_1_3");

    return String();
}

void WebPage::hardwareKeyboardAvailabilityChanged(bool keyboardIsAttached)
{
    m_keyboardIsAttached = keyboardIsAttached;

    if (auto* focusedFrame = m_page->focusController().focusedFrame())
        focusedFrame->eventHandler().capsLockStateMayHaveChanged();
}

void WebPage::updateStringForFind(const String& findString)
{
    send(Messages::WebPageProxy::UpdateStringForFind(findString));
}

#if USE(QUICK_LOOK)
void WebPage::didReceivePasswordForQuickLookDocument(const String& password)
{
    WebPreviewLoaderClient::didReceivePassword(password, m_pageID);
}
#endif

bool WebPage::platformPrefersTextLegibilityBasedZoomScaling() const
{
#if PLATFORM(WATCHOS)
    return true;
#else
    return false;
#endif
}

void WebPage::updateSelectionWithDelta(int64_t locationDelta, int64_t lengthDelta, CompletionHandler<void()>&& completionHandler)
{
    Ref<Frame> frame = corePage()->focusController().focusedOrMainFrame();
    VisibleSelection selection = frame->selection().selection();
    if (selection.isNone()) {
        completionHandler();
        return;
    }

    auto root = frame->selection().rootEditableElementOrDocumentElement();
    auto range = selection.toNormalizedRange();
    if (!root || !range) {
        completionHandler();
        return;
    }

    size_t selectionLocation;
    size_t selectionLength;
    TextIterator::getLocationAndLengthFromRange(root, range.get(), selectionLocation, selectionLength);

    CheckedInt64 newSelectionLocation { selectionLocation };
    CheckedInt64 newSelectionLength { selectionLength };
    newSelectionLocation += locationDelta;
    newSelectionLength += lengthDelta;

    if (newSelectionLocation.hasOverflowed() || newSelectionLength.hasOverflowed()) {
        completionHandler();
        return;
    }

    if (auto range = TextIterator::rangeFromLocationAndLength(root, newSelectionLocation.unsafeGet(), newSelectionLength.unsafeGet()))
        frame->selection().setSelectedRange(range.get(), DOWNSTREAM, WebCore::FrameSelection::ShouldCloseTyping::Yes, UserTriggered);

    completionHandler();
}

static VisiblePosition moveByGranularityRespectingWordBoundary(Frame& frame, VisiblePosition& position, TextGranularity granularity, uint64_t granularityCount, SelectionDirection direction)
{
    bool backwards = direction == DirectionBackward;
    auto farthestPositionInDirection = backwards ? startOfEditableContent(position) : endOfEditableContent(position);
    if (position == farthestPositionInDirection)
        return { };

    VisiblePosition currentPosition = position;
    VisiblePosition nextPosition;
    for (unsigned i = 0; i < granularityCount + 1; ++i) {
        nextPosition = positionOfNextBoundaryOfGranularity(currentPosition, granularity, direction);
        // FIXME (196127): We shouldn't need to do this, but have seen previousParagraphPosition go forwards.
        if ((backwards && nextPosition > currentPosition) || (!backwards && nextPosition < currentPosition))
            break;
        if (nextPosition.isNull())
            break;
        currentPosition = nextPosition;
    }

    return backwards ? startOfWord(currentPosition) : endOfWord(currentPosition);
}

static VisiblePosition visiblePositionForPointInRootViewCoordinates(Frame& frame, FloatPoint pointInRootViewCoordinates)
{
    auto pointInDocument = frame.view()->rootViewToContents(roundedIntPoint(pointInRootViewCoordinates));
    return frame.visiblePositionForPoint(pointInDocument);
}

void WebPage::requestDocumentEditingContext(DocumentEditingContextRequest request, CompletionHandler<void(DocumentEditingContext)>&& completionHandler)
{
    if (!request.options.contains(DocumentEditingContextRequest::Options::Text) && !request.options.contains(DocumentEditingContextRequest::Options::AttributedText)) {
        completionHandler({ });
        return;
    }

    m_page->focusController().focusedOrMainFrame().document()->updateLayoutIgnorePendingStylesheets();

    Ref<Frame> frame = m_page->focusController().focusedOrMainFrame();
    VisibleSelection selection = frame->selection().selection();

    VisiblePosition rangeOfInterestStart;
    VisiblePosition rangeOfInterestEnd;
    VisiblePosition selectionStart = selection.visibleStart();
    VisiblePosition selectionEnd = selection.visibleEnd();

    bool isSpatialRequest = request.options.contains(DocumentEditingContextRequest::Options::Spatial);
    bool wantsRects = request.options.contains(DocumentEditingContextRequest::Options::Rects);

    if (auto textInputContext = request.textInputContext) {
        RefPtr<Element> element = elementForTextInputContext(*textInputContext);
        if (!element) {
            completionHandler({ });
            return;
        }
        if (is<HTMLTextFormControlElement>(element)) {
            auto& textFormControlElement = downcast<HTMLTextFormControlElement>(*element);
            rangeOfInterestStart = textFormControlElement.visiblePositionForIndex(0);
            rangeOfInterestEnd = textFormControlElement.visiblePositionForIndex(textFormControlElement.value().length());
        } else {
            rangeOfInterestStart = firstPositionInOrBeforeNode(element.get());
            rangeOfInterestEnd = lastPositionInOrAfterNode(element.get());
        }
    } else if (isSpatialRequest) {
        // FIXME: We might need to be a bit more careful that we get something useful (test the other corners?).
        rangeOfInterestStart = visiblePositionForPointInRootViewCoordinates(frame.get(), request.rect.minXMinYCorner());
        rangeOfInterestEnd = visiblePositionForPointInRootViewCoordinates(frame.get(), request.rect.maxXMaxYCorner());
        if (rangeOfInterestEnd < rangeOfInterestStart)
            std::exchange(rangeOfInterestStart, rangeOfInterestEnd);
    } else if (!selection.isNone()) {
        rangeOfInterestStart = selectionStart;
        rangeOfInterestEnd = selectionEnd;
    }

    if (rangeOfInterestStart.isNull() || rangeOfInterestStart.isOrphan() || rangeOfInterestEnd.isNull() || rangeOfInterestEnd.isOrphan()) {
        completionHandler({ });
        return;
    }

    DocumentEditingContext context;

    // The subset of the selection that is inside the range of interest.
    VisiblePosition startOfRangeOfInterestInSelection;
    VisiblePosition endOfRangeOfInterestInSelection;

    auto selectionRange = selection.toNormalizedRange();
    auto rangeOfInterest = makeRange(rangeOfInterestStart, rangeOfInterestEnd);
    if (selectionRange && rangesOverlap(rangeOfInterest.get(), selectionRange.get())) {
        startOfRangeOfInterestInSelection = rangeOfInterestStart > selectionStart ? rangeOfInterestStart : selectionStart;
        endOfRangeOfInterestInSelection = rangeOfInterestEnd < selectionEnd ? rangeOfInterestEnd : selectionEnd;
    } else {
        size_t rangeOfInterestLocation;
        size_t rangeOfInterestLength;
        RefPtr<Node> rootNode = rangeOfInterest->commonAncestorContainer();
        if (!rootNode) {
            completionHandler({ });
            return;
        }

        RefPtr<ContainerNode> rootContainerNode = rootNode->isContainerNode() ? downcast<ContainerNode>(rootNode.get()) : rootNode->parentNode();
        TextIterator::getLocationAndLengthFromRange(rootContainerNode.get(), rangeOfInterest.get(), rangeOfInterestLocation, rangeOfInterestLength);

        CheckedSize midpointLocation { rangeOfInterestLocation };
        midpointLocation += rangeOfInterestLength / 2;
        if (midpointLocation.hasOverflowed()) {
            completionHandler({ });
            return;
        }

        auto midpointRange = TextIterator::rangeFromLocationAndLength(rootContainerNode.get(), midpointLocation.unsafeGet(), 0);

        auto midpoint = midpointRange->startPosition();
        startOfRangeOfInterestInSelection = startOfWord(midpoint);
        if (startOfRangeOfInterestInSelection < rangeOfInterestStart) {
            startOfRangeOfInterestInSelection = endOfWord(midpoint);
            if (startOfRangeOfInterestInSelection > rangeOfInterestEnd)
                startOfRangeOfInterestInSelection = midpoint;
        }

        endOfRangeOfInterestInSelection = startOfRangeOfInterestInSelection;
    }

    VisiblePosition contextBeforeStart;
    VisiblePosition contextAfterEnd;
    if (request.granularityCount) {
        contextBeforeStart = moveByGranularityRespectingWordBoundary(frame.get(), rangeOfInterestStart, request.surroundingGranularity, request.granularityCount, DirectionBackward);
        contextAfterEnd = moveByGranularityRespectingWordBoundary(frame.get(), rangeOfInterestEnd, request.surroundingGranularity, request.granularityCount, DirectionForward);
    } else {
        contextBeforeStart = rangeOfInterestStart;
        contextAfterEnd = rangeOfInterestEnd;
    }

    auto makeString = [&](VisiblePosition& start, VisiblePosition& end) -> NSAttributedString * {
        if (start.isNull() || end.isNull() || start == end)
            return nil;
        // FIXME: This should return editing-offset-compatible attributed strings if that option is requested.
        return adoptNS([[NSAttributedString alloc] initWithString:plainTextReplacingNoBreakSpace(start.deepEquivalent(), end.deepEquivalent())]).autorelease();
    };

    context.contextBefore = makeString(contextBeforeStart, startOfRangeOfInterestInSelection);
    context.selectedText = makeString(startOfRangeOfInterestInSelection, endOfRangeOfInterestInSelection);
    context.contextAfter = makeString(endOfRangeOfInterestInSelection, contextAfterEnd);

    auto compositionRange = frame->editor().compositionRange();
    if (compositionRange && rangesOverlap(rangeOfInterest.get(), compositionRange.get())) {
        VisiblePosition compositionStart(compositionRange->startPosition());
        VisiblePosition compositionEnd(compositionRange->endPosition());

        VisiblePosition relevantCompositionStart = rangeOfInterestStart > compositionStart ? rangeOfInterestStart : compositionStart;
        VisiblePosition relevantCompositionEnd = rangeOfInterestEnd < compositionEnd ? rangeOfInterestEnd : compositionEnd;

        context.markedText = makeString(relevantCompositionStart, relevantCompositionEnd);
        context.selectedRangeInMarkedText.location = distanceBetweenPositions(relevantCompositionStart, startOfRangeOfInterestInSelection);
        context.selectedRangeInMarkedText.length = [context.selectedText.string length];
    }

    if (wantsRects) {
        CharacterIterator contextIterator(contextBeforeStart.deepEquivalent(), contextAfterEnd.deepEquivalent());
        unsigned currentLocation = 0;
        while (!contextIterator.atEnd()) {
            unsigned length = contextIterator.text().length();
            if (!length) {
                contextIterator.advance(1);
                continue;
            }

            DocumentEditingContext::TextRectAndRange rect;
            rect.rect = contextIterator.range()->absoluteBoundingBox();
            rect.range = { currentLocation, 1 };
            context.textRects.append(rect);

            currentLocation++;
            contextIterator.advance(1);
        }
    }

#if ENABLE(PLATFORM_DRIVEN_TEXT_CHECKING)
    if (request.options.contains(DocumentEditingContextRequest::Options::Annotation))
        context.annotatedText = m_textCheckingControllerProxy->annotatedSubstringBetweenPositions(contextBeforeStart, contextAfterEnd);
#endif

    completionHandler(context);
}

} // namespace WebKit

#undef RELEASE_LOG_IF_ALLOWED
#undef RELEASE_LOG_ERROR_IF_ALLOWED

#endif // PLATFORM(IOS_FAMILY)
