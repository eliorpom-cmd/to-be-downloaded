import Foundation

/// Construit un bundle de certificats de confiance combinant :
///  - le bundle Mozilla embarqué (`cacert.pem`, racines publiques),
///  - les racines du trousseau macOS, qui incluent les CA installées
///    localement : contrôle parental, antivirus, VPN, proxy d'entreprise…
///    (ex. « Qustodio Protection CA » qui intercepte le TLS).
///
/// Indispensable : yt-dlp (via curl_cffi + `CURL_CA_BUNDLE`) doit faire
/// confiance à un éventuel intercepteur TLS présent sur la machine, sinon
/// toutes les connexions HTTPS échouent (« unable to get local issuer certificate »).
enum TrustStore {

    /// Génère le bundle combiné dans Application Support et renvoie son URL.
    /// En cas d'échec, retombe sur le bundle Mozilla embarqué.
    static func prepareBundle(shippedCACert: URL?) -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil,
                                           create: true) else {
            return shippedCACert
        }

        let dir = appSupport.appendingPathComponent(AppConfig.displayName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("trust.pem")

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
            "/System/Library/Keychains/SystemRootCertificates.keychain", // racines Apple
            "/Library/Keychains/System.keychain",                        // racines admin (Qustodio…)
            login,                                                       // racines utilisateur
        ]

        var results: [Data] = []
        for keychain in keychains where FileManager.default.fileExists(atPath: keychain) {
            if let out = runSecurityExport(keychain: keychain), !out.isEmpty {
                results.append(out)
            }
        }
        return results
    }

    /// `security find-certificate -a -p <keychain>` → certificats au format PEM.
    private static func runSecurityExport(keychain: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-certificate", "-a", "-p", keychain]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Lecture jusqu'à EOF AVANT waitUntilExit : évite le deadlock si la
            // sortie dépasse la taille du buffer du pipe.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        } catch {
            return nil
        }
    }
}
