import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var controller: LidController
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "laptopcomputer").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Duo").font(.headline)
                    Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            Text(controller.statusMessage).font(.caption).foregroundStyle(.secondary)
            if Bundle.main.bundleURL.path.hasPrefix("/Volumes/") {
                Text("Running from the installer. Quit, drag the app to Applications, then open that copy.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Toggle("Lid animation", isOn: $preferences.isEnabled)
            Toggle("Open at login", isOn: $launchesAtLogin)
                .onChange(of: launchesAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        launchesAtLogin = SMAppService.mainApp.status == .enabled
                        loginError = "Couldn't change login settings. Try again from Applications."
                    }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
            if !controller.isSensorAvailable {
                Text("This Mac doesn't have a compatible lid sensor.").font(.callout)
            } else if !controller.hasScreenPermission {
                Text("Allow Screen Recording to animate your desktop. Frames stay in memory and are never saved or sent.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Allow Screen Recording…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                    controller.refreshReadiness()
                }
            } else if !controller.hasBuiltInDisplay {
                Text("Open your MacBook to use the effect. External and mirrored displays are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Automatically follows your lid and settles when you pause.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !controller.hasScreenPermission {
                Button(controller.isCheckingPermission ? "Checking…" : "I've enabled it — check again") {
                    controller.checkPermission()
                }.disabled(controller.isCheckingPermission)
            }
            Button("Preview animation") { controller.runPreview() }
                .disabled(!controller.hasScreenPermission || !controller.hasBuiltInDisplay || !controller.isSensorAvailable || !preferences.isEnabled)
            Divider()
            HStack {
                Button("About") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Mac Duo Private",
                        .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0",
                        .credits: NSAttributedString(string: "Adapted from Mac Duo by Makito (sumimakito).\nOriginal renderer © 2026 Makito, Apache License 2.0.\nModified with automatic lid tracking and local-only processing.\n\nNo analytics, uploads, or saved recordings.")
                    ])
                }
                Spacer()
                Button("Quit", action: onQuit)
            }.controlSize(.small)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(18)
        .frame(width: 300)
        .onAppear {
            if !controller.hasScreenPermission { controller.checkPermission() }
            else { controller.refreshReadiness() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshReadiness()
        }
    }
}
