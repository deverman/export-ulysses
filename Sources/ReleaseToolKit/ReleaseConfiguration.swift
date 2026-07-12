import Foundation

public enum ReleaseConfigurationError: LocalizedError, Equatable {
    case invalidArchitecture(String)
    case missingEnvironment(String)
    case partialNotarizationEnvironment([String])
    case notRepositoryRoot(String)
    case versionMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchitecture(let architecture):
            "Unsupported architecture '\(architecture)'. Use arm64 or x86_64."
        case .missingEnvironment(let name):
            "Required environment variable \(name) is not set."
        case .partialNotarizationEnvironment(let names):
            "Notarization configuration is incomplete. Set \(names.joined(separator: ", ")) or unset all notarization variables."
        case .notRepositoryRoot(let path):
            "Release commands must run from the repository root. Package.swift was not found at \(path)."
        case .versionMismatch(let expected, let actual):
            "Built CLI reports version '\(actual)', but release version '\(expected)' was requested."
        }
    }
}

public struct DirectReleaseConfiguration: Equatable {
    public let version: String
    public let architecture: String
    public let artifactName: String

    public init(version: String, architecture: String) throws {
        guard ["arm64", "x86_64"].contains(architecture) else {
            throw ReleaseConfigurationError.invalidArchitecture(architecture)
        }
        self.version = version
        self.architecture = architecture
        artifactName = "export-ulysses-\(version)-macos26-\(architecture)"
    }
}

public struct NotarizationCredentials: Equatable {
    public let appleID: String
    public let teamID: String
    public let appPassword: String

    public static func resolve(environment: [String: String]) throws -> Self? {
        let keys = ["APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_PASSWORD"]
        let values = keys.map { environment[$0].flatMap { $0.isEmpty ? nil : $0 } }
        if values.allSatisfy({ $0 == nil }) { return nil }
        let missing = zip(keys, values).compactMap { key, value in value == nil ? key : nil }
        guard missing.isEmpty else {
            throw ReleaseConfigurationError.partialNotarizationEnvironment(missing)
        }
        return Self(appleID: values[0]!, teamID: values[1]!, appPassword: values[2]!)
    }
}

public enum RepositoryRoot {
    public static func validate(_ url: URL, fileManager: FileManager = .default) throws {
        let manifest = url.appendingPathComponent("Package.swift").path
        guard fileManager.fileExists(atPath: manifest) else {
            throw ReleaseConfigurationError.notRepositoryRoot(manifest)
        }
    }
}
