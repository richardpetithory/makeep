import Foundation

nonisolated enum KeepDate {
    static let zero = "1970-01-01T00:00:00.000Z"

    static func format(_ date: Date) -> String {
        date.formatted(.iso8601
            .year().month().day()
            .timeZone(separator: .omitted).time(includingFractionalSeconds: true)
            .dateTimeSeparator(.standard))
    }

    static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601.year().month().day()
            .time(includingFractionalSeconds: true).dateTimeSeparator(.standard).timeZone(separator: .omitted)) {
            return date
        }
        return try? Date(string, strategy: .iso8601)
    }

    /// Keep uses the epoch as "unset" for trashed/deleted.
    static func isSet(_ value: JSONValue?) -> Bool {
        guard let string = value?.stringValue, let date = parse(string) else { return false }
        return date.timeIntervalSince1970 > 1
    }
}
