import SwiftUI
import AppKit

/// Network access: QR to scan from your phone, LAN address, and server
/// control.
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

            statusPill

            Spacer().frame(height: Theme.Space.s24)

            qrCard

            Spacer().frame(height: Theme.Space.s20)

            Text(server.url ?? "No address yet")
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(server.isRunning ? Theme.label : Theme.labelTertiary)
                .textSelection(.enabled)

            Spacer().frame(height: Theme.Space.s4)

            Text(hint)
                .font(Theme.Text.subheadline)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Spacer().frame(height: Theme.Space.s24)

            actions

            Spacer()
            Spacer(minLength: Theme.Space.s24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Space.s40)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: - Status

    private var statusPill: some View {
        HStack(spacing: 7) {
            Image(systemName: statusSymbol)
                .font(.system(size: 13))
                .foregroundStyle(status == .stopped ? Theme.labelTertiary : Theme.label)
            Text(statusLabel)
                .font(Theme.Text.body)
                .foregroundStyle(status == .stopped ? Theme.labelSecondary : Theme.label)
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

    private var hint: String {
        switch status {
        case .stopped:
            return server.lastError
                ?? "Start the server to let devices on your Wi-Fi download from this Mac"
        case .active, .connected:
            return "Scan with your phone on the same Wi-Fi network"
        }
    }

    // MARK: - QR

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
        .opacity(server.isRunning ? 1 : 0.22)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: Theme.Space.s8) {
            if server.isRunning {
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

                Button("Stop Server") { server.stop() }
                    .buttonStyle(.push)
            } else {
                Button("Start Server") { server.start() }
                    .buttonStyle(.push)
            }
        }
    }
}
