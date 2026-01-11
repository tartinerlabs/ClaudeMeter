//
//  QRCodeScannerService.swift
//  ClaudeMeter
//
//  AVFoundation-based QR code scanner for pairing
//

#if os(iOS)
import AVFoundation
import UIKit
import ClaudeMeterKit

@MainActor
@Observable
final class QRCodeScannerService: NSObject {
    // MARK: - State

    private(set) var isAuthorized = false
    private(set) var isScanning = false
    private(set) var error: ScannerError?

    // MARK: - Session

    let session = AVCaptureSession()
    private var metadataOutput: AVCaptureMetadataOutput?
    private var onPayloadDetected: ((PairingQRPayload) -> Void)?

    // MARK: - Lifecycle

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            return granted
        case .denied, .restricted:
            isAuthorized = false
            error = .permissionDenied
            return false
        @unknown default:
            return false
        }
    }

    func start(onPayload: @escaping (PairingQRPayload) -> Void) async {
        guard await requestPermission() else { return }

        self.onPayloadDetected = onPayload
        setupSession()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            Task { @MainActor in
                self?.isScanning = true
            }
        }
    }

    func stop() {
        session.stopRunning()
        isScanning = false
    }

    func resume() {
        guard isAuthorized, !session.isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            Task { @MainActor in
                self?.isScanning = true
            }
        }
    }

    // MARK: - Private

    private func setupSession() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Add video input
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            error = .cameraUnavailable
            return
        }
        session.addInput(input)

        // Add metadata output for QR detection
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            error = .cameraUnavailable
            return
        }
        session.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        metadataOutput = output
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension QRCodeScannerService: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let stringValue = object.stringValue else {
            return
        }

        // Try to parse as PairingQRPayload
        guard let payload = PairingQRPayload.fromQRString(stringValue) else {
            return
        }

        // Check if expired
        guard !payload.isExpired else {
            Task { @MainActor in
                self.error = .qrExpired
            }
            return
        }

        // Stop scanning and notify
        Task { @MainActor in
            session.stopRunning()
            isScanning = false

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            onPayloadDetected?(payload)
        }
    }
}

// MARK: - Scanner Error

enum ScannerError: LocalizedError {
    case permissionDenied
    case cameraUnavailable
    case qrExpired

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission is required to scan QR codes. Please enable it in Settings."
        case .cameraUnavailable:
            return "Camera is not available on this device."
        case .qrExpired:
            return "This QR code has expired. Please generate a new one on your Mac."
        }
    }
}
#endif
