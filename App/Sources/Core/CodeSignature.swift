import Foundation
import Security

/// Code signature verification without calling `codesign`.
///
/// We could run `/usr/bin/codesign` and parse its output; the Security API
/// does the same thing without a subprocess, without text parsing, and returns
/// an actionable error. It's also the only way to say "signed by THIS
/// team" in a way that can't be forged.
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

    /// Requires a **Developer ID** signature issued by Apple to the given
    /// team, including the certificate chain.
    ///
    /// This is the strong guarantee of the entire download path: the SHA-256
    /// comes from the same host as the binary, so it only protects against
    /// truncated transfers. A Developer ID signature, on the other hand,
    /// cannot be forged by someone who took control of the server — you'd need
    /// the team's private key AND Apple's certificate authority.
    ///
    /// - Parameters:
    ///   - url: the binary to verify.
    ///   - teamIdentifier: the expected team identifier (e.g., `"KU3N25YGLU"`).
    static func verifyDeveloperID(at url: URL, teamIdentifier: String) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode
        else { throw SignatureError.unreadable }

        // Apple's canonical form for "Developer ID of such-and-such team":
        //   - Apple anchor,
        //   - the intermediate cert carries the Developer ID CA marker,
        //   - the leaf carries the Developer ID Application marker,
        //   - and its organizational unit is the team identifier.
        // Checking only OU without the markers would pass an Apple cert of
        // another type carrying the same field.
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
        // `.enforceRevocationChecks` is NOT requested: it requires the network
        // and would fail offline verification. The Apple chain and team marker
        // are enough here.
        let status = SecStaticCodeCheckValidityWithErrors(
            code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement, &errorRef)

        guard status == errSecSuccess else {
            let detail = errorRef?.takeRetainedValue().localizedDescription
                ?? "OSStatus \(status)"
            // `errSecCSReqFailed` = signature is valid but does not come from
            // the expected team. Distinguish from unsigned or corrupted binary:
            // only this case looks like substitution.
            throw status == errSecCSReqFailed
                ? SignatureError.wrongAuthority
                : SignatureError.invalid(detail)
        }
    }
}
