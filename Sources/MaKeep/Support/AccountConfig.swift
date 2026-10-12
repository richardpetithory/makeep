import Foundation

nonisolated enum BackendKind: String, Codable, CaseIterable, Identifiable {
    case unofficial
    case official

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unofficial: "Personal Google account"
        case .official: "Google Workspace"
        }
    }
}

/// Non-secret account settings. Tokens live in the Keychain.
nonisolated struct AccountConfig: Codable, Equatable {
    var kind: BackendKind
    var email: String?
    var clientID: String?

    private static let defaultsKey = "account"

    static func load() -> AccountConfig? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(AccountConfig.self, from: data)
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
