// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// First launch, three screens.
///
/// It exists for one reason: the app used to download a 56 MB binary onto
/// someone's machine, over whatever connection they happened to be on, without
/// asking — and drop files in a folder it picked for them. Both are decisions
/// that belong to the person, and both are one question each.
///
/// Deliberately short. A walkthrough that explains features nobody has asked
/// about yet is a toll booth; these two questions have to be answered before
/// the app can work at all, which is the only thing that earns a first-run
/// screen.
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ffmpeg: FFmpegInstaller
    let manager: DownloadManager

    private enum Step: Int, CaseIterable { case welcome, folder, engine }

    @State private var step: Step = .welcome
    /// An FFmpeg found on the machine at the moment the last screen appeared.
    @State private var detected: URL?
    @State private var linkFailed: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: WindowChrome.trafficLightInset)
            Spacer()

            Group {
                switch step {
                case .welcome: welcome
                case .folder:  folder
                case .engine:  engine
                }
            }
            .frame(maxWidth: 460)

            Spacer()

            dots

            Spacer().frame(height: Theme.Space.s32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Space.s40)
        .animation(.easeOut(duration: 0.2), value: step)
        .animation(.easeOut(duration: 0.2), value: ffmpeg.status)
    }

    // MARK: - 1. Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            MascotView(size: 96, isActive: false)

            Spacer().frame(height: Theme.Space.s32)

            Text(AppConfig.displayName)
                .font(Theme.Text.title2)
                .foregroundStyle(Theme.label)

            Spacer().frame(height: Theme.Space.s8)

            Text("Paste a YouTube link, get the file. Two questions first, "
                 + "and they are the only two.")
                .font(Theme.Text.body)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: Theme.Space.s24)

            Button("Get Started") { step = .folder }
                .buttonStyle(.push)
        }
    }

    // MARK: - 2. Destination folder

    private var folder: some View {
        VStack(spacing: 0) {
            stepIcon("folder")

            Text("Where should the files go?")
                .font(Theme.Text.title3)
                .foregroundStyle(Theme.label)

            Spacer().frame(height: Theme.Space.s8)

            Text("Downloads land here, under their own title. You can change "
                 + "this later in Settings.")
                .font(Theme.Text.body)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: Theme.Space.s20)

            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.labelSecondary)
                Text(settings.outputDirectory.path)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: Theme.Space.s8)
                Button("Choose…", action: chooseFolder)
                    .buttonStyle(.plain)
                    .font(Theme.Text.bodyEmphasized)
                    .foregroundStyle(Theme.label)
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s10)
            .background(Theme.fillTertiary,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            Spacer().frame(height: Theme.Space.s24)

            // Pre-filled with ~/Downloads, so the common answer is one click.
            Button("Continue") { step = .engine }
                .buttonStyle(.push)
        }
    }

    // MARK: - 3. FFmpeg

    private var engine: some View {
        VStack(spacing: 0) {
            stepIcon("shippingbox")

            Text(engineTitle)
                .font(Theme.Text.title3)
                .foregroundStyle(Theme.label)

            Spacer().frame(height: Theme.Space.s8)

            Text(engineMessage)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: Theme.Space.s20)

            engineControls

            if let linkFailed {
                Spacer().frame(height: Theme.Space.s12)
                InlineNotice(symbol: "exclamationmark.triangle.fill", message: linkFailed)
            }
        }
        .task {
            // Looked up when the screen appears, not at launch: it costs four
            // stat calls, and asking earlier would be asking before it matters.
            detected = FFmpegInstaller.detectExisting()
        }
    }

    private var engineTitle: String {
        if ffmpeg.isInstalled { return "Ready" }
        switch ffmpeg.status {
        case .downloading, .checking: return "Getting FFmpeg"
        case .installing:             return "Checking it over"
        default:                      return "One component to fetch"
        }
    }

    private var engineMessage: String {
        if ffmpeg.isInstalled {
            return ffmpeg.usesExternalFFmpeg
                ? "Using the FFmpeg already on this Mac. Nothing was downloaded."
                : "FFmpeg is installed. That is everything."
        }
        switch ffmpeg.status {
        case .downloading(let fraction):
            return "About 56 MB, once. \(Int(fraction * 100))% done."
        case .installing:
            return "Verifying the publisher's signature."
        case .failed(let message):
            return message
        default:
            return "\(AppConfig.shortName) needs FFmpeg to join video and audio. "
                + "It is not bundled, because the licence of the build we used does "
                + "not allow passing it on, so it is a 56 MB download, once, "
                + "from its publisher. Nothing is fetched until you say so."
        }
    }

    @ViewBuilder
    private var engineControls: some View {
        if ffmpeg.isInstalled {
            Button("Start Using \(AppConfig.shortName)", action: finish)
                .buttonStyle(.push)
        } else {
            switch ffmpeg.status {
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.label)
                    .frame(width: 260)
            case .checking, .installing:
                ProgressView().controlSize(.small)
            default:
                VStack(spacing: Theme.Space.s10) {
                    Button(ffmpeg.status.isFailure ? "Try Again" : "Download FFmpeg") {
                        Task { await ffmpeg.installIfMissing() }
                    }
                    .buttonStyle(.push)

                    // Someone who already runs `brew install ffmpeg` should
                    // not be made to keep a second copy.
                    if let detected {
                        Button("Use the one at \(detected.path)") {
                            link(detected)
                        }
                        .buttonStyle(.plain)
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.label)
                    }

                    Button(detected == nil ? "Choose an FFmpeg I have…" : "Choose another…",
                           action: chooseFFmpeg)
                        .buttonStyle(.plain)
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.labelSecondary)

                    // Leaving without it is allowed. The Download screen will
                    // ask again, and until then nothing pretends to work.
                    Button("Not Now", action: finish)
                        .buttonStyle(.plain)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.labelTertiary)
                }
            }
        }
    }

    // MARK: - Chrome

    private func stepIcon(_ symbol: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.labelTertiary)
            Spacer().frame(height: Theme.Space.s16)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Circle()
                    .fill(item == step ? Theme.labelSecondary : Theme.fillPrimary)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = settings.outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
            manager.reconfigure()
        }
    }

    private func chooseFFmpeg() {
        guard let url = FFmpegPicker.choose(startingAt: detected?.deletingLastPathComponent())
        else { return }
        link(url)
    }

    private func link(_ url: URL) {
        linkFailed = nil
        Task {
            let ok = await ffmpeg.useExisting(at: url)
            if !ok, case .failed(let message) = ffmpeg.status { linkFailed = message }
        }
    }

    private func finish() {
        settings.onboarded = true
    }
}

extension FFmpegInstaller.Status {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
