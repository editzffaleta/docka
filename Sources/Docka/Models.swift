import SwiftUI
import Combine

// Paleta do app (tema escuro premium, accent azul-turquesa — mesma cor da logo)
enum Theme {
    static let accent = Color(red: 0.13, green: 0.83, blue: 0.76)
    static let bgTop = Color(red: 0.05, green: 0.12, blue: 0.13)
    static let bgBottom = Color(red: 0.02, green: 0.06, blue: 0.07)
    static let card = Color(red: 0.08, green: 0.16, blue: 0.17)
}

// MARK: - Cache de ícones

// NSWorkspace.icon(forFile:) toca o disco e devolve uma imagem nova a cada chamada.
// Como a magnificação redesenha cada ícone dezenas de vezes por segundo, sem cache
// esse custo cai direto no frame da bandeja.
private final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(forPath path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        // pede a representação grande: sem isso o macOS entrega 32px e o ícone
        // fica borrado/lavado quando ampliado
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 256, height: 256)
        cache.setObject(img, forKey: path as NSString)
        return img
    }
}

// MARK: - App fixado na bandeja

struct PinnedApp: Identifiable, Hashable {
    var id: String { path }
    let path: String
    /// Nome de exibição do Finder, resolvido uma vez na criação (localizado).
    let name: String

    init(path: String) {
        self.path = path
        // displayName respeita o nome localizado do app e a preferência de mostrar
        // extensões — daí o corte do sufixo só quando ele realmente vem no fim.
        let display = FileManager.default.displayName(atPath: path)
        self.name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }

    var icon: NSImage { IconCache.shared.icon(forPath: path) }

    // identidade é o caminho: `name` é derivado dele
    static func == (lhs: PinnedApp, rhs: PinnedApp) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }

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

    private enum Key {
        static let apps = "docka.apps"
        static let onboarded = "docka.onboarded"
        static let sounds = "docka.sounds"
        static let pressureZone = "docka.pressureZone"
        static let followDock = "docka.followDock"
        static let offsetX = "docka.offsetX"
        static let iconSize = "docka.iconSize"
        static let magnification = "docka.magnification"
        static let showIndicators = "docka.showIndicators"
        static let bounceOnLaunch = "docka.bounceOnLaunch"
        static let position = "docka.position"
    }

    private let defaults = UserDefaults.standard

    // apps escolhidos (persistidos por caminho)
    @Published var apps: [PinnedApp] {
        didSet { defaults.set(apps.map(\.path), forKey: Key.apps) }
    }

    // bandeja
    @Published var trayVisible = false
    @Published var pinnedOpen = false      // aberta pelo atalho global: não auto-esconde

    // modo demo (--demo): bandeja fixa + hover simulado varrendo os ícones
    @Published var demoHoverX: CGFloat? = nil
    var demoMode = false

    // Ajustes: @Published + UserDefaults, e não @AppStorage. Dentro de uma
    // ObservableObject o @AppStorage grava o valor mas não emite objectWillChange —
    // a bandeja e os rótulos da calibração ficavam sem reagir à mudança.
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: Key.onboarded) } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: Key.sounds) } }
    @Published var pressureZone: Bool { didSet { defaults.set(pressureZone, forKey: Key.pressureZone) } }
    @Published var followDock: Bool { didSet { defaults.set(followDock, forKey: Key.followDock) } }
    @Published var offsetX: Double { didSet { defaults.set(offsetX, forKey: Key.offsetX) } }
    @Published var iconSize: Double { didSet { defaults.set(iconSize, forKey: Key.iconSize) } }
    @Published var magnification: Double { didSet { defaults.set(magnification, forKey: Key.magnification) } }
    @Published var showIndicators: Bool { didSet { defaults.set(showIndicators, forKey: Key.showIndicators) } }
    @Published var bounceOnLaunch: Bool { didSet { defaults.set(bounceOnLaunch, forKey: Key.bounceOnLaunch) } }
    @Published var position: String { didSet { defaults.set(position, forKey: Key.position) } }

    private init() {
        // as chaves são as mesmas de antes: quem já usava o app mantém seus ajustes
        defaults.register(defaults: [
            Key.onboarded: false,
            Key.sounds: true,
            Key.pressureZone: false,
            Key.followDock: true,
            Key.offsetX: 24.0,          // distância da borda
            Key.iconSize: 48.0,
            Key.magnification: 0.75,    // 0 = ampliação desativada
            Key.showIndicators: true,
            Key.bounceOnLaunch: true,
            Key.position: "right"       // left | center | right
        ])

        onboarded = defaults.bool(forKey: Key.onboarded)
        soundsEnabled = defaults.bool(forKey: Key.sounds)
        pressureZone = defaults.bool(forKey: Key.pressureZone)
        followDock = defaults.bool(forKey: Key.followDock)
        offsetX = defaults.double(forKey: Key.offsetX)
        iconSize = defaults.double(forKey: Key.iconSize)
        magnification = defaults.double(forKey: Key.magnification)
        showIndicators = defaults.bool(forKey: Key.showIndicators)
        bounceOnLaunch = defaults.bool(forKey: Key.bounceOnLaunch)
        position = defaults.string(forKey: Key.position) ?? "right"

        apps = (defaults.stringArray(forKey: Key.apps) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { PinnedApp(path: $0) }
    }

    func move(_ path: String, before target: String) {
        guard let from = apps.firstIndex(where: { $0.path == path }),
              let to = apps.firstIndex(where: { $0.path == target }),
              from != to else { return }
        let app = apps.remove(at: from)
        // após remover, o alvo desloca 1 posição p/ trás quando vinha depois do arrastado
        apps.insert(app, at: from < to ? to - 1 : to)
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

    // MARK: - Apps instalados (para o seletor)

    private static var installedCache: [PinnedApp]?

    /// Varre as pastas de aplicativos do sistema e do usuário.
    /// O resultado é memorizado: o seletor é recriado a cada redraw e chamava
    /// esta varredura a cada tecla digitada na busca.
    static func installedApps(refresh: Bool = false) -> [PinnedApp] {
        if !refresh, let cached = installedCache { return cached }

        let roots = ["/Applications",
                     "/System/Applications",
                     (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        var found: [String: PinnedApp] = [:]      // chaveado pelo caminho: evita duplicatas
        for root in roots {
            collectApps(in: URL(fileURLWithPath: root), depth: 2, into: &found)
        }

        let list = found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        installedCache = list
        return list
    }

    // depth 2 = a pasta raiz + um nível de subpasta (Utilities, Adobe, Microsoft…)
    private static func collectApps(in dir: URL, depth: Int, into found: inout [String: PinnedApp]) {
        guard depth > 0,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return }

        for url in entries {
            if url.pathExtension == "app" {
                found[url.path] = PinnedApp(path: url.path)
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collectApps(in: url, depth: depth - 1, into: &found)
            }
        }
    }

    func playSound(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }
}
