import AppKit
import CryptoKit
import Foundation

/// Installed-app OAuth (loopback redirect + PKCE) for the official Keep API.
/// Requires a "Desktop app" OAuth client in a Workspace org's Google Cloud project.
final class GoogleOAuth {
    static let scope = "https://www.googleapis.com/auth/keep"

    let clientID: String
    let clientSecret: String
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var activeReceiver: LoopbackReceiver?

    init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    var hasRefreshToken: Bool { Keychain.get(SecretKey.oauthRefreshToken) != nil }

    func signIn() async throws {
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomURLSafeString(byteCount: 16)

        let receiver = try LoopbackReceiver()
        activeReceiver = receiver
        defer { activeReceiver = nil }
        let port = try await receiver.start()
        let redirectURI = "http://127.0.0.1:\(port)"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]
        NSWorkspace.shared.open(components.url!)

        let params = try await receiver.waitForCallback()
        if let error = params["error"] { throw KeepError.auth(error) }
        guard params["state"] == state, let code = params["code"] else {
            throw KeepError.auth("Invalid OAuth callback.")
        }

        let token = try await tokenRequest([
            ("code", code),
            ("client_id", clientID),
            ("client_secret", clientSecret),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", verifier),
        ])
        guard let refresh = token.refresh_token else {
            throw KeepError.auth("Google did not return a refresh token.")
        }
        Keychain.set(refresh, for: SecretKey.oauthRefreshToken)
        store(token)
    }

    func cancelSignIn() {
        activeReceiver?.cancel()
    }

    func validAccessToken() async throws -> String {
        if let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.get(SecretKey.oauthRefreshToken) else { throw KeepError.notSignedIn }
        let token = try await tokenRequest([
            ("refresh_token", refresh),
            ("client_id", clientID),
            ("client_secret", clientSecret),
            ("grant_type", "refresh_token"),
        ])
        store(token)
        return token.access_token
    }

    func invalidateAccessToken() {
        accessToken = nil
    }

    private nonisolated struct TokenResponse: Decodable {
        var access_token: String
        var expires_in: Double
        var refresh_token: String?
    }

    private func store(_ token: TokenResponse) {
        accessToken = token.access_token
        expiry = .now.addingTimeInterval(token.expires_in)
    }

    private func tokenRequest(_ fields: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.formBody(fields)
        return try JSONDecoder().decode(TokenResponse.self, from: try await HTTP.data(for: request))
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        Data((0..<byteCount).map { _ in UInt8.random(in: 0...255) }).base64URLEncoded
    }
}

extension Data {
    nonisolated var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
