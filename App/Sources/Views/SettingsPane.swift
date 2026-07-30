import SwiftUI
import AppKit

/// Réglages, en panneau de sidebar (et non en fenêtre séparée) : ⌘, y mène.
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
            VStack(alignment: .leading, spacing: Theme.Space.s20) {
                Text("Settings")
                    .font(Theme.Text.largeTitle)
                    .foregroundStyle(Theme.label)

                section("Downloads") {
                    row("Destination folder", detail: settings.outputDirectory.path) {
                        Button("Choose…", action: chooseFolder).buttonStyle(.push)
                    }
                    divider
                    row("At the same time",
                        detail: "More at once is not faster — the bandwidth is the same") {
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
                    row("Default format") {
                        picker($settings.defaultKind, values: MediaKind.allCases) { $0.label }
                    }
                    divider
                    row("Video quality") {
                        picker($settings.defaultVideoQuality, values: VideoQuality.allCases) { $0.label }
                    }
                    divider
                    row("Subtitles",
                        detail: "Embedded as a track in the MP4, when the video has them") {
                        Toggle("", isOn: $settings.embedSubtitles)
                            .toggleStyle(.switch)
                            .labelsHidden()
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
                    // Le nom complet : c'est la ligne où l'on vient vérifier ce
                    // qu'on a installé, le sigle seul n'y suffirait pas.
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

                section("Engine") {
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
                    row("Check automatically",
                        detail: "Once a day while the app runs. YouTube changes often.") {
                        Toggle("", isOn: $settings.autoUpdateEngine)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    divider
                    // FFmpeg est téléchargé, jamais livré : le build qu'on
                    // embarquait n'était pas redistribuable. Cette ligne dit
                    // d'où il vient — c'est le seul composant que l'app va
                    // chercher ailleurs que chez elle-même ou chez yt-dlp.
                    row("FFmpeg", detail: ffmpegDetail) {
                        HStack(spacing: Theme.Space.s8) {
                            if ffmpeg.status.isBusy {
                                ProgressView().controlSize(.small)
                            }
                            Button(ffmpeg.isInstalled ? "Check Now" : "Install") {
                                Task {
                                    ffmpeg.isInstalled
                                        ? await ffmpeg.checkForUpdate(userInitiated: true)
                                        : await ffmpeg.installIfMissing()
                                }
                            }
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

                section("Network") {
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
                    row("Local address", detail: server.url ?? "Server stopped") {
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
                            // Vraies marques pour GitHub et Instagram ; le site
                            // personnel garde le globe système, il n'a pas de
                            // logo à lui.
                            logoLink("github", fallback: "chevron.left.forwardslash.chevron.right",
                                     AppConfig.Author.github, help: "GitHub — eliorpom-cmd")
                            logoLink("instagram", fallback: "camera",
                                     AppConfig.Author.instagram, help: "Instagram — elior.create")
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
            .frame(maxWidth: 720, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { portText = String(settings.port) }
        // Le motif de nommage vit dans la configuration du moteur : il faut le
        // reconstruire, sinon le changement n'aurait d'effet qu'au prochain
        // lancement de l'app.
        .onChange(of: settings.filenameTemplate) { _ in manager.reconfigure() }
        .onChange(of: settings.filenameCustom) { _ in manager.reconfigure() }
        .task { await updater.refreshInstalledVersion() }
        .task { await ffmpeg.refreshInstalledVersion() }
        .confirmationDialog(
            "Clear the library?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Library", role: .destructive) { library.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only empties the list. The downloaded files stay on disk.")
        }
    }

    /// Un raccourci refusé ne se voit pas autrement : Carbon rend une erreur,
    /// mais rien ne se passe à l'écran si on ne la dit pas.
    private var shortcutDetail: String {
        if settings.shortcutRejected {
            return "Already taken by another app — pick another one"
        }
        return settings.globalShortcut ? "Click to change it" : "Turn the shortcut on first"
    }

    /// Exemple concret sous le réglage : un gabarit de nommage ne se comprend
    /// qu'en voyant ce qu'il produit.
    private var filenameDetail: String {
        settings.filenameTemplate == .custom
            ? "Your own yt-dlp pattern"
            : settings.filenameTemplate.example
    }

    // MARK: - Mise à jour de l'app

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
            return "Version \(version) is installed — relaunch to use it"
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
                // Libère le port avant de rendre la main : sinon la nouvelle
                // instance démarrerait sur un port encore occupé par celle-ci.
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

    // MARK: - Moteur

    /// Ligne de détail : version, provenance, et résultat du dernier contrôle.
    private var engineDetail: String {
        var parts: [String] = []
        parts.append(updater.installedVersion.map { "Version \($0)" } ?? "Version unknown")
        if let channel = updater.installedChannel {
            // Rend visible un décalage entre le binaire installé et le canal
            // choisi : sinon on croit tourner en stable avec une nightly.
            parts.append(channel == settings.updateChannel
                ? "updated copy"
                : "\(channel.label.lowercased()) build — will switch on next check")
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

    /// Même esprit que `engineDetail`, avec la provenance en plus : c'est le
    /// seul binaire que l'app va chercher hors de GitHub, autant que ça se lise.
    private var ffmpegDetail: String {
        var parts: [String] = []
        if let version = ffmpeg.installedVersion {
            parts.append("Version \(version)")
        } else {
            parts.append(ffmpeg.isInstalled ? "Version unknown" : "Not installed yet")
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

    /// Changer de canal relance immédiatement un contrôle : sinon le réglage
    /// n'aurait aucun effet visible avant le lendemain.
    private var channelBinding: Binding<UpdateChannel> {
        Binding(
            get: { settings.updateChannel },
            set: { newValue in
                guard newValue != settings.updateChannel else { return }
                settings.updateChannel = newValue
                updater.channelDidChange()
            })
    }

    // MARK: - Crédits

    /// Ce que l'app doit à d'autres. `docs/THIRD-PARTY.md` en donne la version
    /// longue ; cette section-ci est là pour que le crédit soit visible SANS
    /// aller lire le dépôt — l'app ne télécharge rien elle-même, et son icône
    /// n'est pas de la main de son auteur.
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
                      detail: "The HTTP server behind Network Access. MIT.",
                      url: AppConfig.Credits.flyingFox)
            divider
            creditRow("License",
                      detail: "AGPL-3.0 — free to fork, and forks stay free too",
                      url: AppConfig.Credits.license)
            divider
            creditRow("Third-party licenses",
                      detail: "What ships, what is downloaded, and under which terms",
                      url: AppConfig.Credits.licenses)
        }
    }

    /// Ligne de crédit : la ligne ENTIÈRE est le lien. Un glyphe de lien en bout
    /// de ligne, comme dans « About », conviendrait pour une ligne qui a par
    /// ailleurs un réglage ; ici la ligne ne dit rien d'autre que « va voir là ».
    private func creditRow(_ title: String, detail: String, url: URL) -> some View {
        CreditRow(title: title, detail: detail, url: url)
    }

    // MARK: - Briques de mise en page

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
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: Theme.Space.s12)
            trailing()
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s10)
    }

    /// Lien externe réduit à son glyphe : trois adresses en toutes lettres
    /// tiendraient la largeur de la ligne, la ligne de détail les donne déjà.
    private func link(_ symbol: String, _ url: URL, help: String) -> some View {
        IconButton(symbol: symbol, size: 13, help: help) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Même chose, avec le logo de la plateforme à la place d'un glyphe système.
    private func logoLink(
        _ logo: String, fallback: String, _ url: URL, help: String
    ) -> some View {
        BrandLogoButton(logo: logo, fallbackSymbol: fallback, help: help) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Popup macOS discret, aligné sur le style de la maquette.
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

// MARK: - Ligne de crédit

/// Ligne de réglages entièrement cliquable, qui ouvre une page.
///
/// Vue à part et non fonction dans `SettingsPane` : il lui faut son propre
/// `@State` de survol, sinon les cinq lignes s'allumeraient ensemble. Le
/// survol est la seule affordance disponible — le design system est monochrome,
/// on ne peut pas colorer un lien en bleu.
private struct CreditRow: View {
    let title: String
    let detail: String
    let url: URL

    @State private var hovering = false

    var body: some View {
        // PAS un `Button`. Sur macOS 26, un bouton reçoit une chrome de survol
        // du système — une pastille arrondie et en retrait, posée PAR-DESSUS le
        // fond de la ligne — et aucun `ButtonStyle` ne la reprend. Une vue nue
        // avec `onTapGesture` ne rend QUE ce qui est écrit ici ; les traits
        // d'accessibilité rendent le rôle de lien malgré tout.
        HStack(spacing: Theme.Space.s12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.label)
                    // Le survol se lit sur le TEXTE, pas sur un aplat. Un lien
                    // souligné dit ce qu'il fait, et aucune forme ne peut mal
                    // s'aligner : la géométrie de la ligne n'entre plus en jeu.
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
