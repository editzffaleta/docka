import SwiftUI
import Combine

// Paleta do app (tema escuro premium, accent azul-gelo)
enum Theme {
    static let accent = Color(red: 0.45, green: 0.72, blue: 0.98)
    static let bgTop = Color(red: 0.07, green: 0.10, blue: 0.16)
    static let bgBottom = Color(red: 0.03, green: 0.045, blue: 0.08)
    static let card = Color(red: 0.10, green: 0.14, blue: 0.21)
}

// MARK: - App fixado na bandeja

struct PinnedApp: Identifiable, Hashable {
    var id: String { path }
    let path: String

    var name: String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    func launch() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: .init(), completionHandler: nil)
    }
}

// MARK: - Estado global

final class DockaStore: ObservableObject {
    static let shared = DockaStore()

    // apps escolhidos (persistidos por caminho)
    @Published var apps: [PinnedApp] {
        didSet { UserDefaults.standard.set(apps.map(\.path), forKey: "docka.apps") }
    }

    // bandeja
    @Published var trayVisible = false

    // ajustes
    @AppStorage("docka.onboarded") var onboarded = false
    @AppStorage("docka.sounds") var soundsEnabled = true
    @AppStorage("docka.pressureZone") var pressureZone = false
    @AppStorage("docka.followDock") var followDock = true
    @AppStorage("docka.offsetX") var offsetX = 24.0        // distância da borda direita
    @AppStorage("docka.iconSize") var iconSize = 48.0

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: "docka.apps") ?? []
        apps = saved.filter { FileManager.default.fileExists(atPath: $0) }
            .map { PinnedApp(path: $0) }
    }

    func toggle(_ path: String) {
        if let i = apps.firstIndex(where: { $0.path == path }) {
            apps.remove(at: i)
        } else {
            apps.append(PinnedApp(path: path))
        }
    }

    func isSelected(_ path: String) -> Bool {
        apps.contains { $0.path == path }
    }

    // apps instalados em /Applications (para o seletor)
    static func installedApps() -> [PinnedApp] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications"]
        var found: [PinnedApp] = []
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".app") {
                found.append(PinnedApp(path: dir + "/" + n))
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func playSound(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }
}
