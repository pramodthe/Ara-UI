//
//  arauiApp.swift
//  araui
import SwiftUI

@main
struct arauiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.sharedViewModel)
        }
        .windowStyle(.automatic)
        .commands {
            CommandMenu("AraUI") {
                Button("Capture Selection") {
                    appDelegate.sharedViewModel.captureSelection()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Start Voice Capture") {
                    appDelegate.sharedViewModel.handleGlobalHotkeyPress()
                }
                .keyboardShortcut("x", modifiers: [.option])

                Divider()

                Button("Toggle AraUI Visibility") {
                    AppVisibilityController.shared.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.sharedViewModel)
        }
    }
}
