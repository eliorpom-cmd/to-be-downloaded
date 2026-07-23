import Foundation

/// Lance un binaire via `Process` SANS injection shell : les arguments sont
/// passés dans un tableau, jamais concaténés dans une ligne de commande.
enum ProcessRunner {

    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Exécute `executable` avec `arguments` et renvoie sa sortie une fois terminé.
    /// Usage simple (one-shot). Pour le streaming de progression, on utilisera
    /// une variante dédiée en M1.
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            // Lecture des pipes AVANT waitUntilExit pour éviter les deadlocks
            // si la sortie dépasse la taille du buffer du pipe.
            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Result(
                    exitCode: proc.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
