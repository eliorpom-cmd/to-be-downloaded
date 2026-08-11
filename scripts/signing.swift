#!/usr/bin/env swift
// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
//
//  Release signing — Ed25519 (CryptoKit).
//
//  This is the ROOT OF TRUST for automatic updates: the app only replaces its
//  own bundle if the downloaded archive carries a valid signature for the public
//  key compiled in the binary. Since the app is not Apple-notarized, this
//  signature is the ONLY authenticity guarantee — it plays the exact role of
//  Developer ID in Sparkle.
//
//  Private keys never leave this machine:
//      ~/.config/tbd-release/ed25519.key          (0600)  — current signature
//      ~/.config/tbd-release/ed25519-backup.key   (0600)  — backup
//
//  TWO keys, and both public keys are accepted by the app. This avoids lockout:
//  if the current key is lost, sign the next version with the backup key and
//  updates keep working. Store the backup key ELSEWHERE than on this Mac (password
//  manager).
//
//  → NEVER commit. They live outside the repo on purpose.
//
//  Usage:
//      ./scripts/signing.swift keygen [backup]           # once per key
//      ./scripts/signing.swift pubkey [backup]
//      ./scripts/signing.swift sign <file> [backup]      # writes <file>.sig
//      ./scripts/signing.swift verify <file> <file.sig> <pubkey-base64>
//
import Foundation
import CryptoKit

/// `backup` as last argument selects the backup key.
let useBackupKey = CommandLine.arguments.dropFirst().contains("backup")

let keyPath: URL = {
    if let override = ProcessInfo.processInfo.environment["TBD_RELEASE_KEY"] {
        return URL(fileURLWithPath: override)
    }
    let name = useBackupKey ? "ed25519-backup.key" : "ed25519.key"
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/tbd-release/\(name)")
}()

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
    exit(1)
}

func loadPrivateKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOf: keyPath, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else {
        fail("Private key not found or unreadable: \(keyPath.path)\n   First run: ./scripts/signing.swift keygen")
    }
    return key
}

/// Memory-mapped reading: a release archive weighs ~100 MB, no point loading
/// it entirely into memory to sign it.
func mappedContents(of path: String) -> Data {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
        fail("Fichier illisible : \(path)")
    }
    return data
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fail("Missing command (keygen | pubkey | sign | verify)")
}

switch command {
case "keygen":
    if FileManager.default.fileExists(atPath: keyPath.path) {
        let key = loadPrivateKey()
        print("ℹ️  Key already present: \(keyPath.path)")
        print(key.publicKey.rawRepresentation.base64EncodedString())
        exit(0)
    }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(
        at: keyPath.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: 0o700)])
    // Direct write with restrictive permissions: never a window where the
    // key is readable by everyone.
    guard FileManager.default.createFile(
        atPath: keyPath.path,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: NSNumber(value: 0o600)])
    else { fail("Cannot write: \(keyPath.path)") }

    print("✅ Private key created: \(keyPath.path) (0600)")
    print(useBackupKey
        ? "   Store it ELSEWHERE than this Mac: it will save you if the other is lost."
        : "   BACK IT UP (and keep the backup key elsewhere too).")
    print("")
    print("Public key to add to AppConfig.updatePublicKeys:")
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "pubkey":
    print(loadPrivateKey().publicKey.rawRepresentation.base64EncodedString())

case "sign":
    guard args.count >= 2 else { fail("Usage: sign <file>") }
    let target = args[1]
    let signature = try loadPrivateKey().signature(for: mappedContents(of: target))
    let encoded = signature.base64EncodedString()
    try Data(encoded.utf8).write(to: URL(fileURLWithPath: target + ".sig"))
    print(encoded)

case "verify":
    guard args.count >= 4 else { fail("Usage: verify <file> <file.sig> <pubkey-base64>") }
    guard let rawKey = Data(base64Encoded: args[3]),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    else { fail("Invalid public key") }
    guard let sigText = try? String(contentsOf: URL(fileURLWithPath: args[2]), encoding: .utf8),
          let signature = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines))
    else { fail("Unreadable signature: \(args[2])") }

    if publicKey.isValidSignature(signature, for: mappedContents(of: args[1])) {
        print("✅ Signature valid")
    } else {
        fail("Signature INVALID")
    }

default:
    fail("Unknown command: \(command)")
}
