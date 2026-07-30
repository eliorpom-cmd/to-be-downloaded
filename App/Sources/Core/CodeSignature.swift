import Foundation
import Security

/// Vérification de signature de code, sans passer par `codesign`.
///
/// On pourrait lancer `/usr/bin/codesign` et lire sa sortie ; l'API Security
/// fait la même chose sans sous-processus, sans parsing de texte, et rend une
/// erreur exploitable. Elle est aussi la seule à savoir dire « signé par CETTE
/// équipe » d'une façon qui ne se contrefait pas.
enum CodeSignature {

    enum SignatureError: LocalizedError {
        case unreadable
        case invalid(String)
        case wrongAuthority

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "The downloaded file could not be read for signature checking."
            case .invalid(let detail):
                return "The downloaded file is not properly signed: \(detail)"
            case .wrongAuthority:
                return "The downloaded file is signed by someone else than expected."
            }
        }
    }

    /// Exige une signature **Developer ID** délivrée par Apple à l'équipe
    /// donnée, chaîne de certification comprise.
    ///
    /// C'est la garantie forte de tout le chemin de téléchargement : le SHA-256
    /// vient du même hôte que le binaire, donc il ne protège que d'un transfert
    /// tronqué. Une signature Developer ID, elle, ne peut pas être fabriquée par
    /// quelqu'un qui prendrait le contrôle du serveur — il faudrait la clé
    /// privée de l'équipe ET l'autorité de certification d'Apple.
    ///
    /// - Parameters:
    ///   - url: le binaire à vérifier.
    ///   - teamIdentifier: l'identifiant d'équipe attendu (ex. `"KU3N25YGLU"`).
    static func verifyDeveloperID(at url: URL, teamIdentifier: String) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode
        else { throw SignatureError.unreadable }

        // Forme canonique d'Apple pour « Developer ID de telle équipe » :
        //   - ancre Apple,
        //   - le certificat intermédiaire porte le marqueur Developer ID CA,
        //   - la feuille porte le marqueur Developer ID Application,
        //   - et son unité organisationnelle est l'identifiant d'équipe.
        // Vérifier la seule OU sans les marqueurs laisserait passer un
        // certificat Apple d'un autre type portant le même champ.
        let requirementText = """
            anchor apple generic \
            and certificate 1[field.1.2.840.113635.100.6.2.6] \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] \
            and certificate leaf[subject.OU] = "\(teamIdentifier)"
            """

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { throw SignatureError.unreadable }

        var errorRef: Unmanaged<CFError>?
        // `.enforceRevocationChecks` n'est PAS demandé : il exige le réseau et
        // ferait échouer une vérification hors ligne. La chaîne Apple et le
        // marqueur d'équipe suffisent ici.
        let status = SecStaticCodeCheckValidityWithErrors(
            code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement, &errorRef)

        guard status == errSecSuccess else {
            let detail = errorRef?.takeRetainedValue().localizedDescription
                ?? "OSStatus \(status)"
            // `errSecCSReqFailed` = la signature est valide mais ne vient pas de
            // l'équipe attendue. À distinguer d'un binaire non signé ou abîmé :
            // c'est le seul cas qui ressemble à une substitution.
            throw status == errSecCSReqFailed
                ? SignatureError.wrongAuthority
                : SignatureError.invalid(detail)
        }
    }
}
