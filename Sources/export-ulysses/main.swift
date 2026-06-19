import Foundation
import ArgumentParser

//: - Private Interface

private let keysToFetch: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]

private enum ExportJob: Sendable {
    case copyItem(source: URL, destination: URL, createdDate: Date, modifiedDate: Date)
}

final class Exporter {
    private let fileManager = FileManager.default
    private let verbose: Bool
    private let includeHiddenUlyssesMetadata: Bool
    private let maxConcurrentExports: Int

    init(verbose: Bool, includeHiddenUlyssesMetadata: Bool = false, maxConcurrentExports: Int = 2) {
        self.verbose = verbose
        self.includeHiddenUlyssesMetadata = includeHiddenUlyssesMetadata
        self.maxConcurrentExports = max(1, maxConcurrentExports)
    }

    func run(_ input: String, _ output: String, keepGroups: Bool, ignoring: [String]) async throws {
        print("Starting export...")

        let inputURL = URL(fileURLWithPath: input)
        let outputURL = URL(fileURLWithPath: output)
        try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)

        var directoryYAML: OutputStream?
        if keepGroups {
            directoryYAML = OutputStream(toFileAtPath: outputURL.appendingPathComponent("directories.yml").path, append: false)
            directoryYAML?.open()
            write("""
            ---
            note_directories:

            """, to: directoryYAML)
        }

        let jobs = try crawl(
            inputURL,
            output: outputURL.path,
            preservingFolders: keepGroups,
            ignoringFolders: ignoring,
            onFoundDirectory: { path in
                if keepGroups {
                    self.write("- \"\(path)\"\n", to: directoryYAML)
                }
            }
        )

        directoryYAML?.close()

        let exportedTotal = try await export(jobs)
        print("Exported \(exportedTotal) items.")
    }

    private func crawl(_ url: URL, output: String, preservingFolders: Bool = false, ignoringFolders: [String], onFoundDirectory: ((String) -> Void)? = nil) throws -> [ExportJob] {
        vprint("Scanning \(url)...")
        let outputURL = URL(fileURLWithPath: output)
        let resourceValues = try url.resourceValues(forKeys: Set(keysToFetch))
        let isDirectory = resourceValues.isDirectory ?? false
        guard isDirectory else {
            guard !url.lastPathComponent.hasPrefix(".Ulysses-") else { return [] }

            return [.copyItem(
                source: url,
                destination: outputURL.appendingPathComponent(url.lastPathComponent),
                createdDate: resourceValues.creationDate ?? Date(),
                modifiedDate: resourceValues.contentModificationDate ?? Date()
            )]
        }

        let results = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keysToFetch)

        if url.pathExtension == "textbundle" {
            return [.copyItem(
                source: url,
                destination: outputURL.appendingPathComponent(url.lastPathComponent),
                createdDate: resourceValues.creationDate ?? Date(),
                modifiedDate: resourceValues.contentModificationDate ?? Date()
            )]
        }
        else if results.count == 1 && results[0].lastPathComponent == "Info.ulfilter" {
            // TODO: Handle filters?
            return []
        }
        else {
            var name = url.lastPathComponent
            if let plist = NSDictionary(contentsOfFile: url.appendingPathComponent("Info.ulgroup").path) {
                if let displayName = plist["DisplayName"] as? String {
                    name = displayName
                }
                else if let displayName = plist["displayName"] as? String {
                    name = displayName
                }
                else {
                    name = "Inbox" // Plist without displayName maps to Inbox
                }
            }

            // Ignore matching groups
            guard !ignoringFolders.contains(name), shouldExportDirectory(url) else {
                return []
            }

            // Process and crawl group
            let newOutput = preservingFolders ? outputURL.appendingPathComponent(name) : outputURL
            try fileManager.createDirectory(at: newOutput, withIntermediateDirectories: true, attributes: nil)
            let newOutputPath = newOutput.path

            onFoundDirectory?(newOutputPath)

            var jobs: [ExportJob] = []
            for item in results {
                jobs.append(contentsOf: try crawl(item, output: newOutputPath, preservingFolders: preservingFolders, ignoringFolders: ignoringFolders, onFoundDirectory: onFoundDirectory))
            }
            return jobs
        }
    }

    private func export(_ jobs: [ExportJob]) async throws -> Int {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var nextJobIndex = 0

            func enqueueNextJob() {
                guard nextJobIndex < jobs.count else { return }
                let job = jobs[nextJobIndex]
                nextJobIndex += 1
                group.addTask {
                    try exportJob(job)
                }
            }

            for _ in 0..<min(maxConcurrentExports, jobs.count) {
                enqueueNextJob()
            }

            var exported = 0
            for try await _ in group {
                exported += 1
                enqueueNextJob()
                if exported % 500 == 0 {
                    print("Exported \(exported) items.")
                }
            }
            return exported
        }
    }

    private func shouldExportDirectory(_ url: URL) -> Bool {
        includeHiddenUlyssesMetadata || !url.lastPathComponent.hasPrefix(".Ulysses-")
    }

    private func vprint(_ thing: Any) {
        if verbose {
            print(thing)
        }
    }

    private func write(_ string: String, to stream: OutputStream?) {
        let data = [UInt8](string.utf8)
        stream?.write(data, maxLength: data.count)
    }
}

private func exportJob(_ job: ExportJob) throws {
    switch job {
    case let .copyItem(source, destination, createdDate, modifiedDate):
        try copyItem(from: source, to: destination, createdDate: createdDate, modifiedDate: modifiedDate)
    }
}

private func copyItem(from source: URL, to destination: URL, createdDate: Date, modifiedDate: Date) throws {
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
    let availableDestination = availableDestination(for: destination)
    if FileManager.default.fileExists(atPath: availableDestination.path) {
        try FileManager.default.removeItem(at: availableDestination)
    }
    try FileManager.default.copyItem(at: source, to: availableDestination)
    try FileManager.default.setAttributes([
        .creationDate: createdDate,
        .modificationDate: modifiedDate
    ], ofItemAtPath: availableDestination.path)
    try FileManager.default.setAttributes([
        .creationDate: createdDate,
        .modificationDate: modifiedDate
    ], ofItemAtPath: availableDestination.path)
}

private func availableDestination(for destination: URL) -> URL {
    var availableDestination = destination
    let baseName = destination.deletingPathExtension().lastPathComponent
    let pathExtension = destination.pathExtension
    var version = 0
    while FileManager.default.fileExists(atPath: availableDestination.path) {
        version += 1
        var nextDestination = destination
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName) (\(version))")
        if !pathExtension.isEmpty {
            nextDestination.appendPathExtension(pathExtension)
        }
        availableDestination = nextDestination
    }
    return availableDestination
}

//: - Public Interface

@main
struct ExportUlysses: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-ulysses",
        abstract: "Export a Ulysses library to an FSNotes-friendly folder."
    )

    @Argument(help: "The path to your Ulysses notes.")
    var input: String

    @Argument(help: "The path you want to export notes to.")
    var output: String

    @Flag(help: "Create directories for each Ulysses Group, and export notes into them.")
    var keepGroups = false

    @Flag(name: .shortAndLong, help: "Log export activity and debugging statements.")
    var verbose = false

    @Option(name: .long, parsing: .upToNextOption, help: "Groups to ignore on export.")
    var ignore: [String] = []

    @Option(help: "Maximum number of items to export concurrently.")
    var jobs = 2

    func run() async throws {
        try await Exporter(verbose: verbose, maxConcurrentExports: jobs).run(input, output, keepGroups: keepGroups, ignoring: ignore)
    }
}
