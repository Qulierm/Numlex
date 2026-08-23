import Foundation

public struct Sheet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(id: UUID = UUID(), title: String, content: String, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public var lineCount: Int {
        if content.isEmpty { return 0 }
        // Count lines as split by \n, but empty content is 0
        let parts = content.components(separatedBy: "\n")
        if parts.count == 1 && parts[0].isEmpty { return 0 }
        return parts.count
    }

    public var createdLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        // If today, show HH:mm else MMM d at HH:mm
        if Calendar.current.isDateInToday(createdAt) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "MMM d 'at' HH:mm"
        }
        return f.string(from: createdAt)
    }
}

public struct SheetExport: Codable, Sendable {
    public var title: String
    public var content: String
    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}
