// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// Launch a binary via `Process` WITHOUT shell injection: arguments are passed
/// in an array, never concatenated into a command line.
enum ProcessRunner {

    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Run `executable` with `arguments` and return its output once finished.
    ///
    /// Both pipes are drained CONTINUOUSLY while the process runs. Waiting for
    /// it to finish before reading them deadlocks once output exceeds the pipe
    /// buffer (64 KB): the process gets stuck on its write, so never finishes,
    /// so we never read. This is exactly what happened with a well-populated
    /// playlist whose JSON weighs hundreds of kilobytes.
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

/// Assemble both outputs and return control only once the process exits AND
/// both streams are exhausted — in any order.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private var outOpen = true
    private var errOpen = true
    private var exitCode: Int32?
    private var finished = false

    /// Assigned before launch, called once only.
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

    /// Launch failed: no one will return control, neutralize it.
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
