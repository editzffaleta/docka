import SwiftUI
import AppKit
import DockaCore

/// O painel que abre no ícone da barra de menus: abas com ícones no topo,
/// cartões no meio, Ajustes e Encerrar embaixo.
///
/// Era um menu simples; com mais de vinte recursos, um menu vira uma lista
/// sem fim. O painel deixa cada coisa a um clique e mostra o estado de cada
/// recurso sem abrir os ajustes.
enum AbaDoPainel: String, CaseIterable, Identifiable {
    case rapido, sistema, controles, utilidades

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .rapido:     return "Rápido"
        case .sistema:    return "Sistema"
        case .controles:  return "Controles"
        case .utilidades: return "Utilidades"
        }
    }

    var simbolo: String {
        switch self {
        case .rapido:     return "bolt.fill"
        case .sistema:    return "cpu"
        case .controles:  return "switch.2"
        case .utilidades: return "wrench.and.screwdriver.fill"
        }
    }
}

/// Guarda a janela do painel para fechá-la quando uma ação abre outra coisa
/// (o histórico, o editor, o seletor de área) — senão o painel ficaria por
/// cima do que a pessoa acabou de pedir.
final class JanelaDoPainel {
    static weak var atual: NSWindow?
    static func fechar() { atual?.close() }
}

private struct CapturaDeJanela: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { JanelaDoPainel.atual = v.window }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if JanelaDoPainel.atual == nil { JanelaDoPainel.atual = nsView.window }
    }
}

struct PainelDaBarra: View {
    @EnvironmentObject var store: DockaStore
    @AppStorage("docka.abaDoPainel") private var abaGravada = AbaDoPainel.rapido.rawValue
    /// Altura FIXA da área das abas.
    ///
    /// O painel da barra cresce com o conteúdo, mas não encolhe: com altura
    /// variável, recolher um grupo deixava a janela grande e o conteúdo
    /// centralizado no meio de um vão translúcido. Fixa, a janela nunca muda
    /// de tamanho — aba curta fica com espaço embaixo, aba longa rola.
    static let alturaDasAbas: CGFloat = 440

    private var aba: AbaDoPainel { AbaDoPainel(rawValue: abaGravada) ?? .rapido }

    var body: some View {
        VStack(spacing: 10) {
            AppLogo(size: 30).padding(.top, 12)
            abas
            HStack {
                Text(aba.titulo.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            ScrollView {
                Group {
                    switch aba {
                    case .rapido:     AbaRapido()
                    case .sistema:    AbaSistema()
                    case .controles:  AbaControles()
                    case .utilidades: AbaUtilidades()
                    }
                }
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            // Altura explícita, e não só máxima: o painel se dimensiona pelo
            // tamanho ideal do conteúdo, e uma ScrollView não tem tamanho
            // ideal — com só `maxHeight` ela abria com altura zero.
            .frame(height: Self.alturaDasAbas)
            rodape
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: 340)
        .background(CapturaDeJanela())
    }

    private var abas: some View {
        HStack(spacing: 4) {
            ForEach(AbaDoPainel.allCases) { a in
                Button { abaGravada = a.rawValue } label: {
                    Image(systemName: a.simbolo)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(a == aba ? Color.accentColor : Color.secondary)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(a == aba ? Color.accentColor.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(a.titulo)
                .accessibilityLabel(a.titulo)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var rodape: some View {
        HStack(spacing: 8) {
            BotaoDoRodape(titulo: "Ajustes", simbolo: "gearshape") {
                JanelaDoPainel.fechar()
                SettingsWindowController.shared.show()
            }
            BotaoDoRodape(titulo: "Encerrar", simbolo: "power") { NSApp.terminate(nil) }
        }
    }
}

private struct BotaoDoRodape: View {
    let titulo: String
    let simbolo: String
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Label(titulo, systemImage: simbolo)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Peças comuns

/// O cartão de fundo levemente destacado, como um grupo dos Ajustes.
private struct Cartao<Conteudo: View>: View {
    @ViewBuilder let conteudo: () -> Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { conteudo() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// Uma linha com ícone, título, descrição e um interruptor.
private struct LinhaComInterruptor: View {
    let simbolo: String
    let titulo: String
    let descricao: String
    @Binding var ligado: Bool
    var aviso: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: simbolo)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 12, weight: .semibold))
                Text(descricao)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let aviso, ligado {
                    Label(aviso, systemImage: "exclamationmark.shield.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 4)
            Toggle("", isOn: $ligado)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(10)
    }
}

/// Uma linha que faz algo ao clicar: ícone, título, descrição, atalho e seta.
private struct LinhaDeAcao: View {
    let simbolo: String
    let titulo: String
    let descricao: String
    var atalho: AcaoDeAtalho? = nil
    let acao: () -> Void
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Button {
            JanelaDoPainel.fechar()
            // um instante: o painel some antes de o seletor de área ou o
            // histórico aparecerem por cima
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: acao)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: simbolo)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(.system(size: 12, weight: .semibold))
                    Text(descricao).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let atalho, let s = store.atalho(de: atalho) {
                    Text(s.display)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Separador: View {
    var body: some View { Divider().padding(.leading, 40) }
}

// MARK: - Rápido

private struct AbaRapido: View {
    @EnvironmentObject var store: DockaStore
    @ObservedObject private var acordado = AcordadoSessao.shared

    var body: some View {
        VStack(spacing: 10) {
            Cartao {
                HStack(spacing: 10) {
                    Image(systemName: acordado.ativo ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 16))
                        .foregroundStyle(acordado.ativo ? Color.accentColor : .secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manter acordado").font(.system(size: 12, weight: .semibold))
                        Text(acordado.ativo
                             ? (acordado.fim == nil ? "Ligado até você desligar" : "Faltam \(acordado.restante)")
                             : "O Mac não dorme sozinho enquanto estiver ligado")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(DuracaoAcordado.allCases) { d in
                            Button(d.titulo) { acordado.ligar(d, telaAcesa: store.acordadoTelaAcesa) }
                        }
                        if acordado.ativo {
                            Divider()
                            Button("Desligar") { acordado.desligar() }
                        }
                    } label: {
                        Text(acordado.ativo ? "Ligado" : "Ligar").font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(10)
            }

            let acoes = AcaoRapida.allCases.filter(AcoesRapidasBackend.disponivel)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(acoes) { a in
                    Button {
                        JanelaDoPainel.fechar()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { AcoesRapidasBackend.executar(a) }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: a.simbolo).font(.system(size: 15))
                            Text(AcoesRapidasBackend.titulo(a))
                                .font(.system(size: 9.5))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(a.descricao)
                }
            }

            Cartao {
                LinhaComInterruptor(simbolo: "speaker.wave.2", titulo: "Sons",
                                    descricao: "Ao revelar a bandeja e ao abrir um app",
                                    ligado: $store.soundsEnabled)
                Separador()
                LinhaComInterruptor(simbolo: "hand.point.up.left", titulo: "Pressure Zone",
                                    descricao: "A bandeja só abre empurrando o cursor contra a borda",
                                    ligado: $store.pressureZone)
                Separador()
                LinhaComInterruptor(simbolo: "power", titulo: "Abrir no login",
                                    descricao: "O Docka sobe sozinho quando você entra no Mac",
                                    ligado: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            }
        }
    }
}

// MARK: - Sistema

private struct AbaSistema: View {
    @ObservedObject private var m = MonitorModelo.shared

    var body: some View {
        VStack(spacing: 10) {
            Cartao {
                linha("CPU", Metricas.porcentagem(m.cpu), simbolo: "cpu")
                GraficoPequeno(historico: m.historicoCPU, teto: 1, cor: .blue).frame(height: 34).padding(.horizontal, 10)
                Separador().padding(.vertical, 4)
                linha("Memória", "\(Metricas.bytes(m.memoria, binario: true)) de \(Metricas.bytes(m.memoriaTotal, binario: true))",
                      simbolo: "memorychip")
                GraficoPequeno(historico: m.historicoMemoria, teto: 1, cor: .purple).frame(height: 34).padding(.horizontal, 10)
                Separador().padding(.vertical, 4)
                linha("Rede", "↓ \(Metricas.taxa(m.entrada))  ↑ \(Metricas.taxa(m.saida))", simbolo: "network")
                ZStack {
                    GraficoPequeno(historico: m.historicoEntrada, teto: nil, cor: .green)
                    GraficoPequeno(historico: m.historicoSaida, teto: nil, cor: .orange)
                }
                .frame(height: 34).padding(.horizontal, 10).padding(.bottom, 10)
            }
            Cartao {
                if let b = m.bateria {
                    linha(b.carregando ? "Carregando" : (b.naTomada ? "Na tomada" : "Bateria"),
                          Metricas.porcentagem(b.fracao) + (Metricas.tempo(minutos: b.minutos).map { " · \($0)" } ?? ""),
                          simbolo: b.carregando ? "battery.100.bolt" : "battery.75")
                    ProgressView(value: b.fracao).tint(.green).padding(.horizontal, 10).padding(.bottom, 8)
                }
                if let d = m.disco, d.total > 0 {
                    if m.bateria != nil { Separador() }
                    linha("Disco", "\(Metricas.bytes(d.livre)) livres", simbolo: "internaldrive")
                    ProgressView(value: 1 - Double(d.livre) / Double(d.total)).padding(.horizontal, 10).padding(.bottom, 10)
                }
                if m.termico.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    Separador()
                    Label(m.termico == .critical ? "Mac muito quente" : "Mac esquentando", systemImage: "thermometer.high")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange).padding(10)
                }
            }
        }
        // mede só enquanto a aba está à vista
        .onAppear { m.interesse("painelDaBarra", true) }
        .onDisappear { m.interesse("painelDaBarra", false) }
    }

    private func linha(_ titulo: String, _ valor: String, simbolo: String) -> some View {
        HStack {
            Label(titulo, systemImage: simbolo).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Text(valor).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// Gráfico de linha do histórico, compacto.
struct GraficoPequeno: View {
    let historico: Historico
    let teto: Double?
    let cor: Color

    var body: some View {
        GeometryReader { g in
            let p = historico.pontos(largura: g.size.width, altura: g.size.height, teto: teto)
            if p.count > 1 {
                Path { c in
                    c.move(to: p[0])
                    p.dropFirst().forEach { c.addLine(to: $0) }
                }
                .stroke(cor, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            } else {
                Text("Medindo…").font(.system(size: 9)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Controles

private struct AbaControles: View {
    @EnvironmentObject var store: DockaStore
    @AppStorage("docka.painelGruposAbertos") private var abertosGravados = "bordas"

    private var abertos: Set<String> { Set(abertosGravados.split(separator: ",").map(String.init)) }

    var body: some View {
        VStack(spacing: 8) {
            grupo("bordas", "Bordas", contagem: [store.orbitaControl, store.prateleiraControl, store.notasControl,
                                                 store.monitorControl, store.brightnessControl, store.volumeControl]) {
                LinhaComInterruptor(simbolo: "circle.circle", titulo: "Órbita",
                                    descricao: "Anel de apps em volta do cursor", ligado: $store.orbitaControl)
                Separador()
                LinhaComInterruptor(simbolo: "tray.and.arrow.down", titulo: "Prateleira",
                                    descricao: "Estacione arquivos, textos e links enquanto arrasta", ligado: $store.prateleiraControl)
                Separador()
                LinhaComInterruptor(simbolo: "note.text", titulo: "Bloco de notas",
                                    descricao: "Notas em abas numa lateral", ligado: $store.notasControl)
                Separador()
                LinhaComInterruptor(simbolo: "gauge.with.dots.needle.67percent", titulo: "Painel do sistema",
                                    descricao: "CPU, memória e rede numa borda", ligado: $store.monitorControl)
                Separador()
                LinhaComInterruptor(simbolo: "sun.max", titulo: "Régua de brilho",
                                    descricao: "Brilho de qualquer tela numa lateral", ligado: $store.brightnessControl)
                Separador()
                LinhaComInterruptor(simbolo: "speaker.wave.2", titulo: "Régua de volume",
                                    descricao: "Volume da saída numa lateral", ligado: $store.volumeControl)
            }
            grupo("janelas", "Janelas", contagem: [store.janelasControl, store.janelasArrastar, store.arrastarComTecla, store.alternadorControl,
                                                   store.botaoVerdeMaximiza, store.sairAoFecharControl,
                                                   store.protecaoQ, store.cliquesNoDock, store.previaDoDock]) {
                LinhaComInterruptor(simbolo: "rectangle.split.2x1", titulo: "Encaixar janelas",
                                    descricao: "Metades, quartos e terços por atalho", ligado: $store.janelasControl,
                                    aviso: Colagem.permitido ? nil : "Falta a Acessibilidade")
                Separador()
                LinhaComInterruptor(simbolo: "arrow.up.left.and.arrow.down.right", titulo: "Arrastar até a borda",
                                    descricao: "Solte a janela na borda para encaixar", ligado: $store.janelasArrastar)
                Separador()
                LinhaComInterruptor(simbolo: "hand.draw", titulo: "Arrastar segurando teclas",
                                    descricao: "Mova a janela de qualquer ponto", ligado: $store.arrastarComTecla)
                Separador()
                LinhaComInterruptor(simbolo: "square.stack", titulo: "Alternador de apps",
                                    descricao: "Apps na ordem de uso, num atalho próprio", ligado: $store.alternadorControl)
                Separador()
                LinhaComInterruptor(simbolo: "plus.rectangle", titulo: "Botão verde maximiza",
                                    descricao: "Preenche a tela sem criar outro Espaço", ligado: $store.botaoVerdeMaximiza)
                Separador()
                LinhaComInterruptor(simbolo: "xmark.square", titulo: "Sair ao fechar",
                                    descricao: "Encerra os apps escolhidos ao fechar a última janela", ligado: $store.sairAoFecharControl)
                Separador()
                LinhaComInterruptor(simbolo: "command", titulo: "Proteger o ⌘Q",
                                    descricao: "Segurar, duas vezes ou com ⌥ para encerrar", ligado: $store.protecaoQ)
                Separador()
                LinhaComInterruptor(simbolo: "menubar.dock.rectangle", titulo: "Cliques no Dock",
                                    descricao: "Clicar no app ativo minimiza, oculta ou alterna", ligado: $store.cliquesNoDock)
                Separador()
                LinhaComInterruptor(simbolo: "rectangle.on.rectangle.angled", titulo: "Prévia do Dock",
                                    descricao: "Pare no ícone para ver as janelas do app", ligado: $store.previaDoDock)
            }
            grupo("mouse", "Mouse e teclado", contagem: [store.mouseControl, store.gatilhosControl]) {
                LinhaComInterruptor(simbolo: "computermouse", titulo: "Ajustes do mouse",
                                    descricao: "Inverter, rolagem linear ou suave, botões laterais", ligado: $store.mouseControl,
                                    aviso: Colagem.permitido ? nil : "Falta a Acessibilidade")
                Separador()
                LinhaComInterruptor(simbolo: "text.cursor", titulo: "Gatilhos de snippets",
                                    descricao: "Digitar ;gatilho em qualquer app vira o texto", ligado: $store.gatilhosControl,
                                    aviso: GatilhosController.permitido ? nil : "Faltam permissões")
            }
            grupo("clipboard", "Área de transferência", contagem: [store.historicoControl, store.colarSozinho,
                                                                  store.limparLinksAoCopiar, store.apagarAoBloquear]) {
                LinhaComInterruptor(simbolo: "doc.on.clipboard", titulo: "Histórico",
                                    descricao: "Guarda o que você copia, com busca", ligado: $store.historicoControl)
                Separador()
                LinhaComInterruptor(simbolo: "doc.on.doc", titulo: "Colar sozinho",
                                    descricao: "Escolher no histórico ou num snippet já cola", ligado: $store.colarSozinho,
                                    aviso: Colagem.permitido ? nil : "Falta a Acessibilidade")
                Separador()
                LinhaComInterruptor(simbolo: "link", titulo: "Limpar links ao copiar",
                                    descricao: "Tira utm_, fbclid e outros rastreadores", ligado: $store.limparLinksAoCopiar)
                Separador()
                LinhaComInterruptor(simbolo: "lock", titulo: "Apagar ao travar a tela",
                                    descricao: "Quem usar o Mac depois não cola o que ficou", ligado: $store.apagarAoBloquear)
            }
            grupo("sistema", "Sistema e captura", contagem: [store.alertas, store.capturaControl]) {
                LinhaComInterruptor(simbolo: "exclamationmark.triangle", titulo: "Alertas",
                                    descricao: "CPU, memória, disco, bateria e temperatura", ligado: $store.alertas)
                Separador()
                LinhaComInterruptor(simbolo: "camera.viewfinder", titulo: "Captura",
                                    descricao: "Conta-gotas, texto da tela e captura com anotação", ligado: $store.capturaControl,
                                    aviso: CapturaController.permitido ? nil : "Falta a Gravação de Tela")
            }
        }
    }

    /// Um grupo recolhível, com quantos estão ligados — como "Windows 6/6".
    @ViewBuilder
    private func grupo<C: View>(_ id: String, _ titulo: String, contagem: [Bool],
                                @ViewBuilder conteudo: @escaping () -> C) -> some View {
        let aberto = abertos.contains(id)
        VStack(spacing: 6) {
            Button {
                var s = abertos
                if aberto { s.remove(id) } else { s.insert(id) }
                abertosGravados = s.sorted().joined(separator: ",")
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(aberto ? 90 : 0))
                    Text(titulo.uppercased()).font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("\(contagem.filter { $0 }.count)/\(contagem.count)")
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if aberto { Cartao(conteudo: conteudo) }
        }
    }
}

// MARK: - Utilidades

private struct AbaUtilidades: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        VStack(spacing: 8) {
            if store.historicoControl {
                LinhaDeAcao(simbolo: "doc.on.clipboard", titulo: "Histórico",
                            descricao: "O que você copiou, com busca", atalho: .historico) {
                    HistoricoController.shared.abrir()
                }
            }
            LinhaDeAcao(simbolo: "text.badge.plus", titulo: "Snippets",
                        descricao: "Textos prontos com data, hora e o copiado", atalho: .snippets) {
                SnippetsController.shared.abrir()
            }
            LinhaDeAcao(simbolo: "textformat", titulo: "Colar sem formatação",
                        descricao: "Deixa o copiado em texto puro", atalho: .textoPuro) {
                HistoricoModelo.shared.soTexto()
            }
            LinhaDeAcao(simbolo: "link.badge.plus", titulo: "Limpar o link copiado",
                        descricao: "Tira os rastreadores do link na área de transferência") {
                HistoricoModelo.shared.limparLinkCopiado()
            }
            if store.capturaControl {
                LinhaDeAcao(simbolo: "eyedropper", titulo: "Conta-gotas",
                            descricao: "Copia a cor de qualquer ponto da tela", atalho: .contaGotas) {
                    CapturaController.contaGotas()
                }
                LinhaDeAcao(simbolo: "text.viewfinder", titulo: "Copiar texto da tela",
                            descricao: "Selecione uma área; o texto (ou o QR) é copiado", atalho: .textoDaTela) {
                    CapturaController.textoDaTela()
                }
                LinhaDeAcao(simbolo: "camera.viewfinder",
                            titulo: store.capturaEditar ? "Capturar e anotar" : "Capturar área",
                            descricao: store.capturaEditar ? "Seta, texto, borrão e recorte" : "Para copiar ou para a Mesa",
                            atalho: .capturaArea) {
                    CapturaController.capturarArea()
                }
            }
            if store.janelasControl {
                Menu {
                    ForEach(LayoutDeJanela.grupos.indices, id: \.self) { g in
                        if g > 0 { Divider() }
                        ForEach(LayoutDeJanela.grupos[g]) { l in
                            Button { JanelasBackend.executar(l) } label: { Label(l.titulo, systemImage: l.simbolo) }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.split.2x1").font(.system(size: 14)).foregroundStyle(Color.accentColor)
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Encaixar a janela da frente").font(.system(size: 12, weight: .semibold))
                            Text("Metades, quartos, terços, maximizar…").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .menuStyle(.borderlessButton)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            if !store.capturaControl || !store.historicoControl || !store.janelasControl {
                Text("Mais utilidades aparecem aqui ao ligar Captura, Histórico ou Encaixar janelas em Controles.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Autoteste

extension PainelDaBarra {
    /// Desenha o painel fora da tela, aba por aba: mede a altura e grava um
    /// PNG de cada uma — confere o visual sem abrir nada na tela de ninguém.
    static func autoteste(pasta: String) -> String {
        var r: [String] = []
        let anterior = UserDefaults.standard.string(forKey: "docka.abaDoPainel")
        defer { UserDefaults.standard.set(anterior, forKey: "docka.abaDoPainel") }
        var alturas: [CGFloat] = []
        for aba in AbaDoPainel.allCases {
            UserDefaults.standard.set(aba.rawValue, forKey: "docka.abaDoPainel")
            let hv = NSHostingView(rootView: PainelDaBarra().environmentObject(DockaStore.shared)
                .background(Color(nsColor: .windowBackgroundColor)))
            let janela = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 340, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            janela.contentView = hv
            // deixa o SwiftUI medir o conteúdo e reajustar a altura
            for _ in 0..<6 {
                hv.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            let tamanho = hv.fittingSize
            hv.setFrameSize(tamanho)
            hv.layoutSubtreeIfNeeded()
            if let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds) {
                hv.cacheDisplay(in: hv.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(pasta)/painel-\(aba.rawValue).png"))
            }
            alturas.append(tamanho.height)
            r.append("\(tamanho.height > 220 ? "OK" : "FALHOU") — \(aba.titulo): \(Int(tamanho.width))×\(Int(tamanho.height))")
            janela.contentView = nil
        }
        // a garantia que importa: toda aba com a mesma altura, ou a janela
        // da barra cresce e não volta
        r.append("\(Set(alturas).count == 1 ? "OK" : "FALHOU") — todas as abas com a mesma altura")
        return r.joined(separator: "\n")
    }
}
