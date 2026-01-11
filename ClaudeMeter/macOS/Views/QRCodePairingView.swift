//
//  QRCodePairingView.swift
//  ClaudeMeter
//
//  QR code display for pairing with iOS devices
//

#if os(macOS)
import SwiftUI
import CoreImage.CIFilterBuiltins
import ClaudeMeterKit

struct QRCodePairingView: View {
    @Environment(PairingServer.self) private var server
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: NSImage?
    @State private var isGenerating = false
    @State private var timeRemaining: Int = 60
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Pair with iPhone")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if let qrImage {
                // QR Code Display
                qrCodeSection(image: qrImage)
            } else if isGenerating {
                // Loading
                loadingSection
            } else {
                // Generate Button
                generateSection
            }

            // Connected Devices
            if !server.connectedDevices.isEmpty {
                connectedDevicesSection
            }

            // Error Display
            if let error = server.error {
                errorSection(error: error)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear {
            // Auto-start server if not running
            if !server.isRunning {
                server.start()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    // MARK: - Sections

    private func qrCodeSection(image: NSImage) -> some View {
        VStack(spacing: 16) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text("Scan with ClaudeMeter on iPhone")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Countdown
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text("Expires in \(timeRemaining)s")
            }
            .font(.caption)
            .foregroundStyle(timeRemaining < 15 ? .red : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(timeRemaining < 15 ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
            )

            // Regenerate Button
            Button("Generate New Code") {
                Task {
                    await server.invalidateCurrentQR()
                    generateQRCode()
                }
            }
            .buttonStyle(.link)
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Generating QR Code...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(height: 240)
    }

    private var generateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Generate a QR code to pair your iPhone with this Mac")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Generate QR Code") {
                generateQRCode()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!server.isRunning)

            if !server.isRunning {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Starting server...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 240)
    }

    private var connectedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("Connected Devices")
                .font(.headline)

            ForEach(server.connectedDevices) { device in
                HStack {
                    Image(systemName: "iphone")
                        .foregroundStyle(.blue)
                    Text(device.name)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button {
                        server.disconnectDevice(device)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect device")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
        }
    }

    private func errorSection(error: PairingError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.errorDescription ?? "Unknown error")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }

    // MARK: - Actions

    private func generateQRCode() {
        isGenerating = true
        timer?.invalidate()

        Task {
            guard let payload = await server.generatePairingQR() else {
                await MainActor.run {
                    isGenerating = false
                }
                return
            }

            guard let qrData = payload.toQRData() else {
                await MainActor.run {
                    isGenerating = false
                }
                return
            }

            let image = generateQRImage(from: qrData)

            await MainActor.run {
                qrImage = image
                isGenerating = false
                timeRemaining = 60
                startCountdown()
            }
        }
    }

    private func generateQRImage(from data: Data) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for crisp display
        let scale: CGFloat = 10
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func startCountdown() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                } else {
                    timer?.invalidate()
                    qrImage = nil
                    await server.invalidateCurrentQR()
                }
            }
        }
    }
}

#Preview {
    QRCodePairingView()
        .environment(PairingServer())
}
#endif
