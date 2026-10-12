import Foundation

/// Google Keep API v1 (https://developers.google.com/workspace/keep/api).
/// Workspace-only. The API has no update or pin operations, so edits are emulated as
/// create-then-delete.
final class OfficialKeepBackend: KeepBackend {
    let capabilities = BackendCapabilities(editsInPlace: false, supportsPinning: false)
    private let auth: GoogleOAuth
    private let baseURL = URL(string: "https://keep.googleapis.com/v1/")!

    init(auth: GoogleOAuth) {
        self.auth = auth
    }

    func fetchNotes() async throws -> [Note] {
        var notes: [Note] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(url: baseURL.appending(path: "notes"), resolvingAgainstBaseURL: false)!
            components.queryItems = [.init(name: "pageSize", value: "100")]
            if let pageToken { components.queryItems?.append(.init(name: "pageToken", value: pageToken)) }
            let data = try await send("GET", components.url!)
            let page = try JSONDecoder().decode(APIListResponse.self, from: data)
            notes += (page.notes ?? []).filter { $0.trashed != true }.map(\.note)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return notes.sorted(by: Note.displayOrder)
    }

    func create(_ draft: Note) async throws -> Note {
        let body = try JSONEncoder().encode(APINote(draft))
        let data = try await send("POST", baseURL.appending(path: "notes"), body: body)
        return try JSONDecoder().decode(APINote.self, from: data).note
    }

    func update(_ note: Note) async throws -> Note {
        // Create first so a failure never loses content.
        let created = try await create(note)
        try await delete(note)
        return created
    }

    func delete(_ note: Note) async throws {
        _ = try await send("DELETE", baseURL.appending(path: note.id))
    }

    private func send(_ method: String, _ url: URL, body: Data? = nil, retry: Bool = true) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            return try await HTTP.data(for: request)
        } catch KeepError.http(401, _) where retry {
            auth.invalidateAccessToken()
            return try await send(method, url, body: body, retry: false)
        }
    }
}

// MARK: - Wire format

nonisolated private struct APIListResponse: Decodable {
    var notes: [APINote]?
    var nextPageToken: String?
}

nonisolated private struct APINote: Codable {
    var name: String?
    var title: String?
    var body: Section?
    var trashed: Bool?
    var updateTime: String?

    struct Section: Codable {
        var text: TextContent?
        var list: ListContent?
    }

    struct TextContent: Codable {
        var text: String?
    }

    struct ListContent: Codable {
        var listItems: [Item]?
    }

    struct Item: Codable {
        var text: TextContent?
        var checked: Bool?
        var childListItems: [Item]?
    }

    init(_ note: Note) {
        title = note.title
        switch note.content {
        case .text(let text):
            body = Section(text: TextContent(text: text))
        case .list(let items):
            body = Section(list: ListContent(listItems: items.map {
                Item(text: TextContent(text: $0.text), checked: $0.checked)
            }))
        }
    }

    var note: Note {
        let id = name ?? ""
        let content: Note.Content
        if let list = body?.list {
            // The API supports one level of nesting; MaKeep shows it flattened.
            let flat = (list.listItems ?? []).flatMap { [$0] + ($0.childListItems ?? []) }
            content = .list(flat.enumerated().map { index, item in
                ListItem(id: "\(id)#\(index)", text: item.text?.text ?? "", checked: item.checked ?? false)
            })
        } else {
            content = .text(body?.text?.text ?? "")
        }
        return Note(id: id, title: title ?? "", content: content,
                    updated: updateTime.flatMap(KeepDate.parse) ?? .distantPast)
    }
}
