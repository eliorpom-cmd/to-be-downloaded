import Foundation

/// Build a trust certificate bundle combining:
///  - the shipped Mozilla bundle (`cacert.pem`, public roots),
///  - the macOS keychain roots, which include locally-installed CAs: parental
///    controls, antivirus, VPN, enterprise proxy, etc.
///    (e.g. "Qustodio Protection CA" which intercepts TLS).
///
/// Essential: yt-dlp (via curl_cffi + `CURL_CA_BUNDLE`) must trust any TLS
/// interceptor on the machine, otherwise all HTTPS connections fail
/// ("unable to get local issuer certificate").
enum TrustStore {

    /// Generate the combined bundle in Application Support and return its URL.
    /// On failure, fall back to the shipped Mozilla bundle.
    static func prepareBundle(shippedCACert: URL?) -> URL? {
        let dest = AppConfig.supportDirectory.appendingPathComponent("trust.pem")

        var pem = Data()
        if let shipped = shippedCACert, let data = try? Data(contentsOf: shipped) {
            pem.append(data)
            pem.append(0x0A)
        }
        for data in exportSystemRoots() {
            pem.append(data)
            pem.append(0x0A)
        }

        guard pem.count > 0 else { return shippedCACert }
        do {
            try pem.write(to: dest)
            return dest
        } catch {
            return shippedCACert
        }
    }

    private static func exportSystemRoots() -> [Data] {
        let login = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Keychains/login.keychain-db")
        let keychains = [
            "/System/Library/Keychains/SystemRootCertificates.keychain", // Apple roots
            "/Library/Keychains/System.keychain",                        // admin roots (Qustodio…)
            login,                                                       // user roots
        ]

        var results: [Data] = []
        for keychain in keychains where FileManager.default.fileExists(atPath: keychain) {
            if let out = runSecurityExport(keychain: keychain), !out.isEmpty {
                results.append(out)
            }
        }
        return results
    }

    /// `security find-certificate -a -p <keychain>` → certificates in PEM format.
    private static func runSecurityExport(keychain: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-certificate", "-a", "-p", keychain]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Read to EOF BEFORE waitUntilExit: avoids deadlock if output
            // exceeds the pipe buffer size.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        } catch {
            return nil
        }
    }
}
