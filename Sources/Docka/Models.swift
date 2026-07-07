import SwiftUI
import Combine

// Paleta do app (tema escuro premium, accent azul-turquesa — mesma cor da logo)
enum Theme {
    static let accent = Color(red: 0.13, green: 0.83, blue: 0.76)
    static let bgTop = Color(red: 0.05, green: 0.12, blue: 0.13)
    static let bgBottom = Color(red: 0.02, green: 0.06, blue: 0.07)
    static let card = Color(red: 0.08, green: 0.16, blue: 0.17)
}

// MARK: - App fixado na bandeja

struct PinnedApp: Identifiable, Hashable {
    var id: String { path }
    let path: String

    var name: String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }
    var icon: NSImage {
        // pede a representação grande: sem isso o macOS entrega 32px e o ícone
        // fica borrado/lavado quando ampliado
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 256, height: 256)
        return img
    }

    func launch() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: .init(), completionHandler: nil)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func open(files: [URL]) {
        NSWorkspace.shared.open(files, withApplicationAt: URL(fileURLWithPath: path),
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
    @Published var pinnedOpen = false      // aberta pelo atalho global: não auto-esconde

    // modo demo (--demo): bandeja fixa + hover simulado varrendo os ícones
    @Published var demoHoverX: CGFloat? = nil
    var demoMode = false

    func move(_ path: String, before target: String) {
        guard let from = apps.firstIndex(where: { $0.path == path }),
              let to = apps.firstIndex(where: { $0.path == target }),
              from != to else { return }
        let app = apps.remove(at: from)
        // após remover, o alvo desloca 1 posição p/ trás quando vinha depois do arrastado
        apps.insert(app, at: from < to ? to - 1 : to)
    }

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
