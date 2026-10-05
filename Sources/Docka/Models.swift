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
        static let volumeAntesDoMudo = "docka.volumeBeforeMute"
        static let glassTint = "docka.glassTint"
        static let appearance = "docka.appearance"
        static let atalhoTecla = "docka.hotkey.keyCode"
        static let atalhoMods = "docka.hotkey.modifiers"
        static let atalhos = "docka.hotkeys"
        static let orbita = "docka.orbitaControl"
        static let orbitaBandeja = "docka.orbitaDock"
        static let orbitaCanto = "docka.orbitaCorner"
        static let orbitaBotao = "docka.orbitaMouseButton"
        static let orbitaApps = "docka.orbitaApps"
        static let orbitaAneis = "docka.orbitaRings"
        static let orbitaAnelAtivo = "docka.orbitaActiveRing"
        static let acordadoDuracao = "docka.keepAwakeDuration"
        static let acordadoTela = "docka.keepAwakeDisplay"
        static let acoesRapidas = "docka.quickActions"
        static let prateleira = "docka.shelf"
        static let prateleiraBorda = "docka.shelfEdge"
        static let prateleiraAlinhamento = "docka.shelfAlignment"
        static let prateleiraAoArrastar = "docka.shelfOnDrag"
        static let notas = "docka.notes"
        static let notasBorda = "docka.notesEdge"
        static let notasAlinhamento = "docka.notesAlignment"
        static let monitor = "docka.monitor"
        static let monitorBorda = "docka.monitorEdge"
        static let monitorAlinhamento = "docka.monitorAlignment"
        static let leituraDaBarra = "docka.menuBarReading"
        static let alertas = "docka.alerts"
        static let alertaCPU = "docka.alertCPU"
        static let alertaCPULimite = "docka.alertCPULimit"
        static let alertaCPUMinutos = "docka.alertCPUMinutes"
        static let alertaMemoria = "docka.alertMemory"
        static let alertaDisco = "docka.alertDisk"
        static let alertaDiscoGB = "docka.alertDiskGB"
        static let alertaBateria = "docka.alertBattery"
        static let alertaBateriaLimite = "docka.alertBatteryLimit"
        static let alertaTemperatura = "docka.alertThermal"
        static let historico = "docka.clipboardHistory"
        static let historicoLimite = "docka.clipboardLimit"
        static let historicoLembrar = "docka.clipboardRemember"
        static let limparLinks = "docka.cleanLinksOnCopy"
        static let apagarClipboard = "docka.clearClipboardAfter"
        static let colarSozinho = "docka.autoPaste"
        static let apagarAoBloquear = "docka.clearClipboardOnLock"
        static let gatilhos = "docka.snippetTriggers"
        static let janelas = "docka.windowSnapping"
        static let janelasArrastar = "docka.windowSnapDrag"
        static let sairAoFechar = "docka.quitOnClose"
        static let sairAoFecharApps = "docka.quitOnCloseApps"
        static let protecaoQ = "docka.protectQuit"
        static let protecaoW = "docka.protectClose"
        static let protecaoModo = "docka.protectMode"
        static let protecaoApps = "docka.protectApps"
        static let botaoVerde = "docka.greenButtonMaximizes"
        static let arrastarComTecla = "docka.modifierDrag"
        static let arrastarTeclas = "docka.modifierDragKeys"
        static let arrastarRedimensiona = "docka.modifierDragResize"
        static let cliquesNoDock = "docka.dockClicks"
        static let ilha = "docka.island"
        static let ilhaAbrirAoPairar = "docka.islandHoverOpen"
        static let ilhaCombinar = "docka.islandCombine"
        static let ilhaSomDoTimer = "docka.islandTimerSound"
        static let ilhaOrdem = "docka.islandOrder"
        static let ilhaOcultas = "docka.islandHidden"
        static let ilhaBotoesEsquerda = "docka.islandLeftButtons"
        static let ilhaBotoesDireita = "docka.islandRightButtons"
        static let ilhaLetra = "docka.islandLyrics"
        static let ilhaNotificacoes = "docka.islandNotifications"
        static let ilhaAvisoAgentes = "docka.islandAgentNotice"
        static let ilhaAvisoBateria = "docka.islandNoticeBattery"
        static let ilhaAvisoFones = "docka.islandNoticeHeadphones"
        static let ilhaAvisoVolume = "docka.islandNoticeVolume"
        static let ilhaAvisoBrilho = "docka.islandNoticeBrightness"
        static let ilhaAvisoCopiado = "docka.islandNoticeCopy"
        static let ilhaAvisoAgentesMinutos = "docka.islandAgentNoticeMinutes"
        static let ilhaEqualizadorAoVivo = "docka.islandLiveEqualizer"
        static let previaDoDock = "docka.dockPreview"
        static let previaDoDockMiniaturas = "docka.dockPreviewThumbnails"
        static let previaDoDockAtraso = "docka.dockPreviewDelay"
        static let acaoNoCliqueDoDock = "docka.dockClickAction"
        static let alternador = "docka.switcher"
        static let alternadorJanelas = "docka.switcherWindows"
        static let alternadorPrevias = "docka.switcherPreviews"
        static let alternadorSoTela = "docka.switcherCurrentScreen"
        static let alternadorSemJanela = "docka.switcherHideWindowless"
        static let mouse = "docka.mouse"
        static let mouseInverterV = "docka.mouseInvertVertical"
        static let mouseInverterH = "docka.mouseInvertHorizontal"
        static let mouseLinhas = "docka.mouseLinesPerNotch"
        static let mouseSuave = "docka.mouseSmooth"
        static let mouseDeLado = "docka.mouseSidewaysModifier"
        static let mouseBotoes = "docka.mouseSideButtons"
        static let mouseIgnorados = "docka.mouseIgnoredApps"
        static let captura = "docka.capture"
        static let formatoDeCor = "docka.colorFormat"
        static let capturaNaMesa = "docka.captureToDesktop"
        static let capturaEditar = "docka.captureEdit"
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

    /// O anel em uso — o ativo, ou o primeiro se o ativo sumiu.
    var anelEmUso: AnelDaOrbita? {
        aneis.first { $0.id == anelAtivo } ?? aneis.first
    }

    /// Os itens do anel em uso que ainda existem no disco.
    var itensDaOrbita: [ItemDaOrbita] { itens(doAnel: nil) }

    /// Os itens de um anel (`nil` = o em uso) que ainda existem — os submenus
    /// mostram outro anel sem trocar o ativo.
    func itens(doAnel id: UUID?) -> [ItemDaOrbita] {
        let anel = id.flatMap { i in aneis.first { $0.id == i } } ?? anelEmUso
        return (anel?.itens ?? []).filter { ItemVisual.existe($0) }
    }

    private func atualizarAnel(_ id: UUID, _ mudanca: (inout AnelDaOrbita) -> Void) {
        guard let i = aneis.firstIndex(where: { $0.id == id }) else { return }
        mudanca(&aneis[i])
    }

    func adicionarAnel() {
        guard Aneis.podeCriar(aneis) else { return }
        let novo = AnelDaOrbita(nome: Aneis.nomeNovo(aneis))
        aneis.append(novo)
        anelAtivo = novo.id
    }

    func removerAnel(_ id: UUID) {
        guard aneis.count > 1 else { return }   // sempre sobra um
        aneis = Aneis.removendo(id, de: aneis)
        if anelAtivo == id { anelAtivo = aneis.first?.id }
    }

    func renomearAnel(_ id: UUID, para nome: String) {
        let limpo = nome.trimmingCharacters(in: .whitespaces)
        guard !limpo.isEmpty else { return }
        atualizarAnel(id) { $0.nome = limpo }
    }

    func adicionarItem(_ item: ItemDaOrbita, em id: UUID) {
        atualizarAnel(id) { anel in
            guard anel.itens.count < Aneis.maximoDeItens,
                  !anel.itens.contains(where: { $0.tipo == item.tipo && $0.valor == item.valor })
            else { return }
            anel.itens.append(item)
        }
    }

    func removerItem(_ itemID: UUID, de id: UUID) {
        atualizarAnel(id) { $0.itens.removeAll { $0.id == itemID } }
    }

    /// Move o item uma casa no anel — as setinhas da zona no editor.
    func moverItem(_ itemID: UUID, passo: Int, em id: UUID) {
        atualizarAnel(id) { $0.mover(itemID, passo: passo) }
    }

    /// Rola para o anel vizinho — usado pela rolagem com a órbita aberta.
    func rolarAnel(_ passo: Int) {
        anelAtivo = Aneis.proximo(de: anelAtivo, em: aneis, passo: passo)
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
    /// Nível de antes do mudo — o toque no botão volta para ele.
    var volumeAntesDoMudo: Double {
        get { defaults.double(forKey: Key.volumeAntesDoMudo) }
        set { defaults.set(newValue, forKey: Key.volumeAntesDoMudo) }
    }

    /// Mostra a órbita — o anel de apps em volta do cursor.
    @Published var orbitaControl: Bool { didSet { defaults.set(orbitaControl, forKey: Key.orbita) } }
    /// Os anéis da órbita — até 8, cada um com nome e itens próprios
    /// (apps, sites, arquivos e pastas), como na referência.
    @Published var aneis: [AnelDaOrbita] {
        didSet {
            if let dados = try? JSONEncoder().encode(aneis) {
                defaults.set(dados, forKey: Key.orbitaAneis)
            }
        }
    }
    /// O anel mostrado ao abrir — o último usado; a rolagem troca.
    @Published var anelAtivo: UUID? {
        didSet { defaults.set(anelAtivo?.uuidString ?? "", forKey: Key.orbitaAnelAtivo) }
    }
    /// Canto da tela que abre a órbita; vazio = só pelo atalho.
    @Published var orbitaCanto: String { didSet { defaults.set(orbitaCanto, forKey: Key.orbitaCanto) } }
    /// Botão extra do mouse que abre a órbita; -1 = nenhum.
    @Published var orbitaBotao: Int { didSet { defaults.set(orbitaBotao, forKey: Key.orbitaBotao) } }

    /// Duração usada pelo atalho e pelo clique direto em "Manter acordado".
    @Published var acordadoDuracao: DuracaoAcordado {
        didSet { defaults.set(acordadoDuracao.rawValue, forKey: Key.acordadoDuracao) }
    }
    /// Manter acordado segura também a tela acesa, não só o sistema.
    @Published var acordadoTelaAcesa: Bool {
        didSet {
            defaults.set(acordadoTelaAcesa, forKey: Key.acordadoTela)
            AcordadoSessao.shared.trocarTela(acesa: acordadoTelaAcesa)
        }
    }

    /// Liga a prateleira — o painel de borda que segura arquivos, textos e links.
    @Published var prateleiraControl: Bool { didSet { defaults.set(prateleiraControl, forKey: Key.prateleira) } }
    /// Lateral da prateleira.
    @Published var prateleiraBorda: String { didSet { defaults.set(prateleiraBorda, forKey: Key.prateleiraBorda) } }
    @Published var prateleiraAlinhamento: String { didSet { defaults.set(prateleiraAlinhamento, forKey: Key.prateleiraAlinhamento) } }
    /// Abre a prateleira sozinha quando um arrasto começa em qualquer lugar.
    @Published var prateleiraAoArrastar: Bool { didSet { defaults.set(prateleiraAoArrastar, forKey: Key.prateleiraAoArrastar) } }

    /// Liga o bloco de notas de borda.
    @Published var notasControl: Bool { didSet { defaults.set(notasControl, forKey: Key.notas) } }
    @Published var notasBorda: String { didSet { defaults.set(notasBorda, forKey: Key.notasBorda) } }
    @Published var notasAlinhamento: String { didSet { defaults.set(notasAlinhamento, forKey: Key.notasAlinhamento) } }

    /// Liga o painel de borda do monitor do sistema.
    @Published var monitorControl: Bool { didSet { defaults.set(monitorControl, forKey: Key.monitor) } }
    @Published var monitorBorda: String { didSet { defaults.set(monitorBorda, forKey: Key.monitorBorda) } }
    @Published var monitorAlinhamento: String { didSet { defaults.set(monitorAlinhamento, forKey: Key.monitorAlinhamento) } }
    /// O que aparece na barra de menus ao lado do ícone.
    @Published var leituraDaBarra: LeituraDaBarra {
        didSet {
            defaults.set(leituraDaBarra.rawValue, forKey: Key.leituraDaBarra)
            MonitorModelo.shared.interesse("barra", leituraDaBarra != .nenhuma)
        }
    }

    /// Liga os alertas; cada um tem o seu interruptor e limite.
    @Published var alertas: Bool { didSet { defaults.set(alertas, forKey: Key.alertas) } }
    @Published var alertaCPU: Bool { didSet { defaults.set(alertaCPU, forKey: Key.alertaCPU) } }
    @Published var alertaCPULimite: Double { didSet { defaults.set(alertaCPULimite, forKey: Key.alertaCPULimite) } }
    @Published var alertaCPUMinutos: Int { didSet { defaults.set(alertaCPUMinutos, forKey: Key.alertaCPUMinutos) } }
    @Published var alertaMemoria: Bool { didSet { defaults.set(alertaMemoria, forKey: Key.alertaMemoria) } }
    @Published var alertaDisco: Bool { didSet { defaults.set(alertaDisco, forKey: Key.alertaDisco) } }
    @Published var alertaDiscoGB: Int { didSet { defaults.set(alertaDiscoGB, forKey: Key.alertaDiscoGB) } }
    @Published var alertaBateria: Bool { didSet { defaults.set(alertaBateria, forKey: Key.alertaBateria) } }
    @Published var alertaBateriaLimite: Double { didSet { defaults.set(alertaBateriaLimite, forKey: Key.alertaBateriaLimite) } }
    @Published var alertaTemperatura: Bool { didSet { defaults.set(alertaTemperatura, forKey: Key.alertaTemperatura) } }

    /// Guarda o histórico da área de transferência.
    @Published var historicoControl: Bool {
        didSet { defaults.set(historicoControl, forKey: Key.historico); sincronizarClipboard() }
    }
    @Published var historicoLimite: Int { didSet { defaults.set(historicoLimite, forKey: Key.historicoLimite) } }
    /// Grava o histórico em disco para sobreviver a reaberturas.
    @Published var historicoLembrar: Bool {
        didSet { defaults.set(historicoLembrar, forKey: Key.historicoLembrar); HistoricoModelo.shared.gravarAgora() }
    }
    /// Tira rastreadores de todo link copiado, sozinho.
    @Published var limparLinksAoCopiar: Bool {
        didSet { defaults.set(limparLinksAoCopiar, forKey: Key.limparLinks); sincronizarClipboard() }
    }
    /// Segundos até apagar a área de transferência (0 = nunca).
    @Published var apagarClipboard: Int {
        didSet { defaults.set(apagarClipboard, forKey: Key.apagarClipboard); sincronizarClipboard() }
    }

    /// Módulo com permissão: cola sozinho o que se escolhe no histórico e
    /// nos snippets. Ligar pede a Acessibilidade, se ainda não houver.
    @Published var colarSozinho: Bool {
        didSet {
            defaults.set(colarSozinho, forKey: Key.colarSozinho)
            if colarSozinho && !Colagem.permitido { Colagem.pedirPermissao() }
        }
    }

    /// Módulo com permissão: encaixar a janela da frente em layouts.
    @Published var janelasControl: Bool {
        didSet {
            defaults.set(janelasControl, forKey: Key.janelas)
            if janelasControl && !Colagem.permitido { Colagem.pedirPermissao() }
            ArrastoDeJanelas.shared.sincronizar()
        }
    }
    /// Encerrar os apps escolhidos quando a última janela fecha.
    @Published var sairAoFecharControl: Bool {
        didSet { defaults.set(sairAoFecharControl, forKey: Key.sairAoFechar); pedirAcessibilidadeSe(sairAoFecharControl); sincronizarJanelasEDock() }
    }
    @Published var sairAoFecharApps: [String] {
        didSet { defaults.set(sairAoFecharApps, forKey: Key.sairAoFecharApps); sincronizarJanelasEDock() }
    }
    /// Proteção do ⌘Q e do ⌘W.
    @Published var protecaoQ: Bool {
        didSet { defaults.set(protecaoQ, forKey: Key.protecaoQ); pedirAcessibilidadeSe(protecaoQ); sincronizarJanelasEDock() }
    }
    @Published var protecaoW: Bool {
        didSet { defaults.set(protecaoW, forKey: Key.protecaoW); pedirAcessibilidadeSe(protecaoW); sincronizarJanelasEDock() }
    }
    @Published var protecaoModo: String {
        didSet { defaults.set(protecaoModo, forKey: Key.protecaoModo); sincronizarJanelasEDock() }
    }
    /// Apps protegidos; vazio = todos.
    @Published var protecaoApps: [String] { didSet { defaults.set(protecaoApps, forKey: Key.protecaoApps) } }
    /// O botão verde maximiza na área útil, sem criar outro Espaço.
    @Published var botaoVerdeMaximiza: Bool {
        didSet { defaults.set(botaoVerdeMaximiza, forKey: Key.botaoVerde); pedirAcessibilidadeSe(botaoVerdeMaximiza); sincronizarJanelasEDock() }
    }
    /// Clicar no ícone do app ativo no Dock minimiza, oculta ou alterna.
    @Published var cliquesNoDock: Bool {
        didSet { defaults.set(cliquesNoDock, forKey: Key.cliquesNoDock); pedirAcessibilidadeSe(cliquesNoDock); sincronizarJanelasEDock() }
    }
    /// A Ilha Dinâmica em volta do recorte da câmera.
    @Published var ilhaControl: Bool {
        didSet { defaults.set(ilhaControl, forKey: Key.ilha); IlhaController.shared.sincronizar() }
    }
    /// Parado tanto tempo sobre a ilha, ela abre; 0 = só no clique.
    @Published var ilhaAbrirAoPairar: Double { didSet { defaults.set(ilhaAbrirAoPairar, forKey: Key.ilhaAbrirAoPairar) } }
    @Published var ilhaCombinar: Bool { didSet { defaults.set(ilhaCombinar, forKey: Key.ilhaCombinar) } }
    @Published var ilhaSomDoTimer: Bool { didSet { defaults.set(ilhaSomDoTimer, forKey: Key.ilhaSomDoTimer) } }
    /// Notificações recentes na ilha, lidas dos avisos da tela (Acessibilidade).
    @Published var ilhaNotificacoes: Bool {
        didSet {
            defaults.set(ilhaNotificacoes, forKey: Key.ilhaNotificacoes)
            pedirAcessibilidadeSe(ilhaNotificacoes)
            NotificacoesModelo.shared.sincronizar()
        }
    }
    /// Avisos rápidos nas asas da ilha.
    @Published var ilhaAvisoBateria: Bool { didSet { defaults.set(ilhaAvisoBateria, forKey: Key.ilhaAvisoBateria) } }
    @Published var ilhaAvisoFones: Bool { didSet { defaults.set(ilhaAvisoFones, forKey: Key.ilhaAvisoFones) } }
    @Published var ilhaAvisoVolume: Bool { didSet { defaults.set(ilhaAvisoVolume, forKey: Key.ilhaAvisoVolume) } }
    @Published var ilhaAvisoBrilho: Bool { didSet { defaults.set(ilhaAvisoBrilho, forKey: Key.ilhaAvisoBrilho) } }
    @Published var ilhaAvisoCopiado: Bool { didSet { defaults.set(ilhaAvisoCopiado, forKey: Key.ilhaAvisoCopiado) } }
    /// Avisar na ilha quando um agente de IA termina uma tarefa longa.
    @Published var ilhaAvisoAgentes: Bool { didSet { defaults.set(ilhaAvisoAgentes, forKey: Key.ilhaAvisoAgentes) } }
    @Published var ilhaAvisoAgentesMinutos: Double { didSet { defaults.set(ilhaAvisoAgentesMinutos, forKey: Key.ilhaAvisoAgentesMinutos) } }
    /// Letra sincronizada da música, buscada no lrclib.net.
    @Published var ilhaLetra: Bool { didSet { defaults.set(ilhaLetra, forKey: Key.ilhaLetra) } }
    /// Equalizador medindo o áudio de verdade — pede Gravação de Tela.
    @Published var ilhaEqualizadorAoVivo: Bool {
        didSet {
            defaults.set(ilhaEqualizadorAoVivo, forKey: Key.ilhaEqualizadorAoVivo)
            if ilhaEqualizadorAoVivo && !CapturaController.permitido { CapturaController.pedirPermissao() }
        }
    }
    /// A ordem das seções na grade (as que faltarem vão para o fim).
    @Published var ilhaOrdem: [String] { didSet { defaults.set(ilhaOrdem, forKey: Key.ilhaOrdem) } }
    @Published var ilhaOcultas: [String] { didSet { defaults.set(ilhaOcultas, forKey: Key.ilhaOcultas) } }
    @Published var ilhaBotoesEsquerda: [String] { didSet { defaults.set(ilhaBotoesEsquerda, forKey: Key.ilhaBotoesEsquerda) } }
    @Published var ilhaBotoesDireita: [String] { didSet { defaults.set(ilhaBotoesDireita, forKey: Key.ilhaBotoesDireita) } }
    /// A seção que os ajustes devem abrir (a ilha pede a dela).
    @Published var secaoDosAjustesPedida: String?

    /// Prévia das janelas ao parar o cursor num ícone do Dock.
    @Published var previaDoDock: Bool {
        didSet {
            defaults.set(previaDoDock, forKey: Key.previaDoDock)
            pedirAcessibilidadeSe(previaDoDock)
            if previaDoDock && previaDoDockMiniaturas && !CapturaController.permitido { CapturaController.pedirPermissao() }
            PreviaDoDockController.shared.sincronizar()
        }
    }
    @Published var previaDoDockMiniaturas: Bool {
        didSet {
            defaults.set(previaDoDockMiniaturas, forKey: Key.previaDoDockMiniaturas)
            if previaDoDockMiniaturas && !CapturaController.permitido { CapturaController.pedirPermissao() }
        }
    }
    @Published var previaDoDockAtraso: Double { didSet { defaults.set(previaDoDockAtraso, forKey: Key.previaDoDockAtraso) } }

    @Published var acaoNoCliqueDoDock: String { didSet { defaults.set(acaoNoCliqueDoDock, forKey: Key.acaoNoCliqueDoDock) } }

    private func pedirAcessibilidadeSe(_ ligado: Bool) {
        if ligado && !Colagem.permitido { Colagem.pedirPermissao() }
    }

    /// Religa tudo o que depende de permissão — chamado quando o app termina
    /// de abrir e sempre que uma permissão muda.
    func sincronizarModulosComPermissao() {
        sincronizarJanelasEDock()
        MouseController.shared.sincronizar()
        GatilhosController.shared.sincronizar()
        ArrastoDeJanelas.shared.sincronizar()
        ArrastoComTeclaController.shared.sincronizar()
        PreviaDoDockController.shared.sincronizar()
        IlhaController.shared.sincronizar()
        NotificacoesModelo.shared.sincronizar()
    }

    /// Liga ou desliga os vigias e taps destes recursos conforme os ajustes.
    func sincronizarJanelasEDock() {
        SairAoFecharController.shared.sincronizar()
        ProtecaoController.shared.sincronizar()
        CliquesDoSistema.shared.sincronizar()
    }

    /// Mover e redimensionar a janela de qualquer ponto, segurando teclas.
    @Published var arrastarComTecla: Bool {
        didSet {
            defaults.set(arrastarComTecla, forKey: Key.arrastarComTecla)
            pedirAcessibilidadeSe(arrastarComTecla)
            ArrastoComTeclaController.shared.sincronizar()
        }
    }
    @Published var arrastarTeclas: String { didSet { defaults.set(arrastarTeclas, forKey: Key.arrastarTeclas) } }
    @Published var arrastarRedimensiona: Bool { didSet { defaults.set(arrastarRedimensiona, forKey: Key.arrastarRedimensiona) } }

    /// Encaixar arrastando a janela até a borda da tela.
    @Published var janelasArrastar: Bool {
        didSet {
            defaults.set(janelasArrastar, forKey: Key.janelasArrastar)
            ArrastoDeJanelas.shared.sincronizar()
        }
    }

    /// Alternador de apps no atalho próprio (sem permissão).
    @Published var alternadorControl: Bool {
        didSet {
            defaults.set(alternadorControl, forKey: Key.alternador)
            AlternadorController.shared.ligar(alternadorControl)
        }
    }
    /// Uma entrada por janela no alternador — pede Acessibilidade.
    @Published var alternadorJanelas: Bool {
        didSet {
            defaults.set(alternadorJanelas, forKey: Key.alternadorJanelas)
            if alternadorJanelas && !Colagem.permitido { Colagem.pedirPermissao() }
        }
    }

    /// Módulo com permissão: a rolagem e os botões do mouse.
    @Published var mouseControl: Bool {
        didSet {
            defaults.set(mouseControl, forKey: Key.mouse)
            if mouseControl && !Colagem.permitido { Colagem.pedirPermissao() }
            MouseController.shared.sincronizar()
        }
    }
    @Published var mouseInverterVertical: Bool { didSet { defaults.set(mouseInverterVertical, forKey: Key.mouseInverterV) } }
    @Published var mouseInverterHorizontal: Bool { didSet { defaults.set(mouseInverterHorizontal, forKey: Key.mouseInverterH) } }
    /// Linhas por dente da roda; 0 = a aceleração do sistema.
    @Published var mouseLinhas: Int { didSet { defaults.set(mouseLinhas, forKey: Key.mouseLinhas) } }
    @Published var mouseSuave: Bool { didSet { defaults.set(mouseSuave, forKey: Key.mouseSuave) } }
    /// Modificadores (rawValue de Shortcut.Modifiers) que rolam de lado; 0 = nenhum.
    @Published var mouseDeLado: Int { didSet { defaults.set(mouseDeLado, forKey: Key.mouseDeLado) } }
    @Published var mouseBotoes: Bool { didSet { defaults.set(mouseBotoes, forKey: Key.mouseBotoes) } }
    /// Bundle IDs dos apps em que o mouse fica como o sistema manda.
    @Published var mouseIgnorados: [String] { didSet { defaults.set(mouseIgnorados, forKey: Key.mouseIgnorados) } }

    /// Módulo de captura: conta-gotas (sem permissão), texto da tela e
    /// captura de área (Gravação de Tela).
    @Published var capturaControl: Bool {
        didSet {
            defaults.set(capturaControl, forKey: Key.captura)
            if capturaControl && !CapturaController.permitido { CapturaController.pedirPermissao() }
        }
    }
    @Published var formatoDeCor: String { didSet { defaults.set(formatoDeCor, forKey: Key.formatoDeCor) } }
    /// A captura de área vai para um arquivo na Mesa, em vez da área de transferência.
    @Published var capturaNaMesa: Bool { didSet { defaults.set(capturaNaMesa, forKey: Key.capturaNaMesa) } }
    /// Abre a captura de área no editor de anotação.
    @Published var capturaEditar: Bool { didSet { defaults.set(capturaEditar, forKey: Key.capturaEditar) } }

    /// Alternador: só o que está na tela do cursor.
    @Published var alternadorSoTela: Bool {
        didSet { defaults.set(alternadorSoTela, forKey: Key.alternadorSoTela); if alternadorSoTela && !Colagem.permitido { Colagem.pedirPermissao() } }
    }
    /// Alternador: esconder apps abertos sem nenhuma janela.
    @Published var alternadorSemJanela: Bool {
        didSet { defaults.set(alternadorSemJanela, forKey: Key.alternadorSemJanela); if alternadorSemJanela && !Colagem.permitido { Colagem.pedirPermissao() } }
    }

    /// Miniaturas das janelas no alternador — pede Gravação de Tela.
    @Published var alternadorPrevias: Bool {
        didSet {
            defaults.set(alternadorPrevias, forKey: Key.alternadorPrevias)
            if alternadorPrevias && !CapturaController.permitido { CapturaController.pedirPermissao() }
        }
    }

    /// Módulo com permissão: expandir gatilhos digitados em qualquer app.
    @Published var gatilhosControl: Bool {
        didSet {
            defaults.set(gatilhosControl, forKey: Key.gatilhos)
            if gatilhosControl {
                if !GatilhosController.podeEscutar { GatilhosController.pedirEscuta() }
                if !Colagem.permitido { Colagem.pedirPermissao() }
            }
            GatilhosController.shared.sincronizar()
        }
    }

    /// Apaga a área de transferência ao travar a tela ou dormir.
    @Published var apagarAoBloquear: Bool {
        didSet {
            defaults.set(apagarAoBloquear, forKey: Key.apagarAoBloquear)
            HistoricoModelo.shared.vigiarBloqueio(apagarAoBloquear)
        }
    }

    /// O vigia da área de transferência só roda se algum recurso dele está
    /// ligado — histórico, limpar links ou apagar depois de um tempo.
    func sincronizarClipboard() {
        HistoricoModelo.shared.ligar(historicoControl || limparLinksAoCopiar || apagarClipboard > 0)
    }

    /// Mostra o submenu "Ações rápidas" na barra de menus.
    @Published var acoesRapidas: Bool { didSet { defaults.set(acoesRapidas, forKey: Key.acoesRapidas) } }

    /// Liga com a duração escolhida, ou desliga se já estiver ligado.
    func alternarAcordado() {
        let sessao = AcordadoSessao.shared
        if sessao.ativo { sessao.desligar() }
        else { sessao.ligar(acordadoDuracao, telaAcesa: acordadoTelaAcesa) }
    }

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
        if let real = TelasDeBrilho.shared.lerRegua() { brightnessLevel = real }
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
        case .orbita:  return "Órbita"
        case .acordado: return "Manter acordado"
        case .rapida(let a): return a.titulo
        case .prateleira: return "Prateleira"
        case .blocoDeNotas: return "Bloco de notas"
        case .monitor: return "Monitor do sistema"
        case .historico: return "Histórico da área de transferência"
        case .textoPuro: return "Colar sem formatação"
        case .snippets: return "Snippets"
        case .janela(let l): return "Janela — \(l.titulo.lowercased())"
        case .alternador: return "Alternador de apps"
        case .contaGotas: return "Conta-gotas"
        case .textoDaTela: return "Texto da tela"
        case .capturaArea: return "Capturar área"
        case .ilha: return "Ilha Dinâmica"
        case .secaoDaIlha(let s): return "Ilha — \(s.titulo.lowercased())"
        case .anel(let uuid):
            let nome = aneis.first { $0.id == uuid }?.nome ?? "?"
            return "Órbita — \(nome)"
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
        let limpo = Atalhos.limpar(atalhos,
                                   bandejasExistentes: Set(docks.map(\.id)),
                                   aneisExistentes: Set(aneis.map(\.id)))
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
            Key.orbita: false,
            Key.acordadoDuracao: DuracaoAcordado.umaHora.rawValue,
            Key.acordadoTela: true,
            Key.acoesRapidas: false,
            Key.prateleira: false,
            Key.prateleiraBorda: TrayEdge.right.rawValue,
            Key.prateleiraAlinhamento: TrayAlignment.start.rawValue,
            Key.prateleiraAoArrastar: true,
            Key.notas: false,
            // a prateleira nasce na direita: as notas nascem do outro lado
            Key.notasBorda: TrayEdge.left.rawValue,
            Key.notasAlinhamento: TrayAlignment.center.rawValue,
            Key.monitor: false,
            Key.monitorBorda: TrayEdge.right.rawValue,
            // a prateleira fica no topo da direita: o monitor, na base
            Key.monitorAlinhamento: TrayAlignment.end.rawValue,
            Key.leituraDaBarra: LeituraDaBarra.nenhuma.rawValue,
            // desligados em bloco por padrão; ligando, todos já vêm marcados
            Key.alertas: false,
            Key.alertaCPU: true,
            Key.alertaCPULimite: 0.85,
            Key.alertaCPUMinutos: 2,
            Key.alertaMemoria: true,
            Key.alertaDisco: true,
            Key.alertaDiscoGB: 10,
            Key.alertaBateria: true,
            Key.alertaBateriaLimite: 0.20,
            Key.alertaTemperatura: true,
            Key.historico: false,
            Key.historicoLimite: HistoricoDeCopias.limitePadrao,
            Key.historicoLembrar: true,
            Key.limparLinks: false,
            Key.apagarClipboard: 0,
            Key.colarSozinho: false,
            Key.apagarAoBloquear: false,
            Key.gatilhos: false,
            Key.janelas: false,
            Key.janelasArrastar: false,
            Key.sairAoFechar: false,
            Key.protecaoQ: false,
            Key.protecaoW: false,
            Key.protecaoModo: ModoDeProtecao.segurar.rawValue,
            Key.botaoVerde: false,
            Key.arrastarComTecla: false,
            Key.arrastarTeclas: TeclasDoArrasto.controleOpcao.rawValue,
            Key.arrastarRedimensiona: true,
            Key.cliquesNoDock: false,
            Key.ilha: false,
            Key.ilhaAbrirAoPairar: 0.5,
            Key.ilhaCombinar: true,
            Key.ilhaSomDoTimer: true,
            Key.ilhaLetra: false,
            Key.ilhaNotificacoes: false,
            Key.ilhaAvisoAgentes: true,
            Key.ilhaAvisoBateria: true,
            Key.ilhaAvisoFones: true,
            Key.ilhaAvisoVolume: true,
            Key.ilhaAvisoBrilho: true,
            Key.ilhaAvisoCopiado: false,
            Key.ilhaAvisoAgentesMinutos: 3.0,
            Key.ilhaEqualizadorAoVivo: false,
            Key.previaDoDock: false,
            Key.previaDoDockMiniaturas: true,
            Key.previaDoDockAtraso: 0.5,
            Key.acaoNoCliqueDoDock: AcaoNoCliqueDoDock.minimizar.rawValue,
            Key.alternador: false,
            Key.alternadorJanelas: false,
            Key.alternadorPrevias: false,
            Key.alternadorSoTela: false,
            Key.alternadorSemJanela: false,
            Key.mouse: false,
            Key.mouseInverterV: false,
            Key.mouseInverterH: false,
            Key.mouseLinhas: 0,
            Key.mouseSuave: false,
            Key.mouseDeLado: 0,
            Key.mouseBotoes: false,
            Key.captura: false,
            Key.formatoDeCor: FormatoDeCor.hex.rawValue,
            Key.capturaNaMesa: false,
            Key.capturaEditar: true,

            Key.orbitaCanto: "",
            Key.orbitaBotao: BotaoDoMouse.nenhum,
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
        brightnessLevel = TelasDeBrilho.shared.lerRegua() ?? defaults.double(forKey: Key.brilhoNivel)
        brightnessEdge = defaults.string(forKey: Key.brilhoBorda) ?? TrayEdge.right.rawValue
        brightnessAlignment = defaults.string(forKey: Key.brilhoAlinhamento) ?? TrayAlignment.center.rawValue
        volumeControl = defaults.bool(forKey: Key.volume)
        volumeLevel = VolumeBackend.ler() ?? defaults.double(forKey: Key.volumeNivel)
        volumeEdge = defaults.string(forKey: Key.volumeBorda) ?? TrayEdge.left.rawValue
        volumeAlignment = defaults.string(forKey: Key.volumeAlinhamento) ?? TrayAlignment.center.rawValue
        orbitaControl = defaults.bool(forKey: Key.orbita)
        if let dados = defaults.data(forKey: Key.orbitaAneis),
           let gravados = try? JSONDecoder().decode([AnelDaOrbita].self, from: dados) {
            aneis = gravados
        } else {
            // migração encadeada: a lista plana de apps (ou, antes dela, a
            // bandeja que a órbita usava) vira o primeiro anel
            let apps: [String]
            if let lista = defaults.stringArray(forKey: Key.orbitaApps) {
                apps = lista
            } else {
                let docksGravadas: [DockConfig] = (defaults.data(forKey: Key.docks)
                    .flatMap { try? JSONDecoder().decode([DockConfig].self, from: $0) }) ?? []
                let escolhida = defaults.string(forKey: Key.orbitaBandeja) ?? ""
                apps = (docksGravadas.first { $0.id.uuidString == escolhida }
                        ?? docksGravadas.first)?.apps ?? []
            }
            let primeiro = AnelDaOrbita(
                nome: "Anel 1",
                itens: apps.map { ItemDaOrbita(tipo: .app, valor: $0) })
            aneis = [primeiro]
            // didSet não dispara no init: sem gravar aqui a migração viveria só
            // na memória e rodaria de novo a cada início
            if let dados = try? JSONEncoder().encode([primeiro]) {
                defaults.set(dados, forKey: Key.orbitaAneis)
            }
        }
        anelAtivo = defaults.string(forKey: Key.orbitaAnelAtivo)
            .flatMap(UUID.init(uuidString:))
        orbitaCanto = defaults.string(forKey: Key.orbitaCanto) ?? ""
        orbitaBotao = defaults.object(forKey: Key.orbitaBotao) as? Int ?? BotaoDoMouse.nenhum
        acordadoDuracao = DuracaoAcordado(persisted: defaults.integer(forKey: Key.acordadoDuracao))
        acordadoTelaAcesa = defaults.bool(forKey: Key.acordadoTela)
        acoesRapidas = defaults.bool(forKey: Key.acoesRapidas)
        prateleiraControl = defaults.bool(forKey: Key.prateleira)
        prateleiraBorda = defaults.string(forKey: Key.prateleiraBorda) ?? TrayEdge.right.rawValue
        prateleiraAlinhamento = defaults.string(forKey: Key.prateleiraAlinhamento) ?? TrayAlignment.start.rawValue
        prateleiraAoArrastar = defaults.bool(forKey: Key.prateleiraAoArrastar)
        notasControl = defaults.bool(forKey: Key.notas)
        notasBorda = defaults.string(forKey: Key.notasBorda) ?? TrayEdge.left.rawValue
        notasAlinhamento = defaults.string(forKey: Key.notasAlinhamento) ?? TrayAlignment.center.rawValue
        monitorControl = defaults.bool(forKey: Key.monitor)
        monitorBorda = defaults.string(forKey: Key.monitorBorda) ?? TrayEdge.right.rawValue
        monitorAlinhamento = defaults.string(forKey: Key.monitorAlinhamento) ?? TrayAlignment.end.rawValue
        leituraDaBarra = LeituraDaBarra(persisted: defaults.string(forKey: Key.leituraDaBarra) ?? "")
        alertas = defaults.bool(forKey: Key.alertas)
        alertaCPU = defaults.bool(forKey: Key.alertaCPU)
        alertaCPULimite = defaults.double(forKey: Key.alertaCPULimite)
        alertaCPUMinutos = defaults.integer(forKey: Key.alertaCPUMinutos)
        alertaMemoria = defaults.bool(forKey: Key.alertaMemoria)
        alertaDisco = defaults.bool(forKey: Key.alertaDisco)
        alertaDiscoGB = defaults.integer(forKey: Key.alertaDiscoGB)
        alertaBateria = defaults.bool(forKey: Key.alertaBateria)
        alertaBateriaLimite = defaults.double(forKey: Key.alertaBateriaLimite)
        alertaTemperatura = defaults.bool(forKey: Key.alertaTemperatura)
        historicoControl = defaults.bool(forKey: Key.historico)
        historicoLimite = defaults.integer(forKey: Key.historicoLimite)
        historicoLembrar = defaults.bool(forKey: Key.historicoLembrar)
        limparLinksAoCopiar = defaults.bool(forKey: Key.limparLinks)
        apagarClipboard = defaults.integer(forKey: Key.apagarClipboard)
        colarSozinho = defaults.bool(forKey: Key.colarSozinho)
        apagarAoBloquear = defaults.bool(forKey: Key.apagarAoBloquear)
        gatilhosControl = defaults.bool(forKey: Key.gatilhos)
        janelasControl = defaults.bool(forKey: Key.janelas)
        janelasArrastar = defaults.bool(forKey: Key.janelasArrastar)
        sairAoFecharControl = defaults.bool(forKey: Key.sairAoFechar)
        sairAoFecharApps = defaults.stringArray(forKey: Key.sairAoFecharApps) ?? []
        protecaoQ = defaults.bool(forKey: Key.protecaoQ)
        protecaoW = defaults.bool(forKey: Key.protecaoW)
        protecaoModo = defaults.string(forKey: Key.protecaoModo) ?? ModoDeProtecao.segurar.rawValue
        protecaoApps = defaults.stringArray(forKey: Key.protecaoApps) ?? []
        botaoVerdeMaximiza = defaults.bool(forKey: Key.botaoVerde)
        arrastarComTecla = defaults.bool(forKey: Key.arrastarComTecla)
        arrastarTeclas = defaults.string(forKey: Key.arrastarTeclas) ?? TeclasDoArrasto.controleOpcao.rawValue
        arrastarRedimensiona = defaults.bool(forKey: Key.arrastarRedimensiona)
        cliquesNoDock = defaults.bool(forKey: Key.cliquesNoDock)
        ilhaControl = defaults.bool(forKey: Key.ilha)
        ilhaAbrirAoPairar = defaults.double(forKey: Key.ilhaAbrirAoPairar)
        ilhaCombinar = defaults.bool(forKey: Key.ilhaCombinar)
        ilhaSomDoTimer = defaults.bool(forKey: Key.ilhaSomDoTimer)
        ilhaOrdem = defaults.stringArray(forKey: Key.ilhaOrdem) ?? []
        ilhaLetra = defaults.bool(forKey: Key.ilhaLetra)
        ilhaNotificacoes = defaults.bool(forKey: Key.ilhaNotificacoes)
        ilhaAvisoAgentes = defaults.bool(forKey: Key.ilhaAvisoAgentes)
        ilhaAvisoBateria = defaults.bool(forKey: Key.ilhaAvisoBateria)
        ilhaAvisoFones = defaults.bool(forKey: Key.ilhaAvisoFones)
        ilhaAvisoVolume = defaults.bool(forKey: Key.ilhaAvisoVolume)
        ilhaAvisoBrilho = defaults.bool(forKey: Key.ilhaAvisoBrilho)
        ilhaAvisoCopiado = defaults.bool(forKey: Key.ilhaAvisoCopiado)
        ilhaAvisoAgentesMinutos = defaults.double(forKey: Key.ilhaAvisoAgentesMinutos)
        ilhaEqualizadorAoVivo = defaults.bool(forKey: Key.ilhaEqualizadorAoVivo)
        ilhaOcultas = defaults.stringArray(forKey: Key.ilhaOcultas) ?? []
        ilhaBotoesEsquerda = defaults.stringArray(forKey: Key.ilhaBotoesEsquerda)
            ?? Ilha.BotaoLateral.esquerdaPadrao.map(\.rawValue)
        ilhaBotoesDireita = defaults.stringArray(forKey: Key.ilhaBotoesDireita)
            ?? Ilha.BotaoLateral.direitaPadrao.map(\.rawValue)
        previaDoDock = defaults.bool(forKey: Key.previaDoDock)
        previaDoDockMiniaturas = defaults.bool(forKey: Key.previaDoDockMiniaturas)
        previaDoDockAtraso = defaults.double(forKey: Key.previaDoDockAtraso)
        acaoNoCliqueDoDock = defaults.string(forKey: Key.acaoNoCliqueDoDock) ?? AcaoNoCliqueDoDock.minimizar.rawValue
        alternadorControl = defaults.bool(forKey: Key.alternador)
        alternadorJanelas = defaults.bool(forKey: Key.alternadorJanelas)
        alternadorPrevias = defaults.bool(forKey: Key.alternadorPrevias)
        alternadorSoTela = defaults.bool(forKey: Key.alternadorSoTela)
        alternadorSemJanela = defaults.bool(forKey: Key.alternadorSemJanela)
        mouseControl = defaults.bool(forKey: Key.mouse)
        mouseInverterVertical = defaults.bool(forKey: Key.mouseInverterV)
        mouseInverterHorizontal = defaults.bool(forKey: Key.mouseInverterH)
        mouseLinhas = defaults.integer(forKey: Key.mouseLinhas)
        mouseSuave = defaults.bool(forKey: Key.mouseSuave)
        mouseDeLado = defaults.integer(forKey: Key.mouseDeLado)
        mouseBotoes = defaults.bool(forKey: Key.mouseBotoes)
        mouseIgnorados = defaults.stringArray(forKey: Key.mouseIgnorados) ?? []
        capturaControl = defaults.bool(forKey: Key.captura)
        formatoDeCor = defaults.string(forKey: Key.formatoDeCor) ?? FormatoDeCor.hex.rawValue
        capturaNaMesa = defaults.bool(forKey: Key.capturaNaMesa)
        capturaEditar = defaults.bool(forKey: Key.capturaEditar)
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
        // didSet não dispara no init: a leitura gravada liga a coleta aqui
        MonitorModelo.shared.interesse("barra", leituraDaBarra != .nenhuma)
        // idem para o vigia da área de transferência — mas fora do init:
        // ele lê o próprio store, que ainda está nascendo
        DispatchQueue.main.async {
            DockaStore.shared.sincronizarClipboard()
            HistoricoModelo.shared.vigiarBloqueio(DockaStore.shared.apagarAoBloquear)
            AlternadorController.shared.ligar(DockaStore.shared.alternadorControl)
            MouseController.shared.sincronizar()
            GatilhosController.shared.sincronizar()
            ArrastoDeJanelas.shared.sincronizar()
            DockaStore.shared.sincronizarJanelasEDock()
        }
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
