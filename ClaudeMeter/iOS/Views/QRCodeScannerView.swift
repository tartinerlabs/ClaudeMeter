//
//  QRCodeScannerView.swift
//  ClaudeMeter
//
//  Camera view for scanning QR codes from macOS
//

#if os(iOS)
import SwiftUI
import AVFoundation
import ClaudeMeterKit

struct QRCodeScannerView: View {
    @Environment(PairingClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var scanner = QRCodeScannerService()
    @State private var scannedPayload: PairingQRPayload?
    @State private var showingConfirmation = false

    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreviewView(session: scanner.session)
                .ignoresSafeArea()

            // Overlay
            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Scanning frame
                scanningFrame

                Spacer()

                // Bottom instructions
                bottomInstructions
            }

            // Error overlay
            if let error = scanner.error {
                errorOverlay(error: error)
            }
        }
        .task {
            await scanner.start { payload in
                scannedPayload = payload
                showingConfirmation = true
            }
        }
        .onDisappear {
            scanner.stop()
        }
        .confirmationDialog(
            "Pair with \(scannedPayload?.machineName ?? "Mac")?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Connect") {
                if let payload = scannedPayload {
                    Task {
                        await client.connect(with: payload)
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                scannedPayload = nil
                scanner.resume()
            }
        } message: {
            Text("This will stream your Claude usage data from your Mac over local WiFi.")
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(.ultraThinMaterial))
            }

            Spacer()

            Text("Scan QR Code")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            // Spacer for balance
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .ignoresSafeArea()
        )
    }

    private var scanningFrame: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .frame(width: 260, height: 260)
                                .blendMode(.destinationOut)
                        )
                )

            // Frame border
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 260, height: 260)

            // Corner accents
            cornerAccents
        }
    }

    private var cornerAccents: some View {
        let size: CGFloat = 260
        let cornerLength: CGFloat = 40
        let cornerWidth: CGFloat = 4

        return ZStack {
            ForEach(0..<4) { index in
                CornerShape(cornerLength: cornerLength)
                    .stroke(Color.blue, lineWidth: cornerWidth)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
    }

    private var bottomInstructions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                Text("Point camera at QR code on your Mac")
            }
            .font(.headline)
            .foregroundStyle(.white)

            Text("Open ClaudeMeter Settings on your Mac and tap \"Generate QR Code\"")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func errorOverlay(error: ScannerError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(error.errorDescription ?? "An error occurred")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if case .permissionDenied = error {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Dismiss") {
                dismiss()
            }
            .foregroundStyle(.white)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .padding(32)
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

class CameraPreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            guard let session = session else { return }
            previewLayer.session = session
        }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.videoGravity = .resizeAspectFill
    }
}

// MARK: - Corner Shape

struct CornerShape: Shape {
    let cornerLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Top-left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

        return path
    }
}

#Preview {
    QRCodeScannerView()
        .environment(PairingClient())
}
#endif
