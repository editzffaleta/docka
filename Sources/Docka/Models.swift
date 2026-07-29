import SwiftUI
import Combine
import ServiceManagement
import DockaCore

// Identidade do app lida do bundle, para não repetir a versão no código
enum AppInfo {
    /// CFBundleShortVersionString do .app. Fora de um bundle (binário do SPM) é "dev".
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// `false` quando o Docka roda fora de um .app assinado — aí o macOS não tem
    /// o que registrar nos itens de início de sessão.
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }
}

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
        self.name = AppNaming.trimmingAppSuffix(FileManager.default.displayName(atPath: path))
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
        static let maxScale = "docka.maxScale"
        static let maxRange = "docka.maxRange"
        /// Chave antiga: guardava o "boost" 0…1 (0,75 = 1,75×).
        static let magnificationLegacy = "docka.magnification"
        static let showIndicators = "docka.showIndicators"
        static let bounceOnLaunch = "docka.bounceOnLaunch"
        static let position = "docka.position"
        static let atalhoTecla = "docka.hotkey.keyCode"
        static let atalhoMods = "docka.hotkey.modifiers"
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
    /// Ampliação máxima do ícone sob o cursor (1 = desativada).
    @Published var maxScale: Double { didSet { defaults.set(maxScale, forKey: Key.maxScale) } }
    /// Até onde o cursor ainda mexe com um ícone, em pontos.
    @Published var maxRange: Double { didSet { defaults.set(maxRange, forKey: Key.maxRange) } }
    @Published var showIndicators: Bool { didSet { defaults.set(showIndicators, forKey: Key.showIndicators) } }
    @Published var bounceOnLaunch: Bool { didSet { defaults.set(bounceOnLaunch, forKey: Key.bounceOnLaunch) } }
    @Published var position: String { didSet { defaults.set(position, forKey: Key.position) } }

    // MARK: - Atalho global

    @Published private(set) var shortcut: Shortcut = .padrao
    /// Mensagem quando o macOS recusa a combinação escolhida.
    @Published private(set) var shortcutError: String?

    /// Registra o atalho no sistema e persiste se der certo.
    /// Um atalho recusado não é gravado — senão o app subiria sem atalho nenhum
    /// na próxima vez, sem explicar por quê.
    func setShortcut(_ novo: Shortcut) {
        if let falha = HotKeyManager.shared.apply(novo) {
            shortcutError = falha.mensagem
            HotKeyManager.shared.apply(shortcut)   // volta para o que funcionava
            return
        }
        shortcut = novo
        shortcutError = nil
        defaults.set(Int(novo.keyCode), forKey: Key.atalhoTecla)
        defaults.set(Int(novo.modifiers.rawValue), forKey: Key.atalhoMods)
    }

    func resetShortcut() {
        setShortcut(.padrao)
    }

    /// Chamado uma vez na inicialização do app.
    func activateShortcut() {
        if let falha = HotKeyManager.shared.apply(shortcut) {
            shortcutError = falha.mensagem
        }
    }

    // MARK: - Abrir no login
    //
    // Este ajuste não mora no UserDefaults: quem guarda o estado é o próprio macOS,
    // em Configurações do Sistema › Geral › Itens de Início de Sessão, e o usuário
    // pode desligar por lá sem passar pelo app. Por isso sempre lemos do sistema.

    @Published private(set) var launchAtLogin = false
    /// Preenchido quando o registro falha ou quando o usuário desativou o Docka
    /// nas Configurações do Sistema.
    @Published private(set) var launchAtLoginNote: String?

    func refreshLaunchAtLogin() {
        guard AppInfo.isBundled else {
            launchAtLogin = false
            launchAtLoginNote = "Disponível apenas no Docka instalado em Aplicativos."
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
            launchAtLoginNote = nil
        case .requiresApproval:
            launchAtLogin = false
            launchAtLoginNote = "O macOS está bloqueando: libere o Docka em Itens de Início de Sessão."
        default:
            launchAtLogin = false
            launchAtLoginNote = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard AppInfo.isBundled else { refreshLaunchAtLogin(); return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginNote = nil
        } catch {
            launchAtLoginNote = "Não foi possível alterar: \(error.localizedDescription)"
        }
        // o estado verdadeiro é o do sistema, não o que pedimos
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// A versão anterior guardava a ampliação como "boost" 0…1 (0,75 = 1,75×).
    /// Roda ANTES do `register(defaults:)` — depois dele todo `object(forKey:)`
    /// devolve o padrão registrado e não dá mais para saber o que era do usuário.
    private static func migrarAmpliacao(_ defaults: UserDefaults) {
        guard defaults.object(forKey: Key.maxScale) == nil,
              let boost = defaults.object(forKey: Key.magnificationLegacy) as? Double
        else { return }
        defaults.set(boost <= 0 ? 1.0 : 1.0 + boost, forKey: Key.maxScale)
    }

    private init() {
        Self.migrarAmpliacao(defaults)

        // as chaves são as mesmas de antes: quem já usava o app mantém seus ajustes
        defaults.register(defaults: [
            Key.onboarded: false,
            Key.sounds: true,
            Key.pressureZone: false,
            Key.followDock: true,
            Key.offsetX: 24.0,          // distância da borda
            Key.iconSize: 48.0,
            Key.maxScale: Double(Magnification.defaultMaxScale),   // 1 = desativada
            Key.maxRange: Double(Magnification.defaultMaxRange),
            Key.showIndicators: true,
            Key.bounceOnLaunch: true,
            Key.position: "right",      // left | center | right
            Key.atalhoTecla: Int(Shortcut.padrao.keyCode),
            Key.atalhoMods: Int(Shortcut.padrao.modifiers.rawValue)
        ])

        onboarded = defaults.bool(forKey: Key.onboarded)
        soundsEnabled = defaults.bool(forKey: Key.sounds)
        pressureZone = defaults.bool(forKey: Key.pressureZone)
        followDock = defaults.bool(forKey: Key.followDock)
        offsetX = defaults.double(forKey: Key.offsetX)
        iconSize = defaults.double(forKey: Key.iconSize)
        maxScale = defaults.double(forKey: Key.maxScale)
        maxRange = defaults.double(forKey: Key.maxRange)
        showIndicators = defaults.bool(forKey: Key.showIndicators)
        bounceOnLaunch = defaults.bool(forKey: Key.bounceOnLaunch)
        position = defaults.string(forKey: Key.position) ?? "right"

        apps = (defaults.stringArray(forKey: Key.apps) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { PinnedApp(path: $0) }

        let gravado = Shortcut(keyCode: UInt16(defaults.integer(forKey: Key.atalhoTecla)),
                               modifiers: .init(rawValue: UInt32(defaults.integer(forKey: Key.atalhoMods))))
        // um valor corrompido no plist não pode deixar o app sem atalho
        shortcut = gravado.isValid ? gravado : .padrao

        refreshLaunchAtLogin()
    }

    func move(_ path: String, before target: String) {
        guard let from = apps.firstIndex(where: { $0.path == path }),
              let to = apps.firstIndex(where: { $0.path == target }) else { return }
        apps = Reorder.move(apps, from: from, to: to)
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

        let list = AppScanner.scan(roots: AppScanner.defaultRoots)
            .map { PinnedApp(path: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        installedCache = list
        return list
    }

    func playSound(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }
}
