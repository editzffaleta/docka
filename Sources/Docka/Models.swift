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

    /// displayName toca o disco. Com as bandejas guardando CAMINHOS e mapeando
    /// para PinnedApp a cada leitura, sem cache isso viraria I/O por quadro.
    private static var nomes: [String: String] = [:]

    init(path: String) {
        self.path = path
        if let cache = Self.nomes[path] {
            self.name = cache
        } else {
            // displayName respeita o nome localizado do app e a preferência de
            // mostrar extensões — daí o corte do sufixo só no fim.
            let n = AppNaming.trimmingAppSuffix(FileManager.default.displayName(atPath: path))
            Self.nomes[path] = n
            self.name = n
        }
    }

    var icon: NSImage { IconCache.shared.icon(forPath: path) }

    // identidade é o caminho: `name` é derivado dele
    static func == (lhs: PinnedApp, rhs: PinnedApp) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }

    func launch() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: .init(), completionHandler: nil)
    }

    /// As instâncias abertas deste app, se houver.
    var emExecucao: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path }
    }

    /// Pede o encerramento, como o "Encerrar" do Dock: é um pedido educado, não
    /// um `kill`. Um app com trabalho não salvo mostra o próprio diálogo e pode
    /// recusar — e é assim que tem de ser.
    func encerrar() {
        emExecucao.forEach { $0.terminate() }
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
        static let apps = "docka.apps"          // legado: bandeja única
        static let docks = "docka.docks"
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
        static let brilho = "docka.brightnessControl"
        static let brilhoNivel = "docka.brightnessLevel"
        static let brilhoBorda = "docka.brightnessEdge"
        static let brilhoAlinhamento = "docka.brightnessAlignment"
        static let volume = "docka.volumeControl"
        static let volumeNivel = "docka.volumeLevel"
        static let volumeBorda = "docka.volumeEdge"
        static let volumeAlinhamento = "docka.volumeAlignment"
        static let glassTint = "docka.glassTint"
        static let appearance = "docka.appearance"
        static let atalhoTecla = "docka.hotkey.keyCode"
        static let atalhoMods = "docka.hotkey.modifiers"
        static let atalhos = "docka.hotkeys"
    }

    private let defaults = UserDefaults.standard

    /// As bandejas. Cada uma tem seus apps e sua borda.
    @Published var docks: [DockConfig] {
        didSet {
            guard let data = try? JSONEncoder().encode(docks) else { return }
            defaults.set(data, forKey: Key.docks)
        }
    }

    /// Apps de uma bandeja, já resolvidos (nome em cache, arquivo existente).
    func apps(of dock: DockConfig) -> [PinnedApp] {
        dock.apps.filter { FileManager.default.fileExists(atPath: $0) }
                 .map { PinnedApp(path: $0) }
    }

    func dock(_ id: UUID) -> DockConfig? { docks.first { $0.id == id } }

    /// A bandeja principal — a que o onboarding configura e a que sempre existe.
    var principal: DockConfig { docks.first ?? DockConfig() }

    private func atualizar(_ id: UUID, _ mudanca: (inout DockConfig) -> Void) {
        guard let i = docks.firstIndex(where: { $0.id == id }) else { return }
        mudanca(&docks[i])
    }

    func adicionarDock() {
        docks.append(DockConfig(edge: DockConfig.proximaBordaLivre(docks)))
    }

    func removerDock(_ id: UUID) {
        guard docks.count > 1 else { return }   // sempre sobra uma
        docks.removeAll { $0.id == id }
    }

    func definirBorda(_ edge: TrayEdge, em id: UUID) { atualizar(id) { $0.edge = edge } }
    func definirAlinhamento(_ a: TrayAlignment, em id: UUID) { atualizar(id) { $0.alignment = a } }
    func definirOffset(_ v: Double, em id: UUID) { atualizar(id) { $0.offset = v } }

    func alternarApp(_ path: String, em id: UUID) {
        atualizar(id) { d in
            if let i = d.apps.firstIndex(of: path) { d.apps.remove(at: i) }
            else { d.apps.append(path) }
        }
    }

    func estaNaBandeja(_ path: String, _ id: UUID) -> Bool {
        dock(id)?.apps.contains(path) ?? false
    }

    func moverApp(_ path: String, antesDe alvo: String, em id: UUID) {
        atualizar(id) { d in
            guard let from = d.apps.firstIndex(of: path),
                  let to = d.apps.firstIndex(of: alvo) else { return }
            d.apps = Reorder.move(d.apps, from: from, to: to)
        }
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

    /// Borda onde o controle de brilho mora — só laterais.
    @Published var brightnessEdge: String { didSet { defaults.set(brightnessEdge, forKey: Key.brilhoBorda) } }
    @Published var brightnessAlignment: String { didSet { defaults.set(brightnessAlignment, forKey: Key.brilhoAlinhamento) } }

    /// Mostra o controle de brilho.
    @Published var brightnessControl: Bool { didSet { defaults.set(brightnessControl, forKey: Key.brilho) } }
    /// Brilho da tela, lido do sistema.
    @Published var brightnessLevel: Double { didSet { defaults.set(brightnessLevel, forKey: Key.brilhoNivel) } }

    /// Borda onde o controle de volume mora — só laterais, como o de brilho.
    @Published var volumeEdge: String { didSet { defaults.set(volumeEdge, forKey: Key.volumeBorda) } }
    @Published var volumeAlignment: String { didSet { defaults.set(volumeAlignment, forKey: Key.volumeAlinhamento) } }

    /// Mostra o controle de volume.
    @Published var volumeControl: Bool { didSet { defaults.set(volumeControl, forKey: Key.volume) } }
    /// Volume da saída de áudio, lido do sistema.
    @Published var volumeLevel: Double { didSet { defaults.set(volumeLevel, forKey: Key.volumeNivel) } }

    /// Tonalização do vidro (0 = transparente, 1 = tonalizado), como o slider
    /// Liquid Glass das Configurações do Sistema.
    @Published var glassTint: Double { didSet { defaults.set(glassTint, forKey: Key.glassTint) } }
    /// Aparência da bandeja: automático, claro ou escuro.
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: Key.appearance) } }

    /// Valor do slider Liquid Glass do sistema, quando existe.
    static var systemGlassTint: Double? {
        UserDefaults.standard.object(forKey: "NSGlassTintAmount") as? Double
    }

    /// Estilo de ícones escolhido nas Configurações do Sistema (só leitura:
    /// é o sistema que aplica o tema, e o NSWorkspace já entrega o ícone pronto).
    static var systemIconStyle: String {
        switch UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme") {
        case .some(let v) where v.hasPrefix("Clear"):   return "Translúcido"
        case .some(let v) where v.hasPrefix("Tinted"):  return "Tonalizado"
        case .some(let v) where v.hasPrefix("Dark"):    return "Tom escuro"
        case .none:                                     return "Padrão"
        case .some(let v):                              return v
        }
    }

    /// Volta o vidro para o material do sistema, sem nada por cima.
    /// Relê o brilho da tela. Chamado quando o controle aparece: o usuário pode
    /// ter mexido pelo teclado enquanto ele estava escondido.
    func sincronizarBrilho() {
        if let real = BrightnessBackend.ler() { brightnessLevel = real }
    }

    /// Relê o volume da saída. Além do teclado, ele muda sozinho quando o
    /// usuário troca de fone: o "padrão" passa a ser outro aparelho, com outro
    /// nível.
    func sincronizarVolume() {
        if let real = VolumeBackend.ler() { volumeLevel = real }
    }

    func matchSystemGlassTint() {
        glassTint = GlassTint.systemNeutral
    }

    // MARK: - Atalhos globais

    /// Um atalho por ação: cada bandeja, o brilho, o volume e os ajustes.
    ///
    /// Era um atalho só, que agia na PRIMEIRA bandeja — com mais de uma
    /// configurada, as outras não tinham como ser chamadas pelo teclado. O
    /// valor antigo vira o atalho da primeira bandeja na migração, para quem já
    /// usava ⇧⌘D não perder o hábito.
    @Published private(set) var atalhos: [String: Shortcut] = [:]
    /// Mensagem por ação quando o macOS recusa a combinação escolhida.
    @Published private(set) var atalhoErros: [String: String] = [:]

    func atalho(de acao: AcaoDeAtalho) -> Shortcut? { atalhos[acao.id] }
    func erroDoAtalho(_ acao: AcaoDeAtalho) -> String? { atalhoErros[acao.id] }

    /// Define (ou remove, com `nil`) o atalho de uma ação.
    ///
    /// Um atalho recusado não é gravado — senão o app subiria sem ele na
    /// próxima vez, sem explicar por quê.
    func definirAtalho(_ novo: Shortcut?, para acao: AcaoDeAtalho) {
        let anterior = atalhos
        var mapa = atalhos

        if let novo {
            guard novo.isValid else {
                atalhoErros[acao.id] = HotKeyManager.Falha.invalido.mensagem
                return
            }
            if let outra = Atalhos.jaUsadaPor(novo, em: mapa, ignorando: acao.id) {
                atalhoErros[acao.id] = "Essa combinação já é do atalho \(nomeDaAcao(outra))."
                return
            }
            mapa[acao.id] = novo
        } else {
            mapa.removeValue(forKey: acao.id)
        }

        let falhas = HotKeyManager.shared.aplicar(mapa)
        if let falha = falhas[acao.id] {
            atalhoErros[acao.id] = falha.mensagem
            HotKeyManager.shared.aplicar(anterior)   // volta para o que funcionava
            return
        }
        atalhos = mapa
        atalhoErros = atalhoErros.filter { falhas[$0.key] != nil }
        for (chave, falha) in falhas { atalhoErros[chave] = falha.mensagem }
        gravarAtalhos()
    }

    /// Nome legível de uma ação, para as mensagens e para os ajustes.
    func nomeDaAcao(_ id: String) -> String {
        guard let acao = AcaoDeAtalho(id: id) else { return id }
        switch acao {
        case .brilho:  return "Controle de brilho"
        case .volume:  return "Controle de volume"
        case .ajustes: return "Abrir os ajustes"
        case .bandeja(let uuid):
            guard let i = docks.firstIndex(where: { $0.id == uuid }) else { return "Bandeja" }
            let d = docks[i]
            return "Bandeja \(i + 1) — \(d.edge.titulo), \(d.alignment.titulo(for: d.edge).lowercased())"
        }
    }

    private func gravarAtalhos() {
        if let dados = try? JSONEncoder().encode(atalhos) {
            defaults.set(dados, forKey: Key.atalhos)
        }
    }

    /// Chamado na inicialização e sempre que as bandejas mudam.
    func ativarAtalhos() {
        // bandeja apagada não pode deixar o atalho registrado no sistema
        let limpo = Atalhos.limpar(atalhos, bandejasExistentes: Set(docks.map(\.id)))
        if limpo.count != atalhos.count { atalhos = limpo }
        // grava sempre, e não só quando limpou: o conjunto pode ter acabado de
        // nascer da migração do atalho único, e sem isto ele só existiria na
        // memória — a migração rodaria de novo a cada início
        gravarAtalhos()
        let falhas = HotKeyManager.shared.aplicar(atalhos)
        let novos = falhas.mapValues(\.mensagem)
        // publicar sem mudança acordaria quem observa o store à toa
        if novos != atalhoErros { atalhoErros = novos }
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
            Key.brilho: false,
            Key.brilhoNivel: 0.5,
            Key.brilhoBorda: TrayEdge.right.rawValue,
            Key.brilhoAlinhamento: TrayAlignment.center.rawValue,
            Key.volume: false,
            Key.volumeNivel: 0.5,
            Key.volumeBorda: TrayEdge.left.rawValue,
            Key.volumeAlinhamento: TrayAlignment.center.rawValue,
            Key.glassTint: GlassTint.systemNeutral,   // nasce translúcido, como o Dock
            Key.appearance: TrayAppearance.automatico.rawValue,
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
        brightnessControl = defaults.bool(forKey: Key.brilho)
        brightnessLevel = BrightnessBackend.ler() ?? defaults.double(forKey: Key.brilhoNivel)
        brightnessEdge = defaults.string(forKey: Key.brilhoBorda) ?? TrayEdge.right.rawValue
        brightnessAlignment = defaults.string(forKey: Key.brilhoAlinhamento) ?? TrayAlignment.center.rawValue
        volumeControl = defaults.bool(forKey: Key.volume)
        volumeLevel = VolumeBackend.ler() ?? defaults.double(forKey: Key.volumeNivel)
        volumeEdge = defaults.string(forKey: Key.volumeBorda) ?? TrayEdge.left.rawValue
        volumeAlignment = defaults.string(forKey: Key.volumeAlinhamento) ?? TrayAlignment.center.rawValue
        glassTint = defaults.double(forKey: Key.glassTint)
        appearance = defaults.string(forKey: Key.appearance) ?? TrayAppearance.automatico.rawValue

        // migração: quem já usava o app tinha UMA bandeja, com os apps em
        // docka.apps e a posição em docka.position/offsetX
        if let data = defaults.data(forKey: Key.docks),
           let salvas = try? JSONDecoder().decode([DockConfig].self, from: data),
           !salvas.isEmpty {
            docks = salvas
        } else {
            let posLegado = defaults.string(forKey: Key.position) ?? "right"
            let offLegado = defaults.double(forKey: Key.offsetX)
            let migrada = DockConfig(apps: defaults.stringArray(forKey: Key.apps) ?? [],
                                     edge: .bottom,
                                     alignment: TrayAlignment(persisted: posLegado),
                                     offset: offLegado)
            docks = [migrada]
            // grava já: o didSet não dispara na inicialização, e sem isto cada
            // abertura criaria um id novo para a mesma bandeja
            if let data = try? JSONEncoder().encode([migrada]) {
                defaults.set(data, forKey: Key.docks)
            }
        }

        if let dados = defaults.data(forKey: Key.atalhos),
           let mapa = try? JSONDecoder().decode([String: Shortcut].self, from: dados) {
            atalhos = mapa
        } else {
            // migração do atalho único: ele passa a ser o da primeira bandeja,
            // que é exatamente a que ele já controlava
            let gravado = Shortcut(keyCode: UInt16(defaults.integer(forKey: Key.atalhoTecla)),
                                   modifiers: .init(rawValue: UInt32(defaults.integer(forKey: Key.atalhoMods))))
            let herdado = gravado.isValid ? gravado : .padrao
            if let primeira = docks.first { atalhos = [AcaoDeAtalho.bandeja(primeira.id).id: herdado] }
        }

        refreshLaunchAtLogin()
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

    func playSound(_ name: String, volume: Float = 1) {
        guard soundsEnabled else { return }
        let som = NSSound(named: name)
        som?.volume = volume
        som?.play()
    }

    /// Tique do brilho: baixo de propósito. No volume cheio, dezesseis deles
    /// num arrasto viram barulho em vez de retorno.
    func tiqueDeBrilho() { playSound("Tink", volume: 0.22) }

    /// Tique do volume: o mesmo do brilho, mas um tom acima e mais discreto.
    /// Ele soa POR CIMA do que se está ajustando — um tique alto no volume alto
    /// vira estouro, e no volume baixo nem se ouve.
    func tiqueDeVolume() { playSound("Pop", volume: 0.18) }
}
