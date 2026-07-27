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
    ///
    /// Les deux tuyaux sont vidés EN CONTINU, pendant que le process tourne.
    /// Attendre sa fin pour les lire bloque dès que la sortie dépasse la taille
    /// du tampon du tuyau (64 Ko) : le process reste coincé sur son écriture,
    /// donc ne se termine jamais, donc on ne lit jamais. C'est exactement ce
    /// qui arrivait sur une playlist un peu fournie, dont le JSON pèse
    /// plusieurs centaines de kilo-octets.
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Result {
        let collector = OutputCollector()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            collector.onFinished = { out, err, code in
                continuation.resume(returning: Result(
                    exitCode: code,
                    stdout: String(decoding: out, as: UTF8.self),
                    stderr: String(decoding: err, as: UTF8.self)))
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    collector.closeStandardOutput()
                } else {
                    collector.append(data, toStandardOutput: true)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    collector.closeStandardError()
                } else {
                    collector.append(data, toStandardOutput: false)
                }
            }

            process.terminationHandler = { proc in
                collector.processExited(code: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                collector.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Assemble les deux sorties et ne rend la main qu'une fois le process terminé
/// ET les deux flux épuisés — dans n'importe quel ordre.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private var outOpen = true
    private var errOpen = true
    private var exitCode: Int32?
    private var finished = false

    /// Assignée avant le lancement, appelée une seule fois.
    var onFinished: ((Data, Data, Int32) -> Void)?

    func append(_ data: Data, toStandardOutput: Bool) {
        lock.lock(); defer { lock.unlock() }
        if toStandardOutput { out.append(data) } else { err.append(data) }
    }

    func closeStandardOutput() {
        lock.lock(); outOpen = false; lock.unlock()
        finishIfReady()
    }

    func closeStandardError() {
        lock.lock(); errOpen = false; lock.unlock()
        finishIfReady()
    }

    func processExited(code: Int32) {
        lock.lock(); exitCode = code; lock.unlock()
        finishIfReady()
    }

    /// Le lancement a échoué : plus personne ne rendra la main, on neutralise.
    func cancel() {
        lock.lock(); finished = true; lock.unlock()
    }

    private func finishIfReady() {
        lock.lock()
        guard !finished, !outOpen, !errOpen, let code = exitCode else {
            lock.unlock()
            return
        }
        finished = true
        let capturedOut = out
        let capturedErr = err
        let handler = onFinished
        lock.unlock()
        handler?(capturedOut, capturedErr, code)
    }
}
