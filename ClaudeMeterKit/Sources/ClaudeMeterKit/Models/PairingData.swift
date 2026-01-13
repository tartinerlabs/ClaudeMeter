//
//  PairingData.swift
//  ClaudeMeterKit
//
//  Shared models for QR code pairing between macOS and iOS
//

import Foundation

// MARK: - Pairing State

public enum PairingState: String, Sendable, Codable {
    case disconnected
    case connecting
    case authenticating
    case connected

    public var displayName: String {
        switch self {
        case .disconnected: "Not Connected"
        case .connecting: "Connecting..."
        case .authenticating: "Authenticating..."
        case .connected: "Connected"
        }
    }

    public var isActive: Bool {
        self == .connected
    }
}

// MARK: - Pairing Message Type

public enum PairingMessageType: String, Sendable, Codable {
    case auth           // Client sends token for authentication
    case authSuccess    // Server acknowledges successful auth
    case authFailure    // Invalid or expired token
    case snapshot       // Server pushes UsageSnapshot
    case ping           // Keepalive request
    case pong           // Keepalive response
    case disconnect     // Graceful close
}

// MARK: - Pairing Message

public struct PairingMessage: Sendable, Codable {
    public let type: PairingMessageType
    public let payload: Data?
    public let timestamp: Date

    public init(type: PairingMessageType, payload: Data? = nil) {
        self.type = type
        self.payload = payload
        self.timestamp = Date()
    }

    public init<T: Encodable>(type: PairingMessageType, payload: T) {
        self.type = type
        self.payload = try? JSONEncoder().encode(payload)
        self.timestamp = Date()
    }

    public func decodePayload<T: Decodable>(as type: T.Type) -> T? {
        guard let data = payload else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - QR Code Payload

public struct PairingQRPayload: Sendable, Codable {
    public let host: String          // Local IP address
    public let port: UInt16          // Server port
    public let token: String         // One-time auth token (UUID)
    public let expiresAt: Date       // Token expiration (60 seconds)
    public let machineName: String   // Display name for UI

    public init(
        host: String,
        port: UInt16,
        token: String,
        expiresAt: Date,
        machineName: String
    ) {
        self.host = host
        self.port = port
        self.token = token
        self.expiresAt = expiresAt
        self.machineName = machineName
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }

    public var timeUntilExpiry: TimeInterval {
        expiresAt.timeIntervalSinceNow
    }

    /// Encode to JSON Data for QR code generation
    public func toQRData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Decode from scanned QR code string
    public static func fromQRString(_ string: String) -> PairingQRPayload? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PairingQRPayload.self, from: data)
    }
}

// MARK: - Auth Payload

public struct PairingAuthPayload: Sendable, Codable {
    public let token: String
    public let deviceName: String

    public init(token: String, deviceName: String) {
        self.token = token
        self.deviceName = deviceName
    }
}

// MARK: - Connected Device Info

public struct ConnectedDevice: Sendable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let connectedAt: Date

    public init(id: UUID = UUID(), name: String, connectedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.connectedAt = connectedAt
    }
}

// MARK: - Paired Mac Info (persisted on iOS)

public struct PairedMacInfo: Sendable, Codable {
    public let name: String
    public let lastConnected: Date

    public init(name: String, lastConnected: Date = Date()) {
        self.name = name
        self.lastConnected = lastConnected
    }
}

// MARK: - Pairing Error

public enum PairingError: LocalizedError, Sendable {
    case serverNotRunning
    case connectionFailed(String)
    case authenticationFailed
    case tokenExpired
    case invalidQRCode
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            return "Pairing server is not running on Mac."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .authenticationFailed:
            return "Authentication failed. Please scan a new QR code."
        case .tokenExpired:
            return "QR code has expired. Please generate a new one."
        case .invalidQRCode:
            return "Invalid QR code. Please scan the QR code from ClaudeMeter on your Mac."
        case .networkUnavailable:
            return "Network unavailable. Make sure both devices are on the same WiFi network."
        }
    }
}
