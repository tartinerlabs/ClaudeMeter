//
//  PairingServer.swift
//  ClaudeMeter
//
//  WebSocket server for pairing with iOS devices over local network
//

import Foundation
import Network
import ClaudeMeterKit

// MARK: - Pairing Server

@MainActor
@Observable
final class PairingServer {
    // MARK: - Published State

    private(set) var isRunning = false
    private(set) var connectedDevices: [ConnectedDevice] = []
    private(set) var currentQRPayload: PairingQRPayload?
    private(set) var serverPort: UInt16?
    private(set) var error: PairingError?

    // MARK: - Internal

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var authenticatedConnections: Set<UUID> = []
    private let tokenStore = PairingTokenStore()
    private let listenerQueue = DispatchQueue(label: "com.tartinerlabs.ClaudeMeter.pairing")

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        do {
            // Create WebSocket parameters
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            // Add WebSocket protocol
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

            // Create listener on any available port
            listener = try NWListener(using: parameters, on: .any)

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: listenerQueue)

        } catch {
            self.error = .serverNotRunning
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil

        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        authenticatedConnections.removeAll()
        connectedDevices.removeAll()

        isRunning = false
        serverPort = nil
        currentQRPayload = nil
    }

    // MARK: - QR Code Generation

    func generatePairingQR() async -> PairingQRPayload? {
        guard isRunning, let port = serverPort else {
            error = .serverNotRunning
            return nil
        }

        let token = await tokenStore.generateToken()
        let localIP = getLocalIPAddress()
        let machineName = Host.current().localizedName ?? "Mac"

        let payload = PairingQRPayload(
            host: localIP,
            port: port,
            token: token.value,
            expiresAt: token.expiresAt,
            machineName: machineName
        )

        currentQRPayload = payload
        return payload
    }

    /// Invalidate the current QR code
    func invalidateCurrentQR() async {
        if let token = currentQRPayload?.token {
            await tokenStore.invalidate(token: token)
        }
        currentQRPayload = nil
    }

    // MARK: - Broadcasting

    func broadcast(snapshot: UsageSnapshot) {
        guard !authenticatedConnections.isEmpty else { return }

        let message = PairingMessage(type: .snapshot, payload: snapshot)
        guard let data = try? JSONEncoder().encode(message) else { return }

        for connectionID in authenticatedConnections {
            guard let connection = connections[connectionID] else { continue }
            sendData(data, to: connection)
        }
    }

    // MARK: - Connection Management

    func disconnectDevice(_ device: ConnectedDevice) {
        guard let connection = connections[device.id] else { return }

        // Send disconnect message
        let message = PairingMessage(type: .disconnect)
        if let data = try? JSONEncoder().encode(message) {
            sendData(data, to: connection)
        }

        connection.cancel()
        removeConnection(device.id)
    }

    func disconnectAll() {
        let message = PairingMessage(type: .disconnect)
        if let data = try? JSONEncoder().encode(message) {
            for connectionID in authenticatedConnections {
                if let connection = connections[connectionID] {
                    sendData(data, to: connection)
                }
            }
        }

        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        authenticatedConnections.removeAll()
        connectedDevices.removeAll()
    }

    // MARK: - Private - Listener State

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                isRunning = true
                serverPort = port
                error = nil
            }
        case .failed(let nwError):
            isRunning = false
            error = .connectionFailed(nwError.localizedDescription)
            stop()
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    // MARK: - Private - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let connectionID = UUID()
        connections[connectionID] = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(connectionID, state)
            }
        }

        connection.start(queue: listenerQueue)
        receiveMessages(from: connection, id: connectionID)
    }

    private func handleConnectionState(_ connectionID: UUID, _ state: NWConnection.State) {
        switch state {
        case .failed, .cancelled:
            removeConnection(connectionID)
        default:
            break
        }
    }

    private func removeConnection(_ connectionID: UUID) {
        connections.removeValue(forKey: connectionID)
        authenticatedConnections.remove(connectionID)
        connectedDevices.removeAll { $0.id == connectionID }
    }

    // MARK: - Private - Message Handling

    private func receiveMessages(from connection: NWConnection, id connectionID: UUID) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)

        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self, error == nil else { return }

            if let content = content {
                Task { @MainActor in
                    await self.handleMessage(content, from: connectionID)
                }
            }

            // Continue receiving
            if self.connections[connectionID] != nil {
                self.receiveMessages(from: connection, id: connectionID)
            }
        }
    }

    private func handleMessage(_ data: Data, from connectionID: UUID) async {
        guard let message = try? JSONDecoder().decode(PairingMessage.self, from: data),
              let connection = connections[connectionID] else {
            return
        }

        switch message.type {
        case .auth:
            await handleAuth(message, connection: connection, id: connectionID)
        case .ping:
            let pong = PairingMessage(type: .pong)
            if let data = try? JSONEncoder().encode(pong) {
                sendData(data, to: connection)
            }
        case .disconnect:
            connection.cancel()
            removeConnection(connectionID)
        default:
            break
        }
    }

    private func handleAuth(
        _ message: PairingMessage,
        connection: NWConnection,
        id connectionID: UUID
    ) async {
        guard let auth = message.decodePayload(as: PairingAuthPayload.self) else {
            sendAuthFailure(to: connection)
            return
        }

        let isValid = await tokenStore.validateAndConsume(token: auth.token)

        if isValid {
            // Auth success
            authenticatedConnections.insert(connectionID)
            connectedDevices.append(ConnectedDevice(
                id: connectionID,
                name: auth.deviceName
            ))

            let response = PairingMessage(type: .authSuccess)
            if let data = try? JSONEncoder().encode(response) {
                sendData(data, to: connection)
            }

            // Invalidate QR code after successful connection
            currentQRPayload = nil

        } else {
            sendAuthFailure(to: connection)

            // Close connection after failed auth
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                connection.cancel()
                await MainActor.run {
                    removeConnection(connectionID)
                }
            }
        }
    }

    private func sendAuthFailure(to connection: NWConnection) {
        let response = PairingMessage(type: .authFailure)
        if let data = try? JSONEncoder().encode(response) {
            sendData(data, to: connection)
        }
    }

    private func sendData(_ data: Data, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "message",
            metadata: [metadata]
        )
        connection.send(content: data, contentContext: context, completion: .idempotent)
    }

    // MARK: - Private - Network Utilities

    private func getLocalIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return address }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            // Check for IPv4 on WiFi interface (en0)
            guard addrFamily == UInt8(AF_INET),
                  let name = String(cString: interface.ifa_name, encoding: .utf8),
                  name == "en0" else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            address = String(cString: hostname)
            break
        }

        return address
    }
}
