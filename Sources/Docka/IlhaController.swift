import SwiftUI
import AppKit
import DockaCore

/// A Ilha Dinâmica: uma forma preta em volta do recorte da câmera (ou
/// simulada no meio do topo, em telas sem recorte).
///
/// Um painel transparente fixo no topo da tela, do tamanho da ilha aberta com
/// os botões dos lados; dentro dele a forma cresce e encolhe com animação.
/// Fora da forma o painel ignora o mouse — o clique na barra de menus passa
/// direto. O cursor é lido trinta vezes por segundo: é só comparar números,
/// e é o que deixa a ilha crescer antes mesmo do clique.
final class IlhaController {
    static let shared = IlhaController()

    let estado = IlhaEstado()
    private var panel: PainelDaIlha?
    private var vigia = Ilha.Vigia()
    private var relogio: Timer?
    private var monitorDeClique: Any?
    private var observadorDeTelas: NSObjectProtocol?
    private var tiques = 0
    /// O `changeCount` da área de arrasto no momento em que o botão desceu:
    /// se mudar com o botão ainda apertado, há algo sendo arrastado.
    private var arrastoNoClique: Int?
    private var store: DockaStore { .shared }

    /// Altura do conteúdo da ilha aberta, abaixo do recorte, por seção.
    static func alturaDoConteudo(_ secao: Ilha.Secao?, volume: Bool) -> CGFloat {
        if volume { return 76 }
        switch secao {
        case nil:          return 248
        case .timer:       return 124
        case .controles:   return 150
        case .sistema:     return 166
        case .arquivos:    return 124
        case .rascunho:    return 200
        case .capturas:    return 144
        case .downloads:   return 168
        case .musica:      return DockaStore.shared.ilhaLetra ? 150 : 116
        case .calendario:  return 200
        case .mixer:       return 170
        case .notificacoes: return 196
        case .camera:      return 184
        case .agentes:     return 168
        default:           return 124
        }
    }
    static let alturaMaxima: CGFloat = 248
    static let margem: CGFloat = 28

    func sincronizar() {
        if store.ilhaControl { ligar() } else { desligar() }
    }

    private func ligar() {
        guard panel == nil else { reposicionar(); return }
        let p = PainelDaIlha(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // acima da barra de menus, que mora no nível dela
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel = p
        reposicionar()
        let hv = NSHostingView(rootView: VistaDaIlha(acoes: acoes).environmentObject(estado)
            .environmentObject(DockaStore.shared))
        // o tamanho é o do painel, fixo: o SwiftUI não redimensiona a janela
        hv.sizingOptions = []
        p.contentView = ConteinerDaIlha(conteudo: hv, entrou: { [weak self] in self?.arrastoEntrou() },
                                        saiu: { [weak self] in self?.estado.alvo = false })
        p.aoEsc = { [weak self] in guard let self else { return }; self.aplicar(self.vigia.fechar()) }
        ArquivosDaIlhaModelo.shared.observarDownloads(!store.ilhaOcultas.contains(Ilha.Secao.downloads.rawValue))
        MusicaModelo.shared.ligar(!store.ilhaOcultas.contains(Ilha.Secao.musica.rawValue))
        AgentesModelo.shared.aoTerminar = { [weak self] agente, projeto, duracao in
            self?.avisar("\(agente) terminou em \(projeto) · \(AgentesDaIlha.duracao(duracao))", secao: .agentes)
        }
        AgentesModelo.shared.ligar(!store.ilhaOcultas.contains(Ilha.Secao.agentes.rawValue))
        AvisosRapidosModelo.shared.aoAvisar = { [weak self] in self?.atualizarAtividades(Date()) }
        AvisosRapidosModelo.shared.ligar(true)
        p.setFrame(estado.quadroDoPainel, display: true)
        p.orderFrontRegardless()

        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tique() }
        RunLoop.main.add(t, forMode: .common)
        relogio = t
        monitorDeClique = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.cliqueFora()
        }
        observadorDeTelas = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reposicionar()
        }
    }

    private func desligar() {
        relogio?.invalidate(); relogio = nil
        ArquivosDaIlhaModelo.shared.observarDownloads(false)
        MusicaModelo.shared.ligar(false)
        AgentesModelo.shared.ligar(false)
        AvisosRapidosModelo.shared.ligar(false)
        MixerModelo.shared.desfazerTudo()
        if panel?.isKeyWindow == true { panel?.resignKey() }
        if let m = monitorDeClique { NSEvent.removeMonitor(m) }
        monitorDeClique = nil
        if let o = observadorDeTelas { NotificationCenter.default.removeObserver(o) }
        observadorDeTelas = nil
        panel?.orderOut(nil)
        panel = nil
        vigia = Ilha.Vigia()
        estado.estado = .fechada
    }

    /// A tela com recorte, se houver; senão a principal.
    private func tela() -> NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.screens.first
    }

    private func reposicionar() {
        guard let p = panel, let t = tela() else { return }
        let geo = Ilha.Geometria(tela: t.frame, areaEsquerda: t.auxiliaryTopLeftArea,
                                 areaDireita: t.auxiliaryTopRightArea,
                                 alturaDaBarra: t.frame.maxY - t.visibleFrame.maxY)
        let quadro = Self.quadroDoPainel(geo)
        estado.geometria = geo
        estado.quadroDoPainel = quadro
        p.setFrame(quadro, display: true)
    }

    /// O painel: a ilha aberta no tamanho máximo, os botões dos lados e uma
    /// margem para a sombra.
    static func quadroDoPainel(_ geo: Ilha.Geometria) -> CGRect {
        let aberta = geo.aberta(altura: alturaMaxima)
        let lado = Ilha.Geometria.vaoDosBotoes + Ilha.Geometria.botao + margem
        return CGRect(x: aberta.minX - lado, y: aberta.minY - margem,
                      width: aberta.width + 2 * lado, height: aberta.height + margem)
    }

    // MARK: o tique

    private func tique() {
        guard let p = panel else { return }
        let agora = Date()
        tiques += 1

        // o timer anda mesmo com a ilha fechada
        if let terminou = estado.timer.conferir(em: agora) { timerTerminou(terminou) }
        if estado.avisoAte.map({ agora > $0 }) == true { estado.avisoAte = nil; estado.aviso = nil }
        let rapido = estado.estado == .aberta && estado.timer.modo == .cronometro && estado.timer.rodando
        if estado.timer.ativo && (rapido ? tiques % 3 == 0 : tiques % 15 == 0) { estado.agora = agora }
        // a agenda é relida uma vez por minuto, para o aviso do próximo compromisso
        if tiques % 1800 == 1, !store.ilhaOcultas.contains(Ilha.Secao.calendario.rawValue) {
            CalendarioModelo.shared.atualizar()
        }
        // um aviso rápido vencido sai das asas sem esperar o meio segundo
        if tiques % 5 == 0, !AvisosRapidosModelo.shared.lista.isEmpty { atualizarAtividades(agora) }
        if tiques % 15 == 0 {
            ArquivosDaIlhaModelo.shared.lerProgressos()
            atualizarAtividades(agora)
        }
        // com a seção à vista, as pastas são relidas de vez em quando
        if tiques % 90 == 0, estado.estado == .aberta {
            if estado.secao == .capturas { ArquivosDaIlhaModelo.shared.atualizarCapturas() }
            if estado.secao == .downloads { ArquivosDaIlhaModelo.shared.atualizarDownloads() }
        }
        focoDoTeclado(p)

        let loc = NSEvent.mouseLocation
        vigiarArrasto(loc)
        let sobre = zonaInterativa().contains(loc)
        // botão apertado com a ilha aberta (arrastando a régua do timer, por
        // exemplo) ou aviso na tela: ela não fecha sozinha
        let fixada = (estado.estado == .aberta && NSEvent.pressedMouseButtons != 0) || estado.aviso != nil
            || (estado.secao == .rascunho && p.isKeyWindow)
        let espera: TimeInterval? = store.ilhaAbrirAoPairar > 0 ? store.ilhaAbrirAoPairar : nil
        aplicar(vigia.leu(sobreAIlha: sobre, em: agora, abrirAoPairar: espera, fixada: fixada))
        if p.ignoresMouseEvents == sobre { p.ignoresMouseEvents = !sobre }
    }

    /// Onde o cursor conta como "sobre a ilha": a forma do estado atual, com
    /// uma folga, e o topo da tela incluído (encostar no alto também vale).
    private func zonaInterativa() -> CGRect {
        let g = estado.geometria
        let r: CGRect
        switch estado.estado {
        case .fechada, .pairando:
            r = (estado.atividades.isEmpty ? g.pairando : g.compacta).insetBy(dx: -4, dy: -4)
        case .aberta:
            // a área da grade inteira, mesmo com uma seção mais baixa à vista:
            // quem clica num bloco da última fileira fica com o cursor abaixo
            // da seção que abriu — e a ilha fecharia debaixo dele
            let altura = max(Self.alturaDoConteudo(estado.secao, volume: estado.volumeAberto),
                             Self.alturaDoConteudo(nil, volume: false))
            let a = g.aberta(altura: altura)
            let lado = Ilha.Geometria.vaoDosBotoes + Ilha.Geometria.botao
            r = a.insetBy(dx: -lado - 6, dy: -10)
        }
        return CGRect(x: r.minX, y: r.minY, width: r.width, height: g.recorte.maxY + 4 - r.minY)
    }

    private func aplicar(_ acao: Ilha.Vigia.Acao) {
        switch acao {
        case .nada: break
        case .pairar: estado.estado = .pairando
        case .recolher: estado.estado = .fechada
        case .abrir:
            estado.estado = .aberta
        case .fechar:
            estado.estado = .fechada
            estado.volumeAberto = false
        }
    }

    private func cliqueFora() {
        guard estado.estado == .aberta, !zonaInterativa().contains(NSEvent.mouseLocation) else { return }
        aplicar(vigia.fechar())
    }

    /// O Rascunho precisa do teclado: com ele à vista, o painel vira a
    /// janela-chave (sem ativar o Docka — o app da frente continua na
    /// frente). Fora dele, devolve o teclado na hora.
    private func focoDoTeclado(_ p: NSPanel) {
        let quer = estado.estado == .aberta && estado.secao == .rascunho
        if quer && !p.isKeyWindow { p.makeKey() }
        if !quer && p.isKeyWindow {
            NotasModelo.shared.gravarAgora()
            p.resignKey()
        }
    }

    /// Um arquivo sendo arrastado chegando perto do recorte abre a ilha antes
    /// de ele encostar no topo da tela — lá em cima, parado, o macOS abre o
    /// Mission Control (foi o que o teste mostrou).
    private func vigiarArrasto(_ loc: CGPoint) {
        let apertado = NSEvent.pressedMouseButtons & 1 != 0
        let area = NSPasteboard(name: .drag).changeCount
        if !apertado { arrastoNoClique = nil; return }
        if arrastoNoClique == nil { arrastoNoClique = area; return }
        guard area != arrastoNoClique, estado.estado != .aberta,
              !ArquivosDaIlhaModelo.shared.estadoDeArrasto.arrastandoParaFora else { return }
        let c = estado.geometria.compacta
        let aproximacao = CGRect(x: c.minX - 120, y: c.minY - 110, width: c.width + 240, height: c.height + 110)
        if aproximacao.contains(loc) { arrastoEntrou() }
    }

    /// Algo sendo arrastado chegou à ilha: ela abre em Arquivos, pronta para
    /// receber.
    private func arrastoEntrou() {
        estado.alvo = true
        guard !ArquivosDaIlhaModelo.shared.estadoDeArrasto.arrastandoParaFora else { return }
        estado.secao = .arquivos
        estado.volumeAberto = false
        if estado.estado != .aberta { aplicar(vigia.abrir()) }
    }

    private func atualizarAtividades(_ agora: Date) {
        var lista: [Ilha.Atividade] = []
        if let a = estado.timer.atividade(em: agora) { lista.append(a) }
        if let a = ArquivosDaIlhaModelo.shared.atividade { lista.append(a) }
        if let a = MusicaModelo.shared.atividade { lista.append(a) }
        if let a = CalendarioModelo.shared.atividade { lista.append(a) }
        if let a = AgentesModelo.shared.atividade { lista.append(a) }
        lista += AvisosRapidosModelo.shared.vivas()
        let visiveis = Ilha.visiveis(lista, combinar: store.ilhaCombinar, escolhida: estado.escolhida)
        if visiveis != estado.atividades { estado.atividades = visiveis }
    }

    private func timerTerminou(_ fase: TimerDaIlha.FaseDoPomodoro) {
        let texto: String
        switch estado.timer.modo {
        case .pomodoro: texto = fase == .foco ? "Fim do foco — hora da pausa" : "Fim da pausa — de volta ao foco"
        default:        texto = "O timer terminou"
        }
        avisar(texto, secao: .timer, som: store.ilhaSomDoTimer)
    }

    /// A ilha abre com um aviso, toca um som e fecha sozinha depois.
    func avisar(_ texto: String, secao: Ilha.Secao, som: Bool = true) {
        guard panel != nil else { return }
        if som { NSSound(named: "Glass")?.play() }
        estado.aviso = texto
        estado.avisoAte = Date().addingTimeInterval(6)
        estado.secao = secao
        estado.volumeAberto = false
        aplicar(vigia.abrir())
        atualizarAtividades(Date())
    }

    // MARK: ações (vindas da vista e dos atalhos)

    private lazy var acoes = AcoesDaIlha(
        clicar: { [weak self] in self?.clicouNaIlha() },
        irPara: { [weak self] s in self?.irPara(s) },
        voltar: { [weak self] in self?.estado.secao = nil; self?.estado.volumeAberto = false },
        botao: { [weak self] b in self?.botaoLateral(b) },
        timer: { [weak self] mudar in
            guard let self else { return }
            mudar(&self.estado.timer, Date())
            self.estado.agora = Date()
            self.atualizarAtividades(Date())
        },
        dispensarAviso: { [weak self] in self?.estado.aviso = nil; self?.estado.avisoAte = nil },
        escolherAtividade: { [weak self] id in
            self?.estado.escolhida = id
            self?.atualizarAtividades(Date())
        },
        fechar: { [weak self] in guard let self else { return }; self.aplicar(self.vigia.fechar()) }
    )

    /// Clique na ilha fechada: abre na seção da atividade que está nas asas
    /// (o timer abre o timer), ou na grade.
    private func clicouNaIlha() {
        if estado.estado != .aberta {
            switch estado.atividades.first?.tipo {
            case .timer, .pomodoro, .cronometro: estado.secao = .timer
            case .download: estado.secao = .downloads
            case .musica: estado.secao = .musica
            case .calendario: estado.secao = .calendario
            case .agente: estado.secao = .agentes
            default: estado.secao = nil
            }
            estado.volumeAberto = false
        }
        aplicar(vigia.clicou())
    }

    private func irPara(_ s: Ilha.Secao) {
        guard s.disponivel else { return }
        estado.secao = s
        estado.volumeAberto = false
    }

    private func botaoLateral(_ b: Ilha.BotaoLateral) {
        switch b {
        case .inicio:  estado.secao = nil; estado.volumeAberto = false
        case .timer:   irPara(.timer)
        case .volume:  estado.volumeAberto.toggle()
        case .ajustes:
            aplicar(vigia.fechar())
            store.secaoDosAjustesPedida = "ilha"
            SettingsWindowController.shared.show()
        case .agentes: irPara(.agentes)
        }
    }

    /// Atalho global: abre na grade (ou na seção pedida); de novo, fecha.
    func atalho(_ secao: Ilha.Secao?) {
        guard panel != nil else { return }
        if estado.estado == .aberta, estado.secao == secao { aplicar(vigia.fechar()); return }
        estado.secao = secao.flatMap { $0.disponivel ? $0 : nil }
        estado.volumeAberto = false
        aplicar(vigia.abrir())
    }
}

/// O painel da ilha: pode virar a janela-chave (para os campos de texto das
/// próximas seções) sem tirar o foco do app da frente.
final class PainelDaIlha: NSPanel {
    var aoEsc: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { aoEsc?() }
    /// A ilha mora em cima da barra de menus: sem isto, o AppKit empurra a
    /// janela para fora dela — e ela ia parar acima da tela.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class IlhaEstado: ObservableObject {
    @Published var estado: Ilha.Estado = .fechada
    /// nil: a grade de seções.
    @Published var secao: Ilha.Secao?
    @Published var volumeAberto = false
    @Published var atividades: [Ilha.Atividade] = []
    @Published var escolhida: String?
    @Published var timer = TimerDaIlha()
    /// O relógio das vistas — só muda quando há algo correndo.
    @Published var agora = Date()
    @Published var aviso: String?
    /// Algo sendo arrastado está sobre a ilha.
    @Published var alvo = false
    var avisoAte: Date?
    var geometria = Ilha.Geometria(recorte: CGRect(x: 0, y: 0, width: 190, height: 32), temRecorte: false)
    var quadroDoPainel: CGRect = .zero
}

struct AcoesDaIlha {
    let clicar: () -> Void
    let irPara: (Ilha.Secao) -> Void
    let voltar: () -> Void
    let botao: (Ilha.BotaoLateral) -> Void
    let timer: (_ mudar: (inout TimerDaIlha, Date) -> Void) -> Void
    let dispensarAviso: () -> Void
    let escolherAtividade: (String) -> Void
    var fechar: () -> Void = {}
}

// MARK: - A forma

/// Retângulo com os cantos de baixo arredondados e, em cima, duas "orelhas"
/// côncavas que fazem a ilha nascer da borda da tela como o recorte nasce.
struct FormaDaIlha: Shape {
    var raio: CGFloat
    var orelha: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(raio, orelha) }
        set { raio = newValue.first; orelha = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let e = min(orelha, r.width / 4)
        let k = min(raio, (r.width - 2 * e) / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + e, y: r.minY + e), control: CGPoint(x: r.minX + e, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + e, y: r.maxY - k))
        p.addQuadCurve(to: CGPoint(x: r.minX + e + k, y: r.maxY), control: CGPoint(x: r.minX + e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e - k, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - e, y: r.maxY - k), control: CGPoint(x: r.maxX - e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - e, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - A vista

struct VistaDaIlha: View {
    let acoes: AcoesDaIlha
    @EnvironmentObject var e: IlhaEstado
    @EnvironmentObject var store: DockaStore

    private var g: Ilha.Geometria { e.geometria }
    private var aberta: Bool { e.estado == .aberta }

    /// O corpo da ilha no estado atual, em coordenadas do AppKit.
    private var corpo: CGRect {
        switch e.estado {
        case .fechada:  return e.atividades.isEmpty ? g.recorte : g.compacta
        case .pairando:
            return e.atividades.isEmpty ? g.pairando
                : g.compacta.insetBy(dx: -Ilha.Geometria.crescimento.width / 2, dy: 0)
        case .aberta:
            return g.aberta(altura: IlhaController.alturaDoConteudo(e.secao, volume: e.volumeAberto))
        }
    }

    /// AppKit (origem embaixo) → SwiftUI (origem em cima), dentro do painel.
    private func local(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - e.quadroDoPainel.minX, y: e.quadroDoPainel.maxY - r.maxY,
               width: r.width, height: r.height)
    }

    var body: some View {
        let c = local(corpo)
        let orelha: CGFloat = aberta ? 14 : 7
        ZStack(alignment: .topLeading) {
            FormaDaIlha(raio: aberta ? 28 : min(11, c.height / 2.6), orelha: orelha)
                .fill(Color.black)
                .shadow(color: .black.opacity(aberta ? 0.35 : 0), radius: 14, y: 6)
                .frame(width: c.width + 2 * orelha, height: c.height)
                .offset(x: c.minX - orelha, y: c.minY)

            conteudo
                .frame(width: c.width, height: c.height, alignment: .top)
                .clipShape(FormaDaIlha(raio: aberta ? 28 : 11, orelha: 0))
                .offset(x: c.minX, y: c.minY)

            if aberta { botoesLaterais.transition(.opacity) }
        }
        .frame(width: e.quadroDoPainel.width, height: e.quadroDoPainel.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: e.estado)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: e.secao)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: e.volumeAberto)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: e.atividades.map(\.id))
    }

    @ViewBuilder
    private var conteudo: some View {
        if aberta {
            VStack(spacing: 0) {
                cabecalho
                Group {
                    if let aviso = e.aviso { AvisoDaIlha(texto: aviso, ok: acoes.dispensarAviso) }
                    else if e.volumeAberto { VolumeDaIlha() }
                    else if let s = e.secao { secao(s) }
                    else { GradeDaIlha(irPara: acoes.irPara) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
            .transition(.opacity)
        } else {
            Button(action: acoes.clicar) {
                AsasDaIlha(atividades: e.atividades, larguraDoRecorte: g.recorte.width, agora: e.agora)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ilha Dinâmica")
        }
    }

    /// A faixa do recorte: título e voltar à esquerda dele, menu à direita.
    private var cabecalho: some View {
        let lado = (corpo.width - g.recorte.width) / 2
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                if e.secao != nil || e.volumeAberto {
                    Button(action: acoes.voltar) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voltar à grade")
                }
                Text(e.volumeAberto ? "Volume" : (e.secao?.titulo ?? "Docka"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
            .frame(width: lado)
            Spacer(minLength: g.recorte.width)
            HStack {
                Spacer(minLength: 0)
                Button { acoes.botao(.ajustes) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes da ilha")
            }
            .padding(.trailing, 16)
            .frame(width: lado)
        }
        .foregroundStyle(.white)
        .frame(height: g.recorte.height)
    }

    @ViewBuilder
    private func secao(_ s: Ilha.Secao) -> some View {
        switch s {
        case .timer:     TimerDaIlhaView(mudar: acoes.timer)
        case .controles: ControlesDaIlha(fechar: acoes.fechar)
        case .sistema:   SistemaDaIlha()
        case .arquivos:  ArquivosDaIlhaView(alvo: e.alvo)
        case .rascunho:  RascunhoDaIlha()
        case .capturas:  CapturasDaIlha(agora: Date())
        case .downloads: DownloadsDaIlha(agora: Date())
        case .musica:    TocandoAgoraView()
        case .calendario: CalendarioDaIlhaView()
        case .mixer:     MixerDaIlhaView()
        case .notificacoes: NotificacoesDaIlhaView()
        case .camera:    CameraDaIlhaView()
        case .agentes:   AgentesDaIlhaView()
        default:         Text("Em breve").foregroundStyle(.secondary)
        }
    }

    /// Os botões redondos fora da ilha, dos dois lados.
    private var botoesLaterais: some View {
        let a = corpo
        let esquerda = store.ilhaBotoesEsquerda.compactMap(Ilha.BotaoLateral.init(rawValue:)).filter(\.disponivel)
        let direita = store.ilhaBotoesDireita.compactMap(Ilha.BotaoLateral.init(rawValue:)).filter(\.disponivel)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(esquerda.enumerated()), id: \.element) { i, b in
                botao(b).offset(x: local(g.botao(i, esquerda: true, aberta: a)).minX,
                                y: local(g.botao(i, esquerda: true, aberta: a)).minY)
            }
            ForEach(Array(direita.enumerated()), id: \.element) { i, b in
                botao(b).offset(x: local(g.botao(i, esquerda: false, aberta: a)).minX,
                                y: local(g.botao(i, esquerda: false, aberta: a)).minY)
            }
        }
    }

    private func botao(_ b: Ilha.BotaoLateral) -> some View {
        let ativo = (b == .timer && e.secao == .timer) || (b == .volume && e.volumeAberto)
            || (b == .inicio && e.secao == nil && !e.volumeAberto)
        return Button { acoes.botao(b) } label: {
            Image(systemName: b.simbolo)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ativo ? Color.black : Color.white)
                .frame(width: Ilha.Geometria.botao, height: Ilha.Geometria.botao)
                .background(Circle().fill(ativo ? Color.white : Color.black))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(b.titulo)
    }
}

// MARK: - Asas (atividades com a ilha fechada)

private struct AsasDaIlha: View {
    let atividades: [Ilha.Atividade]
    let larguraDoRecorte: CGFloat
    let agora: Date

    var body: some View {
        HStack(spacing: 0) {
            asa(esquerda: true).frame(maxWidth: .infinity)
            Color.clear.frame(width: larguraDoRecorte)
            asa(esquerda: false).frame(maxWidth: .infinity)
        }
        .opacity(atividades.isEmpty ? 0 : 1)
    }

    /// Uma atividade: ícone à esquerda e valor à direita. Duas combinadas:
    /// cada uma numa asa, com ícone e valor.
    @ViewBuilder
    private func asa(esquerda: Bool) -> some View {
        if atividades.count >= 2, atividades[esquerda ? 0 : 1].tipo == .musica {
            HStack(spacing: 6) {
                AsaDaMusica(esquerda: true, compacta: true)
                AsaDaMusica(esquerda: false, compacta: true)
            }
        } else if let a = atividades.first, atividades.count == 1, a.tipo == .musica {
            AsaDaMusica(esquerda: esquerda)
                .frame(maxWidth: .infinity, alignment: esquerda ? .leading : .trailing)
                .padding(esquerda ? .leading : .trailing, 12)
        } else if atividades.count >= 2 {
            let a = atividades[esquerda ? 0 : 1]
            HStack(spacing: 4) {
                Image(systemName: a.simbolo).foregroundStyle(cor(a))
                Text(a.valor).foregroundStyle(cor(a)).monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold))
        } else if let a = atividades.first, a.tipo == .nivel || a.tipo == .bateria, let p = a.progresso {
            if esquerda {
                Image(systemName: a.simbolo).font(.system(size: 12, weight: .semibold)).foregroundStyle(cor(a))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            } else {
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(cor(a)).frame(width: 34 * CGFloat(min(1, max(0, p))))
                    }
                    .frame(width: 34, height: 4)
                    Text(a.valor).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(cor(a))
                }
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 12)
            }
        } else if let a = atividades.first {
            if esquerda {
                Image(systemName: a.simbolo).font(.system(size: 12, weight: .semibold)).foregroundStyle(cor(a))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            } else {
                Text(a.valor).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(cor(a))
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
            }
        }
    }

    private func cor(_ a: Ilha.Atividade) -> Color {
        switch a.tipo {
        case .timer, .cronometro: return .orange
        case .pomodoro:           return Color(red: 1, green: 0.42, blue: 0.36)
        case .download:           return .blue
        case .musica:             return .pink
        case .calendario:         return .red
        case .agente:             return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .bateria:            return .green
        case .nivel:              return .white
        case .aviso:              return .yellow
        }
    }
}

// MARK: - Grade de seções

private struct GradeDaIlha: View {
    let irPara: (Ilha.Secao) -> Void
    @EnvironmentObject var store: DockaStore

    private let colunas = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        let ocultas = Set(store.ilhaOcultas)
        let secoes = Ilha.ordem(gravada: store.ilhaOrdem).filter { !ocultas.contains($0.rawValue) }
        LazyVGrid(columns: colunas, spacing: 8) {
            ForEach(secoes) { s in
                Button { irPara(s) } label: { bloco(s) }
                    .buttonStyle(.plain)
                    .disabled(!s.disponivel)
                    .accessibilityLabel(s.disponivel ? s.titulo : "\(s.titulo), em breve")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func bloco(_ s: Ilha.Secao) -> some View {
        VStack(spacing: 4) {
            Image(systemName: s.simbolo)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(cor(s))
                .frame(height: 22)
            Text(s.titulo).font(.system(size: 10.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            Text(rotuloDoAtalho(s)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
        .opacity(s.disponivel ? 1 : 0.35)
        .contentShape(Rectangle())
    }

    private func rotuloDoAtalho(_ s: Ilha.Secao) -> String {
        if !s.disponivel { return "em breve" }
        return store.atalho(de: .secaoDaIlha(s))?.display ?? " "
    }

    private func cor(_ s: Ilha.Secao) -> Color {
        switch s {
        case .musica:     return .pink
        case .calendario: return .red
        case .timer:      return .orange
        default:          return .white
        }
    }
}

// MARK: - Aviso e volume

private struct AvisoDaIlha: View {
    let texto: String
    let ok: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.badge.fill").font(.system(size: 24)).foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating)
            Text(texto).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            Button(action: ok) {
                Text("OK").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }
}

private struct VolumeDaIlha: View {
    @State private var nivel: Double = VolumeBackend.ler() ?? 0.5

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: nivel <= 0.001 ? "speaker.slash.fill" : "speaker.fill").foregroundStyle(.white)
            ReguaDaIlha(valor: nivel, cor: .white) { v in
                nivel = v
                _ = VolumeBackend.escrever(v)
            }
            .frame(height: 22)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.white)
            Text("\(Int((nivel * 100).rounded()))%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white).frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }
}

/// Uma barra arrastável (0…1). Feita no AppKit: no painel sem foco, o gesto
/// do SwiftUI não recebe eventos (ver o ArrastoAppKit).
struct ReguaDaIlha: View {
    let valor: Double
    var cor: Color = .orange
    let mudou: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                Capsule().fill(cor).frame(width: max(6, geo.size.width * valor), height: 6)
                Circle().fill(Color.white).frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: (geo.size.width - 16) * valor)
            }
            .frame(maxHeight: .infinity)
            .overlay(ToqueAbsolutoAppKit { x in mudou(min(1, max(0, x / max(1, geo.size.width)))) })
        }
    }
}

/// Clique e arrasto que informam a posição absoluta (em pontos, da esquerda)
/// — para réguas: tocar num ponto leva o valor até ali.
struct ToqueAbsolutoAppKit: NSViewRepresentable {
    let aoMover: (CGFloat) -> Void

    final class V: NSView {
        var aoMover: ((CGFloat) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with e: NSEvent) { informar(e) }
        override func mouseDragged(with e: NSEvent) { informar(e) }
        private func informar(_ e: NSEvent) { aoMover?(convert(e.locationInWindow, from: nil).x) }
    }

    func makeNSView(context: Context) -> NSView {
        // sem fundo próprio: fica sempre sobre o preto opaco da ilha, que já
        // segura o clique (pixel transparente deixaria o clique atravessar)
        let v = V()
        v.aoMover = aoMover
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? V)?.aoMover = aoMover }
}

// MARK: - Autoteste

/// `--ilha-selftest`: desenha a ilha fora da tela em cada estado e grava um
/// PNG de cada — sem abrir painel nenhum na tela de verdade.
enum IlhaAutoteste {
    static func rodar(pasta: String) -> String {
        let geo = Ilha.Geometria(tela: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                                 areaEsquerda: CGRect(x: 0, y: 1074.5, width: 751, height: 37.5),
                                 areaDireita: CGRect(x: 959, y: 1074.5, width: 751, height: 37.5),
                                 alturaDaBarra: 38)
        let quadro = IlhaController.quadroDoPainel(geo)
        let agora = Date()
        func cena(_ nome: String, _ preparar: (IlhaEstado) -> Void) -> String {
            let e = IlhaEstado()
            e.geometria = geo
            e.quadroDoPainel = quadro
            e.agora = agora
            preparar(e)
            let acoes = AcoesDaIlha(clicar: {}, irPara: { _ in }, voltar: {}, botao: { _ in },
                                    timer: { _ in }, dispensarAviso: {}, escolherAtividade: { _ in })
            let fundo = LinearGradient(colors: [Color(red: 0.55, green: 0.62, blue: 0.75),
                                                Color(red: 0.85, green: 0.6, blue: 0.45)],
                                       startPoint: .top, endPoint: .bottom)
            let v = ZStack(alignment: .top) {
                fundo
                // a faixa da barra de menus e o recorte de verdade, para comparar
                Rectangle().fill(Color.white.opacity(0.25)).frame(height: geo.recorte.height)
                VistaDaIlha(acoes: acoes).environmentObject(e).environmentObject(DockaStore.shared)
            }
            .frame(width: quadro.width, height: quadro.height)
            let hv = NSHostingView(rootView: v)
            let janela = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: quadro.width, height: quadro.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            janela.contentView = hv
            for _ in 0..<10 {
                hv.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            guard let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds) else { return "FALHOU — \(nome)" }
            hv.cacheDisplay(in: hv.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(pasta)/\(nome).png"))
            janela.contentView = nil
            return "OK — \(nome).png"
        }
        var timer = TimerDaIlha()
        timer.iniciar(em: agora.addingTimeInterval(-60))
        let ativ = timer.atividade(em: agora)!
        let musica = Ilha.Atividade(id: "musica", tipo: .musica, simbolo: "music.note", valor: "3:12", prioridade: 40)
        return [
            cena("ilha-fechada-timer") { $0.atividades = [ativ] },
            cena("ilha-combinada") { $0.atividades = [ativ, musica] },
            cena("ilha-pairando") { $0.estado = .pairando },
            cena("ilha-grade") { $0.estado = .aberta },
            cena("ilha-timer-parado") { $0.estado = .aberta; $0.secao = .timer },
            cena("ilha-timer-correndo") { $0.estado = .aberta; $0.secao = .timer; $0.timer = timer },
            cena("ilha-pomodoro") { e in
                e.estado = .aberta; e.secao = .timer
                var p = TimerDaIlha(); p.modo = .pomodoro
                e.timer = p
            },
            cena("ilha-cronometro") { e in
                e.estado = .aberta; e.secao = .timer
                var c = TimerDaIlha(); c.modo = .cronometro
                c.alternarCronometro(em: agora.addingTimeInterval(-75.4)); c.volta(em: agora.addingTimeInterval(-20))
                e.timer = c
            },
            cena("ilha-volume") { $0.estado = .aberta; $0.volumeAberto = true },
            cena("ilha-aviso") { $0.estado = .aberta; $0.secao = .timer; $0.aviso = "O timer terminou" },
            cena("ilha-controles") { $0.estado = .aberta; $0.secao = .controles },
            cena("ilha-calendario") { e in
                let cal = Calendar.current
                let h = cal.startOfDay(for: agora)
                func ev(_ id: String, _ t: String, _ i: Double, _ f: Double, _ cor: String, todo: Bool = false,
                        reuniao: String? = nil, local: String? = nil) -> CalendarioDaIlha.Evento {
                    .init(id: id, titulo: t, inicio: h.addingTimeInterval(i * 3600), fim: h.addingTimeInterval(f * 3600),
                          diaInteiro: todo, local: local, cor: cor, reuniao: reuniao.flatMap(URL.init(string:)))
                }
                CalendarioModelo.shared.simular([
                    ev("1", "Feriado municipal", 0, 24, "#34C759", todo: true),
                    ev("2", "Reunião de produto", 10, 11, "#0A84FF", reuniao: "https://meet.google.com/abc-defg-hij"),
                    ev("3", "Almoço com a equipe", 12.5, 13.5, "#FF9F0A", local: "Restaurante"),
                    ev("4", "Revisão do Docka", 16, 17, "#BF5AF2"),
                    ev("5", "Dentista", 24 * 3 + 9, 24 * 3 + 10, "#FF453A"),
                ])
                e.estado = .aberta; e.secao = .calendario
            },
            cena("ilha-mixer") { e in
                let ws = NSWorkspace.shared
                func app(_ id: String, _ nome: String, _ caminho: String, _ tocando: Bool) -> MixerModelo.App {
                    .init(id: id, nome: nome, icone: ws.icon(forFile: caminho), tocando: tocando, processos: [])
                }
                MixerModelo.shared.simular([
                    app("com.brave.Browser", "Brave Browser", "/Applications/Brave Browser.app", true),
                    app("com.apple.Music", "Música", "/System/Applications/Music.app", true),
                    app("com.tinyspeck.slackmacgap", "Slack", "/System/Applications/Utilities/Terminal.app", false),
                ], controles: ["com.apple.Music": 0.4, "com.tinyspeck.slackmacgap": 0])
                e.estado = .aberta; e.secao = .mixer
            },
            cena("ilha-sistema") { $0.estado = .aberta; $0.secao = .sistema },
            cena("ilha-arquivos") { $0.estado = .aberta; $0.secao = .arquivos },
            cena("ilha-arquivos-alvo") { $0.estado = .aberta; $0.secao = .arquivos; $0.alvo = true },
        ].joined(separator: "\n")
    }
}

// MARK: - Soltar arquivos na ilha

/// A raiz do painel, em AppKit, registrada para receber arquivos, links e
/// texto — o AppKit procura quem aceita a soltura subindo a partir da view
/// sob o cursor, e o SwiftUI de dentro não se registra para nada.
final class ConteinerDaIlha: NSView {
    private let entrou: () -> Void
    private let saiu: () -> Void

    init(conteudo: NSView, entrou: @escaping () -> Void, saiu: @escaping () -> Void) {
        self.entrou = entrou
        self.saiu = saiu
        super.init(frame: .zero)
        conteudo.autoresizingMask = [.width, .height]
        addSubview(conteudo)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Soltar de volta o que saiu da própria ilha não faz nada.
    private var aceita: Bool { !ArquivosDaIlhaModelo.shared.estadoDeArrasto.arrastandoParaFora }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard aceita else { return [] }
        entrou()
        return .copy
    }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { aceita ? .copy : [] }
    override func draggingExited(_ info: NSDraggingInfo?) { saiu() }
    override func draggingEnded(_ info: NSDraggingInfo) { saiu() }
    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        saiu()
        guard aceita else { return false }
        return PrateleiraModelo.shared.receber(info.draggingPasteboard)
    }
}
