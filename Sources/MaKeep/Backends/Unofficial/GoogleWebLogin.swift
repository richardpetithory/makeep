import AppKit
import WebKit

/// Shows Google's EmbeddedSetup sign-in page and returns the `oauth_token` cookie it sets,
/// which `AndroidAuth.exchangeToken` turns into a master token.
final class GoogleWebLogin: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var pollTask: Task<Void, Never>?

    func run() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: configuration)
            // Google refuses sign-in from user agents it doesn't recognize as a browser.
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
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

            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            webView.load(URLRequest(url: URL(string: "https://accounts.google.com/EmbeddedSetup")!))

            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(750))
                    await self?.checkForToken()
                }
            }
        }
    }

    private func checkForToken() async {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        let cookies = await store.allCookies()
        if let token = cookies.first(where: { $0.name == "oauth_token" })?.value {
            finish(.success(token))
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(.failure(KeepError.cancelled))
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        pollTask?.cancel()
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil
        continuation.resume(with: result)
    }
}
