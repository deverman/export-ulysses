import Foundation

@MainActor
final class SecurityScopedAccess {
    let url: URL
    private let didStartAccessing: Bool

    init(url: URL) {
        self.url = url
        didStartAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

enum BookmarkKey: String {
    case backup
    case destinationParent
}

enum SecurityScopedBookmarkStore {
    static func save(_ url: URL, key: BookmarkKey, readOnly: Bool) throws {
        var options: URL.BookmarkCreationOptions = [.withSecurityScope]
        if readOnly { options.insert(.securityScopeAllowOnlyReadAccess) }
        let data = try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: storageKey(key))
    }

    static func restore(_ key: BookmarkKey) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(key)) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale {
            try? save(url, key: key, readOnly: key == .backup)
        }
        return url
    }

    private static func storageKey(_ key: BookmarkKey) -> String {
        "securityScopedBookmark.\(key.rawValue)"
    }
}
