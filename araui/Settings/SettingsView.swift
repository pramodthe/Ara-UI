//
//  SettingsView.swift
//  araui
//
//  Local app settings and active AI provider labels.
//

import SwiftUI

struct SettingsView: View {
    @State private var startCollapsed: Bool = false
    @State private var hideIconWhenExpanded: Bool = false

    var body: some View {
        Form {
            Section(header: Text("AI Providers")) {
                ProviderRow(label: "Chat", value: "Qwen Plus")
                ProviderRow(label: "Image", value: "Qwen Image 2.0 Pro")
                ProviderRow(label: "Voice output", value: "Qwen3 TTS Flash")
                ProviderRow(label: "Voice input", value: "Apple Speech Recognition")
            }

            Section(header: Text("AraUI")) {
                Toggle("Start collapsed", isOn: $startCollapsed)
                Toggle("Hide icon while window is open", isOn: $hideIconWhenExpanded)
                HStack {
                    Button("Apply Now") { applyUiSettings() }
                    Spacer()
                }
            }

            Section(footer: Text("Provider keys are loaded by the local backend from .env. DashScope keys are not stored in macOS Keychain.").font(.footnote)) { EmptyView() }
        }
        .padding(16)
        .onAppear {
            loadUiSettings()
        }
        .frame(width: 520)
    }

    private func loadUiSettings() {
        let defaults = UserDefaults.standard
        startCollapsed = (defaults.object(forKey: "StartCollapsed") as? Bool) ?? false
        hideIconWhenExpanded = defaults.bool(forKey: "HideIconWhenExpanded")
    }

    private func applyUiSettings() {
        let defaults = UserDefaults.standard
        defaults.set(startCollapsed, forKey: "StartCollapsed")
        defaults.set(hideIconWhenExpanded, forKey: "HideIconWhenExpanded")
        if startCollapsed {
            AppVisibilityController.shared.collapse()
        } else {
            AppVisibilityController.shared.expand()
        }
    }
}

private struct ProviderRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview { SettingsView() }
