// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// Settings, as a sidebar panel (not a separate window): ⌘, opens it.
struct SettingsPane: View {
    @ObservedObject var settings: AppSettings
    let manager: DownloadManager
    @ObservedObject var server: ServerController
    @ObservedObject var library: LibraryStore
    @ObservedObject var updater: EngineUpdater
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var ffmpeg: FFmpegInstaller

    @State private var portText = ""
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            // No page title: the sidebar names the destination, like on
            // Download and Remote Control.
            VStack(alignment: .leading, spacing: Theme.Space.s20) {
                section("Downloads") {
                    row("Destination folder", detail: settings.outputDirectory.path) {
                        Button("Choose…", action: chooseFolder).buttonStyle(.push)
                    }
                    divider
                    row("Concurrent downloads",
                        detail: "More at once is not faster. The bandwidth is the same.") {
                        Picker("", selection: $settings.maxConcurrent) {
                            ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    divider
                    row("File names", detail: filenameDetail) {
                        picker($settings.filenameTemplate, values: FilenameTemplate.allCases) {
                            $0.label
                        }
                    }
                    if settings.filenameTemplate == .custom {
                        divider
                        row("Pattern", detail: "yt-dlp fields, without the extension") {
                            TextField("%(title)s", text: $settings.filenameCustom)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                    }
                }

                section("Format") {
                    // Not "Default format": Video and Audio are not formats,
                    // they are what you came for. MP4 and M4A are the formats,
                    // and they are set further down.
                    row("Download as", detail: "What the round button does by default") {
                        picker($settings.defaultKind, values: MediaKind.allCases) { $0.label }
                    }
                    divider
                    row("Video quality", detail: videoQualityDetail, wraps: true) {
                        picker($settings.defaultVideoQuality, values: VideoQuality.allCases) { $0.label }
                    }
                    divider
                    row("Subtitles",
                        detail: "Embedded as a track in the MP4, when the video has them") {
                        Toggle("", isOn: $settings.embedSubtitles)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    if settings.embedSubtitles {
                        divider
                        row("Subtitle language",
                            detail: "English is always kept as a fallback") {
                            picker($settings.subtitleLanguage,
                                   values: SubtitleLanguage.allCases) { $0.label }
                        }
                        divider
                        row("Use automatic captions",
                            detail: "When the channel wrote none. Machine transcription, "
                                  + "no punctuation, often wrong.",
                            wraps: true) {
                            Toggle("", isOn: $settings.autoSubtitles)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                    divider
                    row("Audio format", detail: settings.audioFormat.detail) {
                        picker($settings.audioFormat, values: AudioFormat.allCases) { $0.label }
                    }
                    if settings.audioFormat.usesBitrate {
                        divider
                        row("Audio bitrate") {
                            picker($settings.defaultAudioBitrate, values: AudioBitrate.allCases) {
                                $0.label
                            }
                        }
                    }
                }

                section("Shortcuts") {
                    row("Paste and download from anywhere",
                        detail: "Works while the app runs, even with no window open") {
                        Toggle("", isOn: $settings.globalShortcut)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    divider
                    row("Shortcut", detail: shortcutDetail) {
                        ShortcutRecorder(settings: settings)
                            .disabled(!settings.globalShortcut)
                            .opacity(settings.globalShortcut ? 1 : 0.4)
                    }
                }

                section("Application") {
                    // Full name: this is where you verify what was installed,
                    // the acronym alone wouldn't be enough.
                    row("\(AppConfig.fullName) \(appUpdater.currentVersion)",
                        detail: appUpdateDetail) {
                        appUpdateControl
                    }
                    divider
                    row("Update automatically",
                        detail: "Signed releases only, checked daily") {
                        Toggle("", isOn: $settings.autoUpdateApp)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                section("Components") {
                    // First row, and phrased as the rule the two below follow.
                    // People were updating yt-dlp and FFmpeg by hand because
                    // the section led with two "Check Now" buttons and never
                    // said the app already does it.
                    row("Keep components up to date",
                        detail: "yt-dlp and FFmpeg update themselves in the background, "
                              + "once a day. YouTube changes often, and this is what "
                              + "keeps downloads working.",
                        wraps: true) {
                        Toggle("", isOn: $settings.autoUpdateEngine)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    divider
                    row("yt-dlp", detail: engineDetail) {
                        HStack(spacing: Theme.Space.s8) {
                            if updater.status.isBusy {
                                ProgressView().controlSize(.small)
                            }
                            Button(updater.status == .downloading ? "Updating…" : "Check Now") {
                                Task { await updater.checkForUpdate(userInitiated: true) }
                            }
                            .buttonStyle(.push)
                            .disabled(updater.status.isBusy)
                        }
                    }
                    divider
                    row("Update channel", detail: settings.updateChannel.detail) {
                        Picker("", selection: channelBinding) {
                            ForEach(UpdateChannel.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    divider
                    // FFmpeg is downloaded, never shipped: the build we used
                    // wasn't redistribution-legal. This row shows where it
                    // comes from — it's the only component the app fetches
                    // from anywhere but itself or yt-dlp.
                    row("FFmpeg", detail: ffmpegDetail, wraps: true) {
                        HStack(spacing: Theme.Space.s8) {
                            if ffmpeg.status.isBusy {
                                ProgressView().controlSize(.small)
                            }
                            // Three different situations, three different
                            // buttons. Offering "Check Now" for an FFmpeg the
                            // app does not own would promise something it
                            // cannot do.
                            Button(ffmpegButtonTitle, action: ffmpegAction)
                                .buttonStyle(.push)
                                .disabled(ffmpeg.status.isBusy)
                        }
                    }
                }

                section("Appearance") {
                    row("Theme") {
                        Picker("", selection: $settings.appearance) {
                            ForEach(AppearancePreference.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 210)
                    }
                }

                section("Remote Control") {
                    row("Let devices on your Wi-Fi use this Mac",
                        detail: server.isRunning
                            ? "Running. The port is open."
                            : "Off. No port is open.") {
                        Toggle("", isOn: remoteControlBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    divider
                    row("Port", detail: "Requires a server restart") {
                        HStack(spacing: Theme.Space.s8) {
                            TextField("", text: $portText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onSubmit(applyPort)
                            Button("Apply & Restart", action: applyPort)
                                .buttonStyle(.push)
                                .disabled(UInt16(portText) == nil || UInt16(portText) == settings.port)
                        }
                    }
                    divider
                    row("Local address", detail: server.url ?? "Remote control is off") {
                        Button("Copy") {
                            guard let url = server.url else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        }
                        .buttonStyle(.push)
                        .disabled(server.url == nil)
                    }
                }

                section("Library") {
                    row("Stored entries",
                        detail: "Removing entries never deletes the files on disk") {
                        HStack(spacing: Theme.Space.s8) {
                            Text("\(library.items.count)")
                                .font(Theme.Text.body)
                                .foregroundStyle(Theme.labelSecondary)
                            Button("Clear Library") { showClearConfirm = true }
                                .buttonStyle(.push)
                                .disabled(library.items.isEmpty)
                        }
                    }
                }

                section("About") {
                    row("Made by \(AppConfig.Author.name)",
                        detail: "byelior.com · github.com/eliorpom-cmd · @elior.create") {
                        HStack(spacing: Theme.Space.s2) {
                            link("globe", AppConfig.Author.website, help: "byelior.com")
                            // Real brands for GitHub and Instagram; the personal
                            // site keeps the system globe, it has no logo.
                            logoLink("github", fallback: "chevron.left.forwardslash.chevron.right",
                                     AppConfig.Author.github, help: "GitHub · eliorpom-cmd")
                            logoLink("instagram", fallback: "camera",
                                     AppConfig.Author.instagram, help: "Instagram · elior.create")
                        }
                    }
                    divider
                    row("Support the app",
                        detail: "\(AppConfig.displayName) is free. A coffee keeps it updated.") {
                        Button("Support Me") {
                            NSWorkspace.shared.open(AppConfig.Author.support)
                        }
                        .buttonStyle(.push)
                    }
                }

                creditsSection
            }
            .padding(.horizontal, Theme.Space.s24)
            .padding(.top, WindowChrome.trafficLightInset + Theme.Space.s16)
            .padding(.bottom, Theme.Space.s32)
            // The column stays readable at 720 pt, but the frame around it
            // spans the pane. Two things follow, and both were reported: the
            // column CENTRES instead of clinging to the left edge on a wide
            // window, and the scroll bar — which belongs to the ScrollView, not
            // to its content — lands on the window edge where it belongs.
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .onAppear { portText = String(settings.port) }
        // The naming pattern lives in the engine config: must be rebuilt
        // or the change only takes effect on the next app launch.
        .onChange(of: settings.filenameTemplate) { _ in manager.reconfigure() }
        .onChange(of: settings.filenameCustom) { _ in manager.reconfigure() }
        .task { await updater.refreshInstalledVersion() }
        .task { await ffmpeg.refreshInstalledVersion() }
        .confirmationDialog(
            "Clear the library?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Library", role: .destructive) { manager.forgetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only empties the list. The downloaded files stay on disk.")
        }
    }

    /// A rejected shortcut won't show otherwise: Carbon returns an error,
    /// but nothing happens on screen unless we say so.
    private var shortcutDetail: String {
        if settings.shortcutRejected {
            return "Already taken by another app. Pick another one."
        }
        return settings.globalShortcut ? "Click to change it" : "Turn the shortcut on first"
    }

    /// Max is the one quality with a consequence attached, so the row says so
    /// permanently. The Download screen warns once; someone who chose Max as
    /// their default made the choice here and can be reminded here.
    private var videoQualityDetail: String? {
        settings.defaultVideoQuality == .max
            ? "Max reaches 4K, which YouTube only serves as VP9. "
                + "QuickTime and the TV app cannot play it; VLC and IINA can."
            : nil
    }

    /// Concrete example below the setting: a naming template only makes
    /// sense by seeing what it produces.
    private var filenameDetail: String {
        settings.filenameTemplate == .custom
            ? "Your own yt-dlp pattern"
            : settings.filenameTemplate.example
    }

    // MARK: - App Update

    private var appUpdateDetail: String {
        switch appUpdater.status {
        case .unavailable(let reason):
            return reason
        case .checking:
            return "Looking for a new version…"
        case .downloading(let fraction):
            return "Downloading… \(Int(fraction * 100))%"
        case .verifying:
            return "Checking the developer signature…"
        case .ready(let version):
            return "Version \(version) is installed. Relaunch to use it."
        case .upToDate:
            return "Up to date"
        case .failed(let message):
            return message
        case .idle:
            guard let last = appUpdater.lastCheck else { return "Never checked for updates" }
            return "Checked \(Format.relative(last))"
        }
    }

    @ViewBuilder
    private var appUpdateControl: some View {
        switch appUpdater.status {
        case .unavailable:
            EmptyView()
        case .ready:
            Button("Relaunch") {
                // Release the port before returning: otherwise the new
                // instance would start on a port still held by this one.
                server.stop()
                appUpdater.relaunch()
            }
            .buttonStyle(.push)
        default:
            HStack(spacing: Theme.Space.s8) {
                if appUpdater.status.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Check Now") {
                    Task { await appUpdater.checkForUpdate(userInitiated: true) }
                }
                .buttonStyle(.push)
                .disabled(appUpdater.status.isBusy)
            }
        }
    }

    // MARK: - Engine

    /// Detail row: version, source, and result of the last check.
    private var engineDetail: String {
        var parts: [String] = []
        parts.append(updater.installedVersion.map { "Version \($0)" } ?? "Version unknown")
        if let channel = updater.installedChannel {
            // Makes visible a mismatch between installed binary and chosen
            // channel: otherwise you'd think you're on stable with a nightly.
            parts.append(channel == settings.updateChannel
                ? "updated copy"
                : "\(channel.label.lowercased()) build, switching on next check")
        } else {
            parts.append("shipped with the app")
        }

        switch updater.status {
        case .installed(let version):
            parts.append("just updated to \(version)")
        case .upToDate:
            parts.append("up to date")
        case .failed(let message):
            parts.append(message)
        case .idle, .checking, .downloading:
            if let last = updater.lastCheck { parts.append("checked \(Format.relative(last))") }
        }
        return parts.joined(separator: " · ")
    }

    private var ffmpegButtonTitle: String {
        if !ffmpeg.isInstalled { return "Install" }
        return ffmpeg.usesExternalFFmpeg ? "Download a Copy" : "Check Now"
    }

    private func ffmpegAction() {
        Task {
            if !ffmpeg.isInstalled {
                await ffmpeg.installIfMissing()
            } else if ffmpeg.usesExternalFFmpeg {
                await ffmpeg.installOwnCopy()
            } else {
                await ffmpeg.checkForUpdate(userInitiated: true)
            }
        }
    }

    /// Same spirit as `engineDetail`, plus where it came from: it's the only
    /// binary the app fetches from outside GitHub, so make that clear — and
    /// when it is the machine's own, say that instead, since none of the
    /// update machinery applies to it.
    private var ffmpegDetail: String {
        var parts: [String] = []
        if let version = ffmpeg.installedVersion {
            parts.append("Version \(version)")
        } else {
            parts.append(ffmpeg.isInstalled ? "Version unknown" : "Not installed yet")
        }
        if ffmpeg.usesExternalFFmpeg {
            let target = (try? FileManager.default.destinationOfSymbolicLink(
                atPath: BinaryLocator.managedFFmpeg.path)) ?? "elsewhere on this Mac"
            parts.append("yours, at \(target)")
            parts.append("updated by whoever installed it, not by \(AppConfig.shortName)")
            return parts.joined(separator: " · ")
        }
        parts.append("downloaded from \(AppConfig.FFmpegSource.homepage.host ?? "its publisher")")

        switch ffmpeg.status {
        case .installed(let version):  parts.append("just installed \(version)")
        case .upToDate:                parts.append("up to date")
        case .downloading(let f):      parts.append("downloading… \(Int(f * 100))%")
        case .installing:              parts.append("verifying signature")
        case .failed(let message):     parts.append(message)
        case .idle, .checking:
            if let last = ffmpeg.lastCheck { parts.append("checked \(Format.relative(last))") }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Remote Control

    /// Reads the server, writes the preference. Reading `server.isRunning`
    /// rather than the stored flag keeps the switch honest when the server
    /// failed to bind — the port is the truth, the preference is only a wish.
    private var remoteControlBinding: Binding<Bool> {
        Binding(
            get: { server.isRunning },
            set: { wanted in
                settings.remoteControl = wanted
                wanted ? server.start() : server.stop()
            })
    }

    /// Changing channels immediately triggers a check: otherwise the
    /// setting would have no visible effect until tomorrow.
    private var channelBinding: Binding<UpdateChannel> {
        Binding(
            get: { settings.updateChannel },
            set: { newValue in
                guard newValue != settings.updateChannel else { return }
                settings.updateChannel = newValue
                updater.channelDidChange()
            })
    }

    // MARK: - Credits

    /// What the app owes others. `docs/THIRD-PARTY.md` gives the long version;
    /// this section ensures credit is VISIBLE WITHOUT reading the repo — the
    /// app doesn't download anything itself, and the icon isn't the author's work.
    private var creditsSection: some View {
        section("Credits") {
            creditRow("App icon by \(AppConfig.Credits.Icon.author)",
                      detail: "aka \(AppConfig.Credits.Icon.alias) · "
                            + "\(AppConfig.Credits.Icon.handle) on X",
                      url: AppConfig.Credits.Icon.url)
            divider
            creditRow("yt-dlp",
                      detail: "Resolves the links and does the downloading. Public domain.",
                      url: AppConfig.Credits.ytDlp)
            divider
            creditRow("FFmpeg",
                      detail: "Joins video and audio, extracts audio, embeds subtitles. GPL v3.",
                      url: AppConfig.Credits.ffmpeg)
            divider
            creditRow("FlyingFox",
                      detail: "The HTTP server behind Remote Control. MIT.",
                      url: AppConfig.Credits.flyingFox)
            divider
            creditRow("License",
                      detail: "AGPL-3.0. Free to fork, and forks stay free too.",
                      url: AppConfig.Credits.license)
            divider
            creditRow("Third-party licenses",
                      detail: "What ships, what is downloaded, and under which terms",
                      url: AppConfig.Credits.licenses)
        }
    }

    /// Credit row: the ENTIRE row is the link. A link glyph at the end of
    /// the line, like in "About", would suit a row that has other controls;
    /// here the row says nothing but "go look there".
    private func creditRow(_ title: String, detail: String, url: URL) -> some View {
        CreditRow(title: title, detail: detail, url: url)
    }

    // MARK: - Layout Blocks

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s6) {
            SectionHeader(title: title)
            VStack(spacing: 0) { content() }
                .groupedCard()
        }
    }

    private var divider: some View {
        Divider().overlay(Theme.separator)
    }

    private func row<Trailing: View>(
        _ title: String,
        detail: String? = nil,
        /// Let the detail run onto a second line. Off by default: most details
        /// are paths, where one line with the middle elided is what you want.
        /// A sentence elided in the middle is just broken.
        wraps: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: Theme.Space.s12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.label)
                if let detail {
                    Text(detail)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.labelSecondary)
                        .lineLimit(wraps ? 3 : 1)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: wraps)
                }
            }
            Spacer(minLength: Theme.Space.s12)
            trailing()
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s10)
    }

    /// External link reduced to a glyph: three full addresses would take
    /// the row width; the detail line already shows them.
    private func link(_ symbol: String, _ url: URL, help: String) -> some View {
        IconButton(symbol: symbol, size: 13, help: help) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Same thing, with the platform logo instead of a system glyph.
    private func logoLink(
        _ logo: String, fallback: String, _ url: URL, help: String
    ) -> some View {
        BrandLogoButton(logo: logo, fallbackSymbol: fallback, help: help) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Subtle macOS popup, aligned with mockup style.
    private func picker<T: Hashable & Identifiable>(
        _ selection: Binding<T>,
        values: [T],
        label: @escaping (T) -> String
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(values) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    // MARK: - Actions



    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
            manager.reconfigure()
        }
    }

    private func applyPort() {
        guard let p = UInt16(portText), p != settings.port else { return }
        settings.port = p
        server.restart()
    }
}

// MARK: - Credit Row

/// Settings row that is entirely clickable and opens a page.
///
/// Separate view, not a function in `SettingsPane`: it needs its own
/// hover `@State`, otherwise all five rows would light up together. Hover is
/// the only affordance available — the design system is monochrome,
/// so you can't color a link blue.
private struct CreditRow: View {
    let title: String
    let detail: String
    let url: URL

    @State private var hovering = false

    var body: some View {
        // NOT a `Button`. On macOS 26, a button gets system hover chrome —
        // a rounded inset pill placed ON TOP OF the row background — and no
        // `ButtonStyle` overrides it. A plain view with `onTapGesture` renders
        // ONLY what's written here; accessibility traits still convey the
        // link role.
        HStack(spacing: Theme.Space.s12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.label)
                    // Hover reads on TEXT, not a solid. An underlined link
                    // says what it does, and no shape can misalign: row
                    // geometry is no longer a factor.
                    .underline(hovering)
                Text(detail)
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Theme.Space.s12)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Theme.label : Theme.labelTertiary)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
        .accessibilityAction { NSWorkspace.shared.open(url) }
        .help(url.absoluteString)
    }
}
