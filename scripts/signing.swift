#!/usr/bin/env swift
//
//  Signature des releases — Ed25519 (CryptoKit).
//
//  C'est la RACINE DE CONFIANCE des mises à jour automatiques : l'app ne
//  remplace son propre bundle que si l'archive téléchargée porte une signature
//  valide pour la clé publique compilée dans le binaire. Comme l'app n'est pas
//  notarisée par Apple, cette signature est la SEULE garantie d'authenticité —
//  elle joue exactement le rôle que joue le Developer ID chez Sparkle.
//
//  Les clés privées ne quittent jamais cette machine :
//      ~/.config/downloader-release/ed25519.key          (0600)  — signature courante
//      ~/.config/downloader-release/ed25519-backup.key   (0600)  — secours
//
//  DEUX clés, et les deux clés publiques sont acceptées par l'app. C'est ce qui
//  évite l'impasse : si la clé courante est perdue, on signe la version suivante
//  avec la clé de secours et les mises à jour continuent de fonctionner. Range
//  la clé de secours AILLEURS que sur ce Mac (gestionnaire de mots de passe).
//
//  → À NE JAMAIS committer. Elles vivent hors du repo exprès.
//
//  Usage :
//      ./scripts/signing.swift keygen [backup]           # une fois par clé
//      ./scripts/signing.swift pubkey [backup]
//      ./scripts/signing.swift sign <fichier> [backup]   # écrit <fichier>.sig
//      ./scripts/signing.swift verify <fichier> <fichier.sig> <pubkey-base64>
//
import Foundation
import CryptoKit

/// `backup` en dernier argument sélectionne la clé de secours.
let useBackupKey = CommandLine.arguments.dropFirst().contains("backup")

let keyPath: URL = {
    if let override = ProcessInfo.processInfo.environment["DOWNLOADER_RELEASE_KEY"] {
        return URL(fileURLWithPath: override)
    }
    let name = useBackupKey ? "ed25519-backup.key" : "ed25519.key"
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/downloader-release/\(name)")
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
        fail("Clé privée introuvable ou illisible : \(keyPath.path)\n   Lance d'abord : ./scripts/signing.swift keygen")
    }
    return key
}

/// Lecture mappée : une archive de release pèse ~100 Mo, inutile de la charger
/// entièrement en mémoire pour la signer.
func mappedContents(of path: String) -> Data {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
        fail("Fichier illisible : \(path)")
    }
    return data
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fail("Commande manquante (keygen | pubkey | sign | verify)")
}

switch command {
case "keygen":
    if FileManager.default.fileExists(atPath: keyPath.path) {
        let key = loadPrivateKey()
        print("ℹ️  Clé déjà présente : \(keyPath.path)")
        print(key.publicKey.rawRepresentation.base64EncodedString())
        exit(0)
    }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(
        at: keyPath.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: 0o700)])
    // Écriture directe avec des permissions restrictives : jamais de fenêtre
    // pendant laquelle la clé serait lisible par tous.
    guard FileManager.default.createFile(
        atPath: keyPath.path,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: NSNumber(value: 0o600)])
    else { fail("Écriture impossible : \(keyPath.path)") }

    print("✅ Clé privée créée : \(keyPath.path) (0600)")
    print(useBackupKey
        ? "   Range-la HORS de ce Mac : c'est elle qui te sauvera si l'autre est perdue."
        : "   SAUVEGARDE-LA (et garde aussi la clé de secours ailleurs).")
    print("")
    print("Clé publique à ajouter dans AppConfig.updatePublicKeys :")
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "pubkey":
    print(loadPrivateKey().publicKey.rawRepresentation.base64EncodedString())

case "sign":
    guard args.count >= 2 else { fail("Usage : sign <fichier>") }
    let target = args[1]
    let signature = try loadPrivateKey().signature(for: mappedContents(of: target))
    let encoded = signature.base64EncodedString()
    try Data(encoded.utf8).write(to: URL(fileURLWithPath: target + ".sig"))
    print(encoded)

case "verify":
    guard args.count >= 4 else { fail("Usage : verify <fichier> <fichier.sig> <pubkey-base64>") }
    guard let rawKey = Data(base64Encoded: args[3]),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    else { fail("Clé publique invalide") }
    guard let sigText = try? String(contentsOf: URL(fileURLWithPath: args[2]), encoding: .utf8),
          let signature = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines))
    else { fail("Signature illisible : \(args[2])") }

    if publicKey.isValidSignature(signature, for: mappedContents(of: args[1])) {
        print("✅ Signature valide")
    } else {
        fail("Signature INVALIDE")
    }

default:
    fail("Commande inconnue : \(command)")
}
