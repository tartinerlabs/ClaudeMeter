//
//  ClaudeMeterApp.swift
//  ClaudeMeter
//
//  Created by Ru Chern Chong on 31/12/25.
//

import SwiftUI
#if os(macOS)
import SwiftData
#endif

@main
struct ClaudeMeterApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updaterController = UpdaterController()
    @AppStorage("selectedMainWindowTab") private var selectedTab: MainWindowTab = .dashboard
    @Environment(\.openWindow) private var openWindow
    let modelContainer: ModelContainer
    #endif

    @State private var viewModel: UsageViewModel

    init() {
        #if os(macOS)
        // Initialize SwiftData container
        let schema = Schema([TokenLogEntry.self, ImportedFile.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }

        // Use DependencyContainer for view model creation
        _viewModel = State(initialValue: DependencyContainer.createUsageViewModel(
            modelContext: modelContainer.mainContext
        ))
        #else
        _viewModel = State(initialValue: DependencyContainer.createUsageViewModel())
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // Main window (opened from menu bar)
        Window("ClaudeMeter", id: Constants.mainWindowID) {
            MainWindowView()
                .environment(viewModel)
                .environmentObject(updaterController)
                .task {
                    await viewModel.initializeIfNeeded()
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    selectedTab = .settings
                    openWindow(id: Constants.mainWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Menu bar popover
        MenuBarExtra {
            MenuBarView()
                .environment(viewModel)
                .environmentObject(updaterController)
        } label: {
            MenuBarIconView()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            MainTabView()
                .environment(viewModel)
        }
        #endif
    }
}
