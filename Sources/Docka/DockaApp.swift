import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        TrayController.shared.start()
    }
}

@main
struct DockaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DockaStore.shared

    var body: some Scene {
        WindowGroup("Docka") {
            Group {
                if store.onboarded {
                    SettingsWindowView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(store)
            .frame(minWidth: 780, minHeight: 600)
            .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent().environmentObject(store)
        } label: {
            Image(systemName: "tray.full.fill")
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Button("Abrir Configurações") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
        }
        Divider()
        Toggle("Sons", isOn: Binding(get: { store.soundsEnabled },
                                     set: { store.soundsEnabled = $0 }))
        Toggle("Pressure Zone", isOn: Binding(get: { store.pressureZone },
                                              set: { store.pressureZone = $0 }))
        Divider()
        Button("Encerrar o Docka") { NSApp.terminate(nil) }
    }
}
