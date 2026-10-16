import Foundation

public struct PreferenceKey: Codable, Hashable, Sendable {
    public let domain: String; public let name: String
    public init(_ domain: String, _ name: String) { self.domain = domain; self.name = name }
}
public struct PreferenceChange: Codable, Equatable, Sendable {
    public let key: PreferenceKey; public let original: Data?; public let applied: Data
}
public protocol PreferenceBackend {
    func read(_ key: PreferenceKey) throws -> Data?
    func write(_ key: PreferenceKey, value: Data?) throws
    func refresh(_ keys: [PreferenceKey]) throws
}
// The journal is durable before a single OS preference is changed. Tests inject a
// memory backend; production uses CFPreferences. Missing keys remain missing on restore.
public final class ActivationOverrides {
    private let backend: PreferenceBackend
    private let journal: URL
    public init(backend: PreferenceBackend, journal: URL) { self.backend = backend; self.journal = journal }
    public func activate(_ desired: [PreferenceKey: Data]) throws {
        if FileManager.default.fileExists(atPath: journal.path) { try restore() }
        let changes = try desired.sorted { ($0.key.domain + $0.key.name) < ($1.key.domain + $1.key.name) }.compactMap { key, value -> PreferenceChange? in
            let original = try backend.read(key)
            return original == value ? nil : PreferenceChange(key: key, original: original, applied: value)
        }
        guard !changes.isEmpty else { return }
        try persist(changes)
        do {
            for entry in changes {
                try backend.write(entry.key, value: entry.applied)
                guard try backend.read(entry.key) == entry.applied else { throw LayoutError.invalidInput }
            }
            try backend.refresh(changes.map(\.key))
        } catch { try? restore(); throw error }
    }
    public func restore() throws {
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        let changes = try JSONDecoder().decode([PreferenceChange].self, from: Data(contentsOf: journal))
        var remaining: [PreferenceChange] = []
        for entry in changes {
            do {
                // A manual change made while Bento is active takes precedence.
                if try backend.read(entry.key) == entry.applied {
                    try backend.write(entry.key, value: entry.original)
                    guard try backend.read(entry.key) == entry.original else { throw LayoutError.invalidInput }
                }
            } catch { remaining.append(entry) }
        }
        do { try backend.refresh(changes.map(\.key)) } catch { try persist(changes); throw error }
        if remaining.isEmpty { try FileManager.default.removeItem(at: journal) }
        else { try persist(remaining); throw NSError(domain: "Bento", code: 2, userInfo: [NSLocalizedDescriptionKey: "Some desktop preferences could not be restored. Bento will retry on its next launch."]) }
    }
    private func persist(_ changes: [PreferenceChange]) throws {
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(changes).write(to: journal, options: .atomic)
    }
    public static func boolean(_ value: Bool) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }
}
