import Foundation

/// Central configuration for the app.
enum AppConfig {

    // MARK: - Name
    //
    // Three forms, each for a different display width. The bundle name
    // (`TBD.app`, `com.byelior.tbd`) lives in `project.yml`.

    /// Expanded acronym. Finder, Spotlight, About dialog — everywhere
    /// someone might encounter the app without knowing what "TBD" means.
    static let fullName = "TBD - To be downloaded"

    /// Common name, read in the UI and app menu.
    static let displayName = "To be downloaded"

    /// Acronym alone, for tight spaces: menu bar, User-Agent,
    /// folder name.
    static let shortName = "TBD"

    /// Scheme for incoming links (`tbd://download?url=…`). Declared in
    /// `CFBundleURLTypes`, emitted by the share extension, received by
    /// `AppDelegate` — hence the constant shared between both targets: a
    /// diverging scheme would break sharing silently.
    static let urlScheme = "tbd"

    /// Default port for the LAN HTTP server (M2).
    static let defaultPort: UInt16 = 8787

    /// Names of binaries embedded in Resources/bin.
    static let ytDlpBinaryName = "yt-dlp"
    static let ffmpegBinaryName = "ffmpeg"

    // MARK: - Work Directory

    /// `~/Library/Application Support/TBD`: library, thumbnails, managed
    /// yt-dlp, download fragments, certificate bundle.
    ///
    /// `static let` rather than computed property: directory setup
    /// (and migration from the old one) happens only once, on first access,
    /// regardless of which thread requests it.
    static let supportDirectory: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent(shortName, isDirectory: true)

        // The app was called "Downloader" before it had a real name.
        // Reuse the folder as-is rather than start from scratch: otherwise the
        // library, thumbnails, and already-downloaded yt-dlp would be
        // abandoned in place. Remove when no installations still use it.
        let legacy = base.appendingPathComponent("Downloader", isDirectory: true)
        if !fm.fileExists(atPath: directory.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: directory)
        }

        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Marketing version of the bundle (`CFBundleShortVersionString`), used
    /// notably as the User-Agent for the app's network calls.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Author

    /// Links displayed in settings.
    enum Author {
        static let name = "Elior"
        static let website = URL(string: "https://byelior.com")!
        static let github = URL(string: "https://github.com/eliorpom-cmd")!
        static let instagram = URL(string: "https://instagram.com/elior.create")!

        /// Support page. Ko-fi rather than Buy Me a Coffee: the platform takes
        /// nothing from free-tier donations (BMC takes 5%), and payouts go via
        /// Stripe, straight to a bank account.
        static let support = URL(string: "https://ko-fi.com/eliorpom")!
    }

    // MARK: - Credits

    /// What the app owes to others, as displayed in settings.
    ///
    /// The list is not decorative: yt-dlp and FFmpeg DO the work, and
    /// the icon is not the author's own creation. `docs/THIRD-PARTY.md` remains
    /// the long form (licenses, obligations) — here we give credit and
    /// links, not legal reasoning.
    enum Credits {

        /// Author of the app icon. The delivered artwork (`AppIcon.icon`) is
        /// theirs; the app would have no face without it.
        enum Icon {
            static let author = "Saint"
            static let handle = "@app_settings"
            static let alias = "System Settings"
            static let url = URL(string: "https://x.com/app_settings")!
        }

        static let ytDlp = URL(string: "https://github.com/yt-dlp/yt-dlp")!
        static let ffmpeg = URL(string: "https://ffmpeg.org")!
        static let flyingFox = URL(string: "https://github.com/swhitty/FlyingFox")!

        /// The license details, in the repository. Built from
        /// `updateRepository` so renaming the repo doesn't leave a
        /// dead link behind.
        static let licenses = URL(
            string: "https://github.com/\(updateRepository)/blob/main/docs/THIRD-PARTY.md")!

        /// The app's own license. It is not there for decoration:
        /// under AGPL, anyone distributing a modified version — including by
        /// serving it over a network, which Network Access does — must
        /// provide the source. The link makes this obligation findable instead
        /// of letting it sleep in a repository file.
        static let license = URL(
            string: "https://github.com/\(updateRepository)/blob/main/LICENSE")!
    }

    // MARK: - App Updates

    /// GitHub repository whose releases serve as the update channel.
    static let updateRepository = "eliorpom-cmd/to-be-downloaded"

    /// Ed25519 public keys (base64) that authenticate update archives. A valid
    /// signature for **any one** of them is sufficient.
    ///
    /// Since the app is not notarized by Apple, this signature is the ONLY
    /// proof of update authenticity: without it, nothing is installed.
    ///
    /// There are TWO on purpose. The first is used daily; the second is a
    /// backup key stored off the build machine. Without it, losing the
    /// current key would permanently break automatic updates for already-
    /// installed apps — the only incident we could not recover from, since
    /// an update would be needed to fix the key.
    ///
    /// Trade-off: two keys can authorize an update instead of one.
    /// Hence the rule — the backup key does NOT live on the build machine.
    ///
    /// ⚠️ Never remove a key already published: installed versions know only
    /// these.
    static let updatePublicKeys = [
        "6ylYSJBktHoAANVp3Lt/yATR1wMi1dNWVxoTtH+ix/U=",  // current
        "Krj7bauZKnfutbN2UrwIhvcWYT/8lV5shEO3Bvlb1Qo=",  // backup (off-machine)
    ]

    /// Accepted hosts for update downloads. The URL comes from an API
    /// response, so we don't follow it blindly: HTTPS required and
    /// known host, even though Ed25519 signature (app) or SHA-256 hash
    /// (yt-dlp) is the real line of defense.
    private static let trustedUpdateHosts: Set<String> = [
        "github.com", "www.github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "raw.githubusercontent.com",
    ]

    static func isTrustedUpdateURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else { return false }
        return trustedUpdateHosts.contains(host)
    }

    // MARK: - FFmpeg

    /// FFmpeg is NOT shipped in the bundle, and it's not a size issue: the
    /// static build we were embedding was compiled with `--enable-nonfree`,
    /// which makes it **legally non-redistributable** (its own `ffmpeg -L`
    /// says so). No license on this repository changes that: we cannot grant
    /// rights to code we don't own. Downloading it on first launch shifts
    /// distribution to whoever has the right to do it.
    ///
    /// Source chosen: Martin Riedl's builds. `--enable-gpl
    /// --enable-version3` **without** `--enable-nonfree`, so GPLv3 and
    /// redistributable; native arm64; Developer ID signed (verified on
    /// install); and most importantly, stable "latest" URLs with a
    /// `.sha256` published alongside each archive.
    enum FFmpegSource {
        /// Returns a 307 redirect to the versioned archive — from which we
        /// extract the available version without downloading the 28 MB.
        static let latestBase = "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release"

        /// Both executables are published separately. yt-dlp needs
        /// BOTH: ffprobe probes streams before assembly.
        static let components = ["ffmpeg", "ffprobe"]

        /// Apple team identifier expected on the binary signature.
        /// This is the real guarantee of the chain: the SHA-256 comes from the
        /// same host as the archive and only protects against truncated
        /// transfers, whereas a Developer ID signature cannot be forged by
        /// someone who took control of the server.
        static let signingTeam = "KU3N25YGLU"

        static let homepage = URL(string: "https://ffmpeg.martin-riedl.de")!

        private static let trustedHosts: Set<String> = ["ffmpeg.martin-riedl.de"]

        static func isTrustedURL(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased()
            else { return false }
            return trustedHosts.contains(host)
        }
    }
}
