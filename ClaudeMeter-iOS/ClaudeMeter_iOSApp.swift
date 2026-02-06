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
        // Use DependencyContainer for view model creation
        _viewModel = State(initialValue: DependencyContainer.createUsageViewModel())
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
