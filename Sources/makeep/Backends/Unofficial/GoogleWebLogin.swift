import AppKit
import WebKit

/// Shows Google's EmbeddedSetup sign-in page and returns the `oauth_token` cookie it sets,
/// which `AndroidAuth.exchangeToken` turns into a master token. Also picks up the account's
/// email from the page, since the token exchange needs it and the cookie doesn't carry it.
final class GoogleWebLogin: NSObject, NSWindowDelegate, WKScriptMessageHandler {
    struct Result {
        var oauthToken: String
        var email: String?
    }

    private static let messageName = "makeepEmail"

    /// The email/username box. On the EmbeddedSetup flow it's `<input type="text" id="identifierId">`.
    private static let identifierSelector = "#identifierId, input[name=identifier], input[type=email]"

    /// Reports the email typed into the identifier box, and the canonical one Google shows
    /// on later steps (`data-email`), which covers usernames typed without "@gmail.com".
    private static let emailScript = """
    (function () {
      var IDENTIFIER = '\(identifierSelector)';
      var last = null;
      function post(value) {
        if (!value) return;
        value = value.trim();
        if (value.indexOf('@') < 1 || value === last) return;
        last = value;
        window.webkit.messageHandlers.\(messageName).postMessage(value);
      }
      function onField(e) { if (e.target && e.target.matches && e.target.matches(IDENTIFIER)) post(e.target.value); }
      document.addEventListener('input', onField, true);
      document.addEventListener('change', onField, true);
      function scan() {
        var el = document.querySelector('[data-email]');
        if (el) post(el.getAttribute('data-email'));
      }
      scan();
      new MutationObserver(scan).observe(document.documentElement, { subtree: true, childList: true });
    })();
    """

    /// Google renders its sign-in fields after load, so wait for one to appear and focus it
    /// (unless the user has already clicked into something).
    private static let focusScript = """
    (function () {
      var tries = 0;
      var timer = setInterval(function () {
        var field = document.querySelector('\(identifierSelector), input[type="password"]');
        if (field && field.offsetParent !== null) {
          clearInterval(timer);
          if (!document.activeElement || document.activeElement === document.body) field.focus();
        } else if (++tries > 50) {
          clearInterval(timer);
        }
      }, 100);
    })();
    """

    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Result, Error>?
    private var pollTask: Task<Void, Never>?
    private var email: String?

    func run() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            // Run our scripts and message handler in an isolated content world: they share the DOM,
            // but the page can't see them. Google refuses sign-in ("This browser or app may not be
            // secure") when it detects an embedded web view, e.g. via window.webkit.messageHandlers.
            let controller = configuration.userContentController
            controller.add(self, contentWorld: .defaultClient, name: Self.messageName)
            for source in [Self.emailScript, Self.focusScript] {
                controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd,
                                                      forMainFrameOnly: true, in: .defaultClient))
            }
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: configuration)
            // Google refuses sign-in from user agents it doesn't recognize as a browser.
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
            #if DEBUG
            webView.isInspectable = true
            #endif
            self.webView = webView

            let window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Sign in to Google Keep"
            window.contentView = webView
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.level = .floating
            self.window = window

            bringToFront()
            webView.load(URLRequest(url: URL(string: "https://accounts.google.com/EmbeddedSetup")!))

            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(750))
                    await self?.checkForToken()
                }
            }
        }
    }

    private func bringToFront() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)  // Otherwise keystrokes don't reach the page.
    }

    private func checkForToken() async {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        let cookies = await store.allCookies()
        if let token = cookies.first(where: { $0.name == "oauth_token" })?.value {
            finish(.success(Result(oauthToken: token, email: email)))
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let value = message.body as? String { email = value }
    }

    func windowWillClose(_ notification: Notification) {
        finish(.failure(KeepError.cancelled))
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        pollTask?.cancel()
        // The content controller retains its message handler (self); break the cycle.
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageName, contentWorld: .defaultClient)
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil
        continuation.resume(with: result)
    }
}
