//
//  PairingClient.swift
//  ClaudeMeter
//
//  WebSocket client for connecting to macOS pairing server
//

#if os(iOS)
import Foundation
import Network
import UIKit
import ClaudeMeterKit

@MainActor
@Observable
final class PairingClient {
    // MARK: - Published State

    private(set) var state: PairingState = .disconnected
    private(set) var pairedMac: PairedMacInfo?
    private(set) var lastSnapshot: UsageSnapshot?
    private(set) var error: PairingError?

    // MARK: - Internal

    private var connection: NWConnection?
    private var currentPayload: PairingQRPayload?
    private var reconnectTask: Task<Void, Never>?
    private let connectionQueue = DispatchQueue(label: "com.tartinerlabs.ClaudeMeter.pairing.client")

    // MARK: - Persistence

    private let defaults = UserDefaults(suiteName: "group.com.tartinerlabs.ClaudeMeter")
    private let pairedMacKey = "pairedMacInfo"

    // MARK: - Callbacks

    var onSnapshotReceived: ((UsageSnapshot) -> Void)?

    // MARK: - Init

    init() {
        loadPairedMac()
    }

    // MARK: - Connection

    func connect(with payload: PairingQRPayload) async {
        // Check if QR is expired
        guard !payload.isExpired else {
            error = .tokenExpired
            return
        }

        currentPayload = payload
        state = .connecting
        error = nil

        // Create WebSocket parameters
        let parameters = NWParameters.tcp

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        // Create connection endpoint
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(payload.host),
            port: NWEndpoint.Port(integerLiteral: payload.port)
        )

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                self?.handleConnectionState(newState)
            }
        }

        connection?.start(queue: connectionQueue)
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil

        if let connection = connection {
            // Send disconnect message
            let message = PairingMessage(type: .disconnect)
            if let data = try? JSONEncoder().encode(message) {
                sendData(data)
            }

            connection.cancel()
        }

        connection = nil
        state = .disconnected
        currentPayload = nil
    }

    func unpair() {
        disconnect()
        pairedMac = nil
        lastSnapshot = nil
        defaults?.removeObject(forKey: pairedMacKey)
    }

    // MARK: - Private - Connection State

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            sendAuth()
        case .failed(let nwError):
            error = .connectionFailed(nwError.localizedDescription)
            state = .disconnected
            scheduleReconnect()
        case .cancelled:
            state = .disconnected
        case .waiting(let nwError):
            // Network unavailable, waiting for path
            if state != .disconnected {
                error = .networkUnavailable
            }
        default:
            break
        }
    }

    // MARK: - Private - Authentication

    private func sendAuth() {
        guard let payload = currentPayload else { return }

        state = .authenticating

        let auth = PairingAuthPayload(
            token: payload.token,
            deviceName: UIDevice.current.name
        )
        let message = PairingMessage(type: .auth, payload: auth)

        guard let data = try? JSONEncoder().encode(message) else { return }

        sendData(data)
        receiveMessages()
    }

    // MARK: - Private - Message Handling

    private func receiveMessages() {
        connection?.receiveMessage { [weak self] content, context, isComplete, nwError in
            guard let self = self, nwError == nil else { return }

            if let content = content {
                Task { @MainActor in
                    self.handleMessage(content)
                }
            }

            // Continue receiving if still connected
            if self.connection != nil {
                self.receiveMessages()
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(PairingMessage.self, from: data) else {
            return
        }

        switch message.type {
        case .authSuccess:
            state = .connected
            error = nil
            savePairedMac()

        case .authFailure:
            error = .authenticationFailed
            state = .disconnected
            disconnect()

        case .snapshot:
            if let snapshot = message.decodePayload(as: UsageSnapshot.self) {
                lastSnapshot = snapshot
                onSnapshotReceived?(snapshot)

                // Update widgets
                Task {
                    await WidgetDataManager.shared.save(snapshot)
                }
            }

        case .ping:
            let pong = PairingMessage(type: .pong)
            if let data = try? JSONEncoder().encode(pong) {
                sendData(data)
            }

        case .disconnect:
            state = .disconnected
            connection?.cancel()
            connection = nil

        default:
            break
        }
    }

    private func sendData(_ data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "message",
            metadata: [metadata]
        )
        connection?.send(content: data, contentContext: context, completion: .idempotent)
    }

    // MARK: - Private - Reconnection

    private func scheduleReconnect() {
        // Only reconnect if we have a paired Mac
        guard pairedMac != nil, let payload = currentPayload else { return }

        reconnectTask?.cancel()
        reconnectTask = Task {
            // Wait before reconnecting
            try? await Task.sleep(for: .seconds(5))

            guard !Task.isCancelled else { return }

            // Only reconnect if still disconnected
            if state == .disconnected {
                await connect(with: payload)
            }
        }
    }

    // MARK: - Private - Persistence

    private func savePairedMac() {
        guard let payload = currentPayload else { return }

        pairedMac = PairedMacInfo(
            name: payload.machineName,
            lastConnected: Date()
        )

        if let data = try? JSONEncoder().encode(pairedMac) {
            defaults?.set(data, forKey: pairedMacKey)
        }
    }

    private func loadPairedMac() {
        guard let data = defaults?.data(forKey: pairedMacKey),
              let info = try? JSONDecoder().decode(PairedMacInfo.self, from: data) else {
            return
        }
        pairedMac = info
    }
}
#endif
