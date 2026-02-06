//
//  PairingTokenStore.swift
//  ClaudeMeter
//
//  Manages one-time tokens for QR code pairing authentication
//

import Foundation

// MARK: - Token

struct PairingToken: Sendable {
    let value: String
    let expiresAt: Date
    var isConsumed: Bool = false

    var isValid: Bool {
        !isConsumed && Date() < expiresAt
    }

    var timeRemaining: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }
}

// MARK: - Token Store

actor PairingTokenStore {
    private var tokens: [String: PairingToken] = [:]
    private let tokenLifetime: TimeInterval

    init(tokenLifetime: TimeInterval = 60) {
        self.tokenLifetime = tokenLifetime
    }

    /// Generate a new one-time token
    func generateToken() -> PairingToken {
        // Clean up expired tokens first
        cleanupExpiredTokens()

        let token = PairingToken(
            value: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(tokenLifetime)
        )
        tokens[token.value] = token

        // Schedule automatic cleanup after expiration
        Task {
            try? await Task.sleep(for: .seconds(tokenLifetime + 1))
            tokens.removeValue(forKey: token.value)
        }

        return token
    }

    /// Validate and consume a token (single-use)
    /// - Returns: `true` if valid and successfully consumed, `false` otherwise
    func validateAndConsume(token: String) -> Bool {
        guard var storedToken = tokens[token], storedToken.isValid else {
            return false
        }

        // Mark as consumed (single-use)
        storedToken.isConsumed = true
        tokens[token] = storedToken

        return true
    }

    /// Check if a token is valid without consuming it
    func isValid(token: String) -> Bool {
        guard let storedToken = tokens[token] else { return false }
        return storedToken.isValid
    }

    /// Get remaining time for a token
    func timeRemaining(for token: String) -> TimeInterval? {
        tokens[token]?.timeRemaining
    }

    /// Invalidate all tokens
    func invalidateAll() {
        tokens.removeAll()
    }

    /// Invalidate a specific token
    func invalidate(token: String) {
        tokens.removeValue(forKey: token)
    }

    // MARK: - Private

    private func cleanupExpiredTokens() {
        tokens = tokens.filter { $0.value.isValid }
    }
}
