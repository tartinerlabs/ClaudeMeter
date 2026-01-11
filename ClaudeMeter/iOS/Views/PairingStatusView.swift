//
//  PairingStatusView.swift
//  ClaudeMeter
//
//  Shows current pairing status and connected Mac info
//

#if os(iOS)
import SwiftUI
import ClaudeMeterKit

struct PairingStatusView: View {
    @Environment(PairingClient.self) private var client

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Connection Status
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.body)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if client.state == .connecting || client.state == .authenticating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Paired Mac Info
            if let mac = client.pairedMac, client.state == .connected {
                Divider()

                HStack {
                    Image(systemName: "desktopcomputer")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mac.name)
                            .font(.body)
                        Text("Last connected \(mac.lastConnected.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        client.unpair()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Error Message
            if let error = client.error {
                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error.errorDescription ?? "Connection error")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Last Received Snapshot
            if let snapshot = client.lastSnapshot, client.state == .connected {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Receiving Data")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        snapshotBadge(
                            label: "Session",
                            value: "\(snapshot.session.percentUsed)%",
                            status: snapshot.session.status
                        )
                        snapshotBadge(
                            label: "Opus",
                            value: "\(snapshot.opus.percentUsed)%",
                            status: snapshot.opus.status
                        )
                        if let sonnet = snapshot.sonnet {
                            snapshotBadge(
                                label: "Sonnet",
                                value: "\(sonnet.percentUsed)%",
                                status: sonnet.status
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var statusIcon: some View {
        Image(systemName: statusIconName)
            .font(.title3)
            .foregroundStyle(statusColor)
            .frame(width: 32)
    }

    private var statusIconName: String {
        switch client.state {
        case .disconnected:
            return "wifi.slash"
        case .connecting, .authenticating:
            return "wifi"
        case .connected:
            return "wifi"
        }
    }

    private var statusColor: Color {
        switch client.state {
        case .disconnected:
            return .secondary
        case .connecting, .authenticating:
            return .orange
        case .connected:
            return .green
        }
    }

    private var statusTitle: String {
        client.state.displayName
    }

    private var statusSubtitle: String {
        switch client.state {
        case .disconnected:
            if client.pairedMac != nil {
                return "Tap \"Scan QR Code\" to reconnect"
            }
            return "Scan QR code on your Mac to pair"
        case .connecting:
            return "Establishing connection..."
        case .authenticating:
            return "Verifying..."
        case .connected:
            return "Receiving usage data from Mac"
        }
    }

    private func snapshotBadge(label: String, value: String, status: UsageStatus) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(status.color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(status.color.opacity(0.1))
        )
    }
}

#Preview {
    PairingStatusView()
        .environment(PairingClient())
        .padding()
}
#endif
