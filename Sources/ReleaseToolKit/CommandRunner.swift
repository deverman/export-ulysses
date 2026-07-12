import Foundation

public struct CommandFailure: LocalizedError {
    public let command: [String]
    public let status: Int32
    public let output: String

    public var errorDescription: String? {
        var message = "Command failed with exit status \(status): \(command.joined(separator: " "))"
        if !output.isEmpty { message += "\n\(output)" }
        return message
    }
}

public struct CommandRunner {
    public init() {}

    @discardableResult
    public func run(_ command: [String], captureOutput: Bool = false) throws -> String {
        precondition(!command.isEmpty)
        print("$ \(command.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command

        let pipe = captureOutput ? Pipe() : nil
        if let pipe {
            process.standardOutput = pipe
            process.standardError = pipe
        }

        try process.run()
        process.waitUntilExit()
        let output = pipe.map { String(decoding: $0.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) } ?? ""
        guard process.terminationStatus == 0 else {
            throw CommandFailure(command: command, status: process.terminationStatus, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
