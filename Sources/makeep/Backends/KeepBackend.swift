import Foundation

struct BackendCapabilities {
    /// False when an edit has to be emulated by creating a new note and deleting the old one.
    var editsInPlace: Bool
    var supportsPinning: Bool
}

protocol KeepBackend: AnyObject {
    var capabilities: BackendCapabilities { get }
    func fetchNotes() async throws -> [Note]
    func create(_ draft: Note) async throws -> Note
    func update(_ note: Note) async throws -> Note
    func delete(_ note: Note) async throws
}

nonisolated enum KeepError: LocalizedError {
    case notSignedIn
    case notFound
    case cancelled
    case auth(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in."
        case .notFound: "That note no longer exists."
        case .cancelled: "Sign-in was cancelled."
        case .auth(let message): "Authentication failed: \(message)"
        case .http(let status, let body): "Google returned HTTP \(status). \(body)"
        }
    }
}
