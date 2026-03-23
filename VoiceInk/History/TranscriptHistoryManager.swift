import Cocoa

struct TranscriptEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let engineType: String
    let timestamp: Date

    init(text: String, engineType: String) {
        self.id = UUID()
        self.text = text
        self.engineType = engineType
        self.timestamp = Date()
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    var preview: String {
        if text.count <= 40 { return text }
        return String(text.prefix(37)) + "..."
    }
}

@MainActor
final class TranscriptHistoryManager: ObservableObject {
    @Published private(set) var entries: [TranscriptEntry] = []

    private let maxEntries = 20
    private let expirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private let storageKey = "transcriptHistory"

    init() {
        load()
        purgeExpired()
    }

    func add(text: String, engineType: String) {
        let entry = TranscriptEntry(text: text, engineType: engineType)
        entries.insert(entry, at: 0)

        // Keep only maxEntries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        save()
    }

    func clear() {
        entries = []
        save()
    }

    func copyToClipboard(_ entry: TranscriptEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
    }

    // MARK: - Private

    private func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-expirationInterval)
        entries = entries.filter { $0.timestamp > cutoff }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else {
            return
        }
        entries = decoded
    }
}
