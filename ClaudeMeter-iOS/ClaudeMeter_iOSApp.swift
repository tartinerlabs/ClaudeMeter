//
//  ClaudeMeter_iOSApp.swift
//  ClaudeMeter-iOS
//

import SwiftUI

@main
struct ClaudeMeter_iOSApp: App {
    @State private var viewModel: UsageViewModel
    @State private var pairingClient = PairingClient()

    init() {
        let credentialService = iOSCredentialService()
        _viewModel = State(initialValue: UsageViewModel(
            credentialProvider: credentialService
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(viewModel)
                .environment(pairingClient)
                .onAppear {
                    // Set up callback to update viewModel when snapshot received
                    pairingClient.onSnapshotReceived = { snapshot in
                        Task { @MainActor in
                            viewModel.updateFromPairedSnapshot(snapshot)
                        }
                    }
                }
        }
    }
}
