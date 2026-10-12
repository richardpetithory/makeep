import Foundation

/// Port of the two gpsoauth calls gkeepapi relies on:
/// - `exchangeToken`: one-time `oauth_token` cookie (from accounts.google.com/EmbeddedSetup) → long-lived master token
/// - `performOAuth`: master token → short-lived Keep access token
enum AndroidAuth {
    private static let url = URL(string: "https://android.clients.google.com/auth")!
    private static let clientSig = "38918a453d07199354f8b19af05ec6562ced5788"
    private static let keepScopes = "oauth2:https://www.googleapis.com/auth/memento https://www.googleapis.com/auth/reminders"

    static func exchangeToken(email: String, oauthToken: String, androidID: String) async throws -> String {
        let response = try await post([
            ("accountType", "HOSTED_OR_GOOGLE"),
            ("Email", email),
            ("has_permission", "1"),
            ("add_account", "1"),
            ("ACCESS_TOKEN", "1"),
            ("Token", oauthToken),
            ("service", "ac2dm"),
            ("source", "android"),
            ("androidId", androidID),
            ("device_country", "us"),
            ("operatorCountry", "us"),
            ("lang", "en"),
            ("sdk_version", "17"),
            ("google_play_services_version", "240913000"),
            ("client_sig", clientSig),
            ("callerSig", clientSig),
            ("droidguard_results", "dummy123"),
        ])
        guard let master = response["Token"] else {
            throw KeepError.auth(response["Error"] ?? "No master token in response.")
        }
        return master
    }

    static func performOAuth(email: String, masterToken: String, androidID: String) async throws -> (token: String, expiry: Date) {
        let response = try await post([
            ("accountType", "HOSTED_OR_GOOGLE"),
            ("Email", email),
            ("has_permission", "1"),
            ("EncryptedPasswd", masterToken),
            ("service", keepScopes),
            ("source", "android"),
            ("androidId", androidID),
            ("app", "com.google.android.keep"),
            ("client_sig", clientSig),
            ("device_country", "us"),
            ("operatorCountry", "us"),
            ("lang", "en"),
            ("sdk_version", "17"),
        ])
        guard let token = response["Auth"] else {
            throw KeepError.auth(response["Error"] ?? "No auth token in response.")
        }
        let expiry = response["Expiry"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
            ?? .now.addingTimeInterval(3000)
        return (token, expiry)
    }

    static func randomAndroidID() -> String {
        String(format: "%016llx", UInt64.random(in: 0...UInt64.max))
    }

    private static func post(_ fields: [(String, String)]) async throws -> [String: String] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("GoogleAuth/1.4", forHTTPHeaderField: "User-Agent")
        request.httpBody = HTTP.formBody(fields)

        let (data, _) = try await URLSession.shared.data(for: request)
        // Errors come back as "Error=..." in the body, so parse regardless of status.
        var result: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let separator = line.firstIndex(of: "=") else { continue }
            result[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        return result
    }
}
