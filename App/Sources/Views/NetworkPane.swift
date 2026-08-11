// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// Remote Control: turn the LAN server on, scan the QR from a phone, and
/// drive this Mac's downloads from it.
///
/// Two states, and they look different on purpose. **Off** is the state a
/// new user meets — nothing is running, so instead of a dimmed QR code
/// standing for a feature nobody has explained, the screen says what the
/// feature is and what turning it on does to their machine. **On** is a
/// working tool: code, address, and the controls for it.
struct NetworkPane: View {
    @ObservedObject var server: ServerController
    @ObservedObject var settings: AppSettings

    /// Slow clock: "device connected" depends on a recent ping.
    @State private var now = Date()

    private enum Status { case stopped, active, connected }

    private var status: Status {
        guard server.isRunning else { return .stopped }
        if let ping = server.lastClientPing, now.timeIntervalSince(ping) < 4 { return .connected }
        return .active
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: WindowChrome.trafficLightInset)
            Spacer()

            if server.isRunning {
                runningState
            } else {
                explanation
            }

            Spacer()
            Spacer(minLength: Theme.Space.s24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Space.s40)
        .animation(.easeOut(duration: 0.2), value: server.isRunning)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: - Off

    /// What the Library's empty state does for the library, this does for
    /// remote control: it is the only moment the feature can be explained to
    /// someone who has never used it.
    private var explanation: some View {
        VStack(spacing: 0) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.labelTertiary)

            Spacer().frame(height: Theme.Space.s16)

            Text("Download from your phone")
                .font(Theme.Text.title3)
                .foregroundStyle(Theme.label)

            Spacer().frame(height: Theme.Space.s8)

            Text("Turn this on and this Mac serves a small page to the "
                 + "devices on your Wi-Fi. Scan the code with a phone, paste a "
                 + "link there, and the download runs here, on the Mac's "
                 + "connection, into the Mac's folder. The finished file can be "
                 + "pulled back to the phone from the same page.")
                .font(Theme.Text.body)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430)

            Spacer().frame(height: Theme.Space.s20)

            // Said plainly, because opening a port on someone's machine
            // without telling them is exactly the complaint this screen
            // exists to answer.
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                fact("lock.shield", "Nothing is exposed to the internet. The "
                     + "address works on your local network only.")
                fact("power", "The port opens when you turn this on, and closes "
                     + "when you turn it off or quit \(AppConfig.shortName).")
                fact("person.2.slash", "Anyone on your Wi-Fi who has the address "
                     + "can queue a download. There is no password.")
            }
            .frame(maxWidth: 430, alignment: .leading)

            Spacer().frame(height: Theme.Space.s24)

            Button("Turn On Remote Control", action: startServer)
                .buttonStyle(.push)

            if let error = server.lastError {
                Spacer().frame(height: Theme.Space.s12)
                InlineNotice(symbol: "exclamationmark.triangle.fill", message: error)
                    .frame(maxWidth: 430)
            }
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Theme.labelTertiary)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - On

    private var runningState: some View {
        VStack(spacing: 0) {
            statusPill

            Spacer().frame(height: Theme.Space.s24)

            qrCard

            Spacer().frame(height: Theme.Space.s20)

            Text(server.url ?? "No address yet")
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Theme.label)
                .textSelection(.enabled)

            Spacer().frame(height: Theme.Space.s4)

            Text("Scan with your phone on the same Wi-Fi network")
                .font(Theme.Text.subheadline)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Spacer().frame(height: Theme.Space.s24)

            actions
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Image(systemName: statusSymbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.label)
            Text(statusLabel)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.label)
        }
        .padding(.vertical, Theme.Space.s6)
        .padding(.horizontal, Theme.Space.s12)
        .background(Theme.fillTertiary, in: Capsule())
    }

    private var statusSymbol: String {
        switch status {
        case .stopped:   return "wifi.slash"
        case .active:    return "antenna.radiowaves.left.and.right"
        case .connected: return "iphone.radiowaves.left.and.right"
        }
    }

    private var statusLabel: String {
        switch status {
        case .stopped:   return "Server stopped"
        case .active:    return "Server running"
        case .connected: return "Server running · 1 device connected"
        }
    }

    /// The QR stays **always light**, even in dark mode: a white code on
    /// black background scans poorly.
    private var qrCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.white)
                .frame(width: 196, height: 196)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 1)
                )

            if let url = server.url, let image = QRGenerator.image(from: url) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 156, height: 156)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 110, weight: .light))
                    .foregroundStyle(Color.black.opacity(0.25))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Space.s8) {
            Button("Copy Address") {
                guard let url = server.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            }
            .buttonStyle(.push)

            Button("Open in Browser") {
                guard let url = server.url, let link = URL(string: url) else { return }
                NSWorkspace.shared.open(link)
            }
            .buttonStyle(.push)

            Button("Turn Off", action: stopServer)
                .buttonStyle(.push)
        }
    }

    // MARK: - Actions

    // The preference is written HERE, at the two buttons, and nowhere else.
    // These are the only places a human expressed an intention about remote
    // control; `ServerController.stop()` is also called before an update
    // relaunch and by a port change, where it means nothing of the sort.

    private func startServer() {
        settings.remoteControl = true
        server.start()
    }

    private func stopServer() {
        settings.remoteControl = false
        server.stop()
    }
}
