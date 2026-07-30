import SwiftUI
import WebKit

#if os(macOS)

/// WKWebView-based preview for macOS.
struct PreviewWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    var scrollFraction: CGFloat
    var jump: HeadingJump?
    var onScrollChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Allow scrolling observation via JS
        let script = WKUserScript(
            source: Self.scrollObserverJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(script)
        webView.configuration.userContentController.add(
            context.coordinator,
            name: "scrollHandler"
        )

        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.performJumpIfNeeded(jump, in: webView)
        // Only reload if HTML changed
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            // Save scroll position, reload, restore
            webView.evaluateJavaScript("document.documentElement.scrollTop / (document.documentElement.scrollHeight - document.documentElement.clientHeight)") { result, _ in
                context.coordinator.savedScrollFraction = (result as? CGFloat) ?? self.scrollFraction
                webView.loadHTMLString(html, baseURL: self.baseURL)
            }
        }
    }

    static let scrollObserverJS = """
    window.addEventListener('scroll', function() {
        var scrollFraction = document.documentElement.scrollTop /
            Math.max(1, document.documentElement.scrollHeight - document.documentElement.clientHeight);
        window.webkit.messageHandlers.scrollHandler.postMessage(scrollFraction);
    });
    """

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: PreviewWebView
        weak var webView: WKWebView?
        var lastHTML: String = ""
        var savedScrollFraction: CGFloat = 0

        init(_ parent: PreviewWebView) {
            self.parent = parent
        }

        /// Scroll to a heading the sidebar selected, once per request token.
        var lastJumpToken: Int?
        /// A jump requested while the page was still loading, replayed on finish.
        var pendingJump: HeadingJump?

        func performJumpIfNeeded(_ jump: HeadingJump?, in webView: WKWebView) {
            guard let jump, jump.token != lastJumpToken else { return }
            lastJumpToken = jump.token
            if webView.isLoading {
                // The element does not exist yet; replay once the load finishes.
                pendingJump = jump
                return
            }
            scroll(to: jump, in: webView)
        }

        func scroll(to jump: HeadingJump, in webView: WKWebView) {
            // Navigate by document-order index rather than slug, so this never
            // depends on slug text agreeing between source and rendered HTML.
            let js = """
            (function() {
                var el = document.querySelector('[data-heading-index="\(jump.headingIndex)"]');
                if (el) { el.scrollIntoView({ block: 'start' }); }
            })();
            """
            webView.evaluateJavaScript(js)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // A jump takes priority over restoring the previous scroll position:
            // the user just asked to be somewhere specific.
            if let pending = pendingJump {
                pendingJump = nil
                scroll(to: pending, in: webView)
                return
            }
            // Restore scroll position after load
            let fraction = savedScrollFraction
            let js = """
            document.documentElement.scrollTop = \(fraction) *
                (document.documentElement.scrollHeight - document.documentElement.clientHeight);
            """
            webView.evaluateJavaScript(js)
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences
        ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                await UIApplication.shared.open(url)
                #endif
                return (.cancel, preferences)
            } else {
                return (.allow, preferences)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if let fraction = message.body as? Double {
                parent.onScrollChange?(CGFloat(fraction))
            }
        }
    }
}

#else

/// WKWebView-based preview for iOS.
struct PreviewWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    var scrollFraction: CGFloat
    var jump: HeadingJump?
    var onScrollChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        context.coordinator.webView = webView

        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.performJumpIfNeeded(jump, in: webView)
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.evaluateJavaScript("document.documentElement.scrollTop / Math.max(1, document.documentElement.scrollHeight - document.documentElement.clientHeight)") { result, _ in
                context.coordinator.savedScrollFraction = (result as? CGFloat) ?? self.scrollFraction
                webView.loadHTMLString(html, baseURL: self.baseURL)
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        var parent: PreviewWebView
        weak var webView: WKWebView?
        var lastHTML: String = ""
        var savedScrollFraction: CGFloat = 0

        init(_ parent: PreviewWebView) {
            self.parent = parent
        }

        /// Scroll to a heading the sidebar selected, once per request token.
        var lastJumpToken: Int?
        /// A jump requested while the page was still loading, replayed on finish.
        var pendingJump: HeadingJump?

        func performJumpIfNeeded(_ jump: HeadingJump?, in webView: WKWebView) {
            guard let jump, jump.token != lastJumpToken else { return }
            lastJumpToken = jump.token
            if webView.isLoading {
                // The element does not exist yet; replay once the load finishes.
                pendingJump = jump
                return
            }
            scroll(to: jump, in: webView)
        }

        func scroll(to jump: HeadingJump, in webView: WKWebView) {
            // Navigate by document-order index rather than slug, so this never
            // depends on slug text agreeing between source and rendered HTML.
            let js = """
            (function() {
                var el = document.querySelector('[data-heading-index="\(jump.headingIndex)"]');
                if (el) { el.scrollIntoView({ block: 'start' }); }
            })();
            """
            webView.evaluateJavaScript(js)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let pending = pendingJump {
                pendingJump = nil
                scroll(to: pending, in: webView)
                return
            }
            let fraction = savedScrollFraction
            let js = """
            document.documentElement.scrollTop = \(fraction) *
                (document.documentElement.scrollHeight - document.documentElement.clientHeight);
            """
            webView.evaluateJavaScript(js)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let contentHeight = scrollView.contentSize.height
            let visibleHeight = scrollView.bounds.height
            guard contentHeight > visibleHeight else { return }
            let fraction = scrollView.contentOffset.y / (contentHeight - visibleHeight)
            parent.onScrollChange?(max(0, min(1, fraction)))
        }
    }
}

#endif
