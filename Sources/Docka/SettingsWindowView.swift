import SwiftUI
import DockaCore
import CoreAudio

// Gerenciador do Docka.
//
// Construído com os idiomas nativos que PRODUZEM o visual das Configurações do
// Sistema — NavigationSplitView com barra lateral e Form com .formStyle(.grouped)
// — em vez de redesenhar aquele visual com formas próprias. É o que garante que
// as linhas, os espaçamentos, os controles e o comportamento em Tom claro/escuro
// acompanhem o sistema sozinhos.

enum Secao: String, CaseIterable, Identifiable {
    case geral, recursos, sistema, ilha, teclado, finder, alternador, encerrar, dock, apps, aparencia, bandeja, orbita, prateleira, notas, monitor, clipboard, janelas, mouse, captura, brilho, volume, energia, som, paineis, acoes, atalho, sobre
    var id: String { rawValue }

    /// A barra lateral em grupos com título — com mais de vinte seções, um
    /// vão entre blocos já não dizia onde procurar cada coisa.
    static let grupos: [(titulo: String, itens: [Secao])] = [
        ("Essenciais", [.geral, .recursos, .sistema, .ilha, .energia, .som, .monitor]),
        ("Controles de janela", [.mouse, .teclado, .alternador, .janelas, .encerrar, .dock]),
        ("Arquivos", [.finder, .clipboard, .prateleira, .captura]),
        ("Bordas", [.bandeja, .apps, .aparencia, .orbita, .notas, .brilho, .volume]),
        ("Utilidades", [.paineis, .acoes, .atalho]),
        ("", [.sobre]),
    ]

    var titulo: String {
        switch self {
        case .geral:     return "Geral"
        case .recursos:  return "Recursos"
        case .alternador: return "Alternador"
        case .encerrar:  return "Ao fechar"
        case .dock:      return "Dock"
        case .ilha:      return "Ilha Dinâmica"
        case .sistema:   return "Ajustes do sistema"
        case .apps:      return "Apps"
        case .aparencia: return "Aparência"
        case .bandeja:   return "Bandeja"
        case .orbita:    return "Órbita"
        case .prateleira: return "Prateleira"
        case .notas:     return "Bloco de notas"
        case .monitor:   return "Monitor"
        case .clipboard: return "Área de transferência"
        case .janelas:   return "Encaixe de janelas"
        case .mouse:     return "Mouse"
        case .teclado:   return "Teclado"
        case .finder:    return "Finder"
        case .captura:   return "Captura"
        case .brilho:    return "Brilho"
        case .volume:    return "Volume"
        case .energia:   return "Energia"
        case .paineis:   return "Painéis"
        case .som:       return "Som"
        case .acoes:     return "Ações rápidas"
        case .atalho:    return "Atalhos"
        case .sobre:     return "Sobre"
        }
    }

    /// Nome na barra lateral: igual ao título, menos onde o título não cabe
    /// na coluna. A página continua com o nome completo.
    var rotulo: String {
        switch self {
        case .notas:     return "Notas"
        case .sistema:   return "Sistema"
        case .clipboard: return "Copiar e colar"
        case .janelas:   return "Janelas"
        default:         return titulo
        }
    }

    /// Ícones de linha (SF Symbols): na barra lateral o macOS os pinta com a
    /// cor de destaque e de branco na seção selecionada.
    var simbolo: String {
        switch self {
        case .geral:      return "gearshape"
        case .recursos:   return "square.grid.2x2"
        case .energia:    return "bolt"
        case .monitor:    return "chart.xyaxis.line"
        case .mouse:      return "computermouse"
        case .teclado:    return "keyboard"
        case .finder:     return "folder"
        case .alternador: return "rectangle.on.rectangle"
        case .encerrar:   return "xmark.square"
        case .dock:       return "menubar.dock.rectangle"
        case .ilha:       return "rectangle.topthird.inset.filled"
        case .sistema:    return "gearshape.2"
        case .janelas:    return "rectangle.split.2x1"
        case .clipboard:  return "doc.on.clipboard"
        case .prateleira: return "tray.full"
        case .captura:    return "camera.viewfinder"
        case .bandeja:    return "dock.rectangle"
        case .apps:       return "app"
        case .aparencia:  return "circle.lefthalf.filled"
        case .orbita:     return "circle.circle"
        case .notas:      return "note.text"
        case .brilho:     return "sun.max"
        case .volume:     return "speaker.wave.2"
        case .paineis:    return "square.grid.3x3.square"
        case .som:        return "speaker.wave.2"
        case .acoes:      return "rays"
        case .atalho:     return "keyboard"
        case .sobre:      return "info.circle"
        }
    }

    // As Configurações do Sistema usam um quadradinho colorido por seção
    var cor: Color {
        switch self {
        case .geral:     return .gray
        case .recursos:  return .blue
        case .alternador: return .blue
        case .encerrar:  return .blue
        case .dock:      return .blue
        case .ilha:      return .blue
        case .sistema:   return .gray
        case .apps:      return .blue
        case .aparencia: return .indigo
        case .bandeja:   return .teal
        case .orbita:    return .purple
        case .prateleira: return .green
        case .notas:     return .yellow
        case .monitor:   return .mint
        case .clipboard: return .cyan
        case .janelas:   return .blue
        case .mouse:     return .gray
        case .teclado:   return .gray
        case .finder:    return .blue
        case .captura:   return .purple
        case .brilho:    return .yellow
        case .volume:    return .pink
        case .energia:   return .brown
        case .paineis:   return .indigo
        case .som:       return .pink
        case .acoes:     return .red
        case .atalho:    return .orange
        case .sobre:     return .secondary
        }
    }
}

/// O círculo colorido com o símbolo — no Ajustes do macOS 26+ os ícones da
/// barra lateral são círculos, não quadradinhos arredondados.
struct IconeSecao: View {
    let secao: Secao
    /// `.increased` na linha selecionada da barra lateral (fundo azul).
    @Environment(\.backgroundProminence) private var proeminencia

    // azul como a cor de destaque, e branco na seção selecionada — o mesmo
    // que os Ajustes do Sistema fazem, mas sem depender da janela estar ativa
    var body: some View {
        Image(systemName: secao.simbolo)
            .foregroundStyle(proeminencia == .increased ? Color.white : Color.accentColor)
            .frame(width: 20)
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject var store: DockaStore
    @State private var secao: Secao = .geral
    @State private var busca = ""

    var body: some View {
        NavigationSplitView {
            barraLateral
                // largura fixa: nas Configurações a barra lateral não é
                // redimensionável nem recolhível
                .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)
                // fora o botão de recolher — ele desalinha a barra de título e o
                // painel da Apple não tem esse controle
                .toolbar(removing: .sidebarToggle)
        } detail: {
            conteudo
                // título fixo na barra da janela, sem setas de navegação
                .navigationTitle("Ajustes do Docka")
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { store.refreshLaunchAtLogin(); irParaAPedida() }
        .onChange(of: store.secaoDosAjustesPedida) { _, _ in irParaAPedida() }
    }

    /// Outra parte do app (a ilha, por exemplo) pediu uma seção.
    private func irParaAPedida() {
        guard let pedida = store.secaoDosAjustesPedida.flatMap(Secao.init(rawValue:)) else { return }
        secao = pedida
        busca = ""
        store.secaoDosAjustesPedida = nil
    }

    private var resultados: [Secao] {
        busca.isEmpty ? [] : Secao.allCases.filter {
            $0.titulo.localizedCaseInsensitiveContains(busca) || $0.rotulo.localizedCaseInsensitiveContains(busca)
        }
    }

    @ViewBuilder
    private var barraLateral: some View {
        List(selection: selecao) {
            if busca.isEmpty {
                ForEach(Secao.grupos.indices, id: \.self) { i in
                    let g = Secao.grupos[i]
                    if g.titulo.isEmpty {
                        Section { linhas(g.itens) }
                    } else {
                        Section(g.titulo) { linhas(g.itens) }
                    }
                }
            } else {
                Section { linhas(resultados) }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $busca, placement: .sidebar, prompt: "Buscar ajustes")
    }

    private func linhas(_ itens: [Secao]) -> some View {
        ForEach(itens) { s in
            NavigationLink(value: s) {
                Label { Text(s.rotulo) } icon: { IconeSecao(secao: s) }
            }
        }
    }

    private var selecao: Binding<Secao?> {
        Binding(get: { secao }, set: { if let novo = $0 { secao = novo } })
    }

    @ViewBuilder
    private var conteudo: some View {
        switch secao {
        case .geral:     GeralView()
        case .recursos:  RecursosView()
        case .alternador: AlternadorSettingsView()
        case .encerrar:  EncerrarSettingsView()
        case .dock:      DockSettingsView()
        case .ilha:      IlhaSettingsView()
        case .sistema:   AjustesDoSistemaView()
        case .apps:      AppsView()
        case .aparencia: AparenciaView()
        case .bandeja:   BandejaView()
        case .orbita:    OrbitaSettingsView()
        case .prateleira: PrateleiraSettingsView()
        case .notas:     NotasSettingsView()
        case .monitor:   MonitorSettingsView()
        case .clipboard: ClipboardSettingsView()
        case .janelas:   JanelasSettingsView()
        case .mouse:     MouseSettingsView()
        case .teclado:   TecladoSettingsView()
        case .finder:    FinderSettingsView()
        case .captura:   CapturaSettingsView()
        case .brilho:    DeslizadorView(deslizador: .brilho)
        case .volume:    DeslizadorView(deslizador: .volume)
        case .energia:   EnergiaView()
        case .paineis:   PaineisSettingsView()
        case .som:       SomSettingsView()
        case .acoes:     AcoesRapidasView()
        case .atalho:    AtalhoView()
        case .sobre:     SobreView()
        }
    }
}

// MARK: - Geral

private struct GeralView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { store.launchAtLogin },
                                     set: { store.setLaunchAtLogin($0) })) {
                    Text("Abrir no login")
                    Text("O Docka sobe sozinho quando você entra no Mac.")
                }
                if let nota = store.launchAtLoginNote {
                    LabeledContent {
                        Button("Abrir Itens de Início") { store.openLoginItemsSettings() }
                    } label: {
                        Label(nota, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Toggle(isOn: $store.soundsEnabled) {
                    Text("Sons")
                    Text("Toca um som ao revelar a bandeja e ao abrir um app.")
                }
            }

            Section {
                Button("Refazer configuração inicial…") { store.onboarded = false }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Recursos e permissões

extension DockaStore {
    /// Cada recurso que pede permissão, e se está ligado agora — a base do
    /// "Usada por" e do aviso de permissão sobrando ou faltando.
    var recursosComPermissao: [RecursoComPermissao] {
        [
            RecursoComPermissao(nome: "Colar sozinho", permissoes: [.acessibilidade], ligado: colarSozinho),
            RecursoComPermissao(nome: "Encaixar janelas", permissoes: [.acessibilidade], ligado: janelasControl),
            RecursoComPermissao(nome: "Arrastar até a borda", permissoes: [.acessibilidade],
                                ligado: janelasControl && janelasArrastar),
            RecursoComPermissao(nome: "Arrastar segurando teclas", permissoes: [.acessibilidade], ligado: arrastarComTecla),
            RecursoComPermissao(nome: "Alternador com janelas e filtros", permissoes: [.acessibilidade],
                                ligado: alternadorControl && (alternadorJanelas || alternadorSoTela || alternadorSemJanela)),
            RecursoComPermissao(nome: "Ajustes do mouse", permissoes: [.acessibilidade], ligado: mouseControl),
            RecursoComPermissao(nome: "Foco segue o mouse", permissoes: [.acessibilidade], ligado: focoSegueMouse),
            RecursoComPermissao(nome: "Filtro de clique duplo", permissoes: [.acessibilidade], ligado: filtroDeClique),
            RecursoComPermissao(nome: "Clique do meio com três dedos", permissoes: [.acessibilidade], ligado: cliqueDoMeio),
            RecursoComPermissao(nome: "Recortar e colar no Finder", permissoes: [.acessibilidade], ligado: recorteNoFinder),
            RecursoComPermissao(nome: "Comandos de menu na barra de comando", permissoes: [.acessibilidade],
                                ligado: barraMenus && atalho(de: .barraDeComando) != nil),
            RecursoComPermissao(nome: "Modo de limpeza", permissoes: [.acessibilidade], ligado: atalho(de: .limpeza) != nil),
            RecursoComPermissao(nome: "Repique de teclas", permissoes: [.acessibilidade], ligado: repiqueDeTeclas),
            RecursoComPermissao(nome: "Tecla super", permissoes: [.acessibilidade], ligado: teclaSuper),
            RecursoComPermissao(nome: "Sair ao fechar", permissoes: [.acessibilidade], ligado: sairAoFecharControl),
            RecursoComPermissao(nome: "Proteção do ⌘Q e ⌘W", permissoes: [.acessibilidade], ligado: protecaoQ || protecaoW),
            RecursoComPermissao(nome: "Botão verde maximiza", permissoes: [.acessibilidade], ligado: botaoVerdeMaximiza),
            RecursoComPermissao(nome: "Cliques no Dock", permissoes: [.acessibilidade], ligado: cliquesNoDock),
            RecursoComPermissao(nome: "Gatilhos de snippets", permissoes: [.monitoramentoDeEntrada, .acessibilidade],
                                ligado: gatilhosControl),
            RecursoComPermissao(nome: "Texto da tela e captura", permissoes: [.gravacaoDeTela], ligado: capturaControl),
            RecursoComPermissao(nome: "Prévia do Dock", permissoes: [.acessibilidade], ligado: previaDoDock),
            RecursoComPermissao(nome: "Miniaturas da prévia do Dock", permissoes: [.gravacaoDeTela],
                                ligado: previaDoDock && previaDoDockMiniaturas),
            RecursoComPermissao(nome: "Notificações na ilha", permissoes: [.acessibilidade],
                                ligado: ilhaControl && ilhaNotificacoes),
            RecursoComPermissao(nome: "Calendário na ilha", permissoes: [.calendarios],
                                ligado: ilhaControl && !ilhaOcultas.contains(Ilha.Secao.calendario.rawValue)),
            RecursoComPermissao(nome: "Prévias do alternador", permissoes: [.gravacaoDeTela],
                                ligado: alternadorControl && alternadorPrevias),
        ]
    }
}

enum EstadoDaPermissao {
    static func concedida(_ p: Permissao) -> Bool {
        switch p {
        case .acessibilidade:         return Colagem.permitido
        case .gravacaoDeTela:         return CapturaController.permitido
        case .monitoramentoDeEntrada: return GatilhosController.podeEscutar
        case .calendarios:            return CalendarioModelo.permitido
        }
    }
}

private struct RecursosView: View {
    enum Aba: String, CaseIterable { case recursos = "Recursos", permissoes = "Permissões" }
    @State private var aba: Aba

    init(aba: Aba = .recursos) { _aba = State(initialValue: aba) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CartaoDeAjuste {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: $aba) {
                            ForEach(Aba.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Divider()
                        Text(aba == .recursos
                             ? "Ligue e desligue cada recurso. Os detalhes ficam na seção de cada um."
                             : "O que cada permissão faz e quais recursos a usam.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }
                switch aba {
                case .recursos:   ListaDeRecursos()
                case .permissoes: ListaDePermissoes()
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// O cartão dos ajustes: fundo um tom acima da janela, cantos arredondados.
private struct CartaoDeAjuste<Conteudo: View>: View {
    @ViewBuilder let conteudo: () -> Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: conteudo)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// Um interruptor por recurso, com a permissão que ele pede ao lado.
private struct ListaDeRecursos: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        grupo("Bordas", [
            ("circle.circle", "Órbita", "Anel de apps em volta do cursor", $store.orbitaControl, []),
            ("tray.full", "Prateleira", "Estacione o que você arrasta numa lateral", $store.prateleiraControl, []),
            ("note.text", "Bloco de notas", "Notas em abas numa lateral", $store.notasControl, []),
            ("chart.xyaxis.line", "Painel do sistema", "CPU, memória e rede numa borda", $store.monitorControl, []),
            ("sun.max", "Régua de brilho", "Brilho de qualquer tela numa lateral", $store.brightnessControl, []),
            ("speaker.wave.2", "Régua de volume", "Volume da saída numa lateral", $store.volumeControl, []),
        ])
        grupo("Controles de janela", [
            ("rectangle.split.2x1", "Encaixe de janelas", "Metades, quartos e terços por atalho", $store.janelasControl, [.acessibilidade]),
            ("arrow.up.left.and.arrow.down.right", "Arrastar até a borda", "Solte a janela na borda para encaixar", $store.janelasArrastar, [.acessibilidade]),
            ("hand.draw", "Arrastar segurando teclas", "Mova e redimensione de qualquer ponto da janela", $store.arrastarComTecla, [.acessibilidade]),
            ("rectangle.on.rectangle", "Alternador", "Apps na ordem de uso, num atalho próprio", $store.alternadorControl, []),
            ("computermouse", "Ajustes do mouse", "Inverter, rolagem linear ou suave, botões laterais", $store.mouseControl, [.acessibilidade]),
            ("plus.rectangle", "Botão verde maximiza", "Preenche a tela sem criar outro Espaço", $store.botaoVerdeMaximiza, [.acessibilidade]),
            ("xmark.square", "Sair ao fechar", "Encerra os apps escolhidos ao fechar a última janela", $store.sairAoFecharControl, [.acessibilidade]),
            ("command", "Proteger o ⌘Q", "Segurar, apertar duas vezes ou usar ⌥ para encerrar", $store.protecaoQ, [.acessibilidade]),
            ("command", "Proteger o ⌘W", "O mesmo para fechar janelas", $store.protecaoW, [.acessibilidade]),
            ("menubar.dock.rectangle", "Cliques no Dock", "Clicar no app ativo minimiza, oculta ou alterna", $store.cliquesNoDock, [.acessibilidade]),
            ("rectangle.on.rectangle.angled", "Prévia do Dock", "Pare no ícone para ver as janelas do app", $store.previaDoDock, [.acessibilidade, .gravacaoDeTela]),
        ])
        grupo("Arquivos", [
            ("doc.on.clipboard", "Histórico", "O que você copia, com busca", $store.historicoControl, []),
            ("doc.on.doc", "Colar sozinho", "Escolher no histórico ou num snippet já cola", $store.colarSozinho, [.acessibilidade]),
            ("text.cursor", "Gatilhos de snippets", "Digitar ;gatilho vira o texto", $store.gatilhosControl, [.monitoramentoDeEntrada, .acessibilidade]),
            ("link", "Limpar links ao copiar", "Tira utm_, fbclid e outros rastreadores", $store.limparLinksAoCopiar, []),
            ("camera.viewfinder", "Captura", "Conta-gotas, texto da tela e captura com anotação", $store.capturaControl, [.gravacaoDeTela]),
        ])
        grupo("Sistema", [
            ("exclamationmark.triangle", "Alertas", "CPU, memória, disco, bateria e temperatura", $store.alertas, []),
        ])
    }

    private func grupo(_ titulo: String,
                       _ linhas: [(String, String, String, Binding<Bool>, [Permissao])]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            CartaoDeAjuste {
                ForEach(linhas.indices, id: \.self) { i in
                    if i > 0 { Divider().padding(.leading, 44) }
                    let l = linhas[i]
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: l.0)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(l.1).font(.system(size: 13, weight: .semibold))
                                ForEach(l.4) { p in
                                    Text(p.titulo)
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(l.2).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: l.3).toggleStyle(.switch).labelsHidden()
                    }
                    .padding(12)
                }
            }
        }
    }
}

/// Cada permissão: estado, para que serve, quem usa, e o que fazer.
private struct ListaDePermissoes: View {
    @EnvironmentObject var store: DockaStore
    @State private var concedidas = Self.ler()
    private let relogio = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private static func ler() -> [Permissao: Bool] {
        Dictionary(uniqueKeysWithValues: Permissao.allCases.map { ($0, EstadoDaPermissao.concedida($0)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CartaoDeAjuste {
                ForEach(Array(Permissao.allCases.enumerated()), id: \.element) { i, p in
                    if i > 0 { Divider() }
                    linha(p, concedida: concedidas[p] ?? false)
                }
            }
            Text("O núcleo do Docka não pede nenhuma. Revogar uma permissão nos Ajustes do Sistema só desliga o que depende dela — o resto continua funcionando. Assinado ad-hoc, o Docka pode precisar delas de novo depois de uma atualização.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        // as permissões mudam nos Ajustes do Sistema, fora do Docka
        .onReceive(relogio) { _ in concedidas = Self.ler() }
    }

    @ViewBuilder
    private func linha(_ p: Permissao, concedida: Bool) -> some View {
        let recursos = store.recursosComPermissao
        let usam = Permissoes.usadaPor(p, em: recursos)
        let situacao = Permissoes.situacao(p, concedida: concedida, recursos: recursos)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: p.simbolo)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(p.titulo).font(.system(size: 13, weight: .semibold))
                    Circle().fill(concedida ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(concedida ? "Concedida" : "Não concedida")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(p.descricao).font(.system(size: 11))
                Text(usam.isEmpty
                     ? "Nada ligado usa agora. Pode ser usada por: \(Permissoes.lista(Permissoes.podeSerUsadaPor(p, em: recursos)))."
                     : "Usada por: \(Permissoes.lista(usam)).")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch situacao {
                case .concedidaSemUso:
                    aviso("Você concedeu esta permissão, mas nada ligado precisa dela. Se quiser, revogue nos Ajustes do Sistema.",
                          cor: .secondary)
                case .falta:
                    aviso("\(Permissoes.lista(usam)) \(usam.count == 1 ? "está ligado e precisa" : "estão ligados e precisam") desta permissão para funcionar.",
                          cor: .orange)
                case .emUso, .desnecessaria:
                    EmptyView()
                }
                Button("Abrir Ajustes do Sistema") {
                    if let url = URL(string: p.enderecoDosAjustes) { NSWorkspace.shared.open(url) }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(12)
    }

    private func aviso(_ texto: String, cor: Color) -> some View {
        Text(texto)
            .font(.system(size: 11))
            .foregroundStyle(cor == .orange ? Color.orange : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(cor.opacity(0.12)))
    }
}

// MARK: - Apps

private struct AppsView: View {
    @EnvironmentObject var store: DockaStore
    @State private var alvo: UUID?

    /// A bandeja sendo editada — a principal, salvo escolha do usuário.
    private var dock: DockConfig {
        store.docks.first { $0.id == alvo } ?? store.principal
    }

    var body: some View {
        Form {
            if store.docks.count > 1 {
                Section {
                    Picker("Bandeja", selection: Binding(
                        get: { dock.id }, set: { alvo = $0 })) {
                        ForEach(store.docks) { d in Text(d.titulo).tag(d.id) }
                    }
                }
            }

            Section("Na bandeja") {
                if dock.apps.isEmpty {
                    ContentUnavailableView("Nenhum app na bandeja",
                                           systemImage: "square.dashed",
                                           description: Text("Escolha abaixo os apps que ficam no Docka."))
                } else {
                    ForEach(store.apps(of: dock)) { app in
                        LabeledContent {
                            Button {
                                withAnimation { store.alternarApp(app.path, em: dock.id) }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remover \(app.name) do Docka")
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                            }
                        }
                    }
                }
            }

            Section("Aplicativos instalados") {
                AppPickerGrid(dockID: dock.id)
                    .frame(minHeight: 260)
                    .listRowInsets(EdgeInsets())
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Aparência

private struct AparenciaView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                // como no painel Aparência: três miniaturas de janela com o
                // rótulo embaixo e contorno azul na selecionada
                LabeledContent("Tom") {
                    HStack(alignment: .top, spacing: 20) {
                        OpcaoTom(valor: .claro, selecao: $store.appearance) {
                            MiniJanela(escura: false)
                        }
                        OpcaoTom(valor: .escuro, selecao: $store.appearance) {
                            MiniJanela(escura: true)
                        }
                        OpcaoTom(valor: .automatico, selecao: $store.appearance) {
                            MiniJanelaAutomatica()
                        }
                    }
                }
            }

            Section {
                // no formato do controle Liquid Glass das Configurações:
                // rótulo à esquerda, prévia simulada à direita e o slider embaixo dela
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 10) {
                        MaterialPreview(tint: store.glassTint,
                                        appearance: TrayAppearance(persisted: store.appearance),
                                        apps: store.apps(of: store.principal))
                            .frame(width: 330, height: 180)

                        HStack(spacing: 8) {
                            Image(systemName: "square.on.square.dashed")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Slider(value: $store.glassTint, in: 0...1)
                                .labelsHidden()
                                .accessibilityLabel("Material do painel")
                                .accessibilityValue(materialDescrito)
                            Image(systemName: "square.filled.on.square")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(width: 330)

                        if !GlassTint.isSystemNeutral(store.glassTint) {
                            Button("Voltar ao padrão") {
                                withAnimation { store.matchSystemGlassTint() }
                            }
                        }
                    }
                } label: {
                    Text("Material do painel")
                    Text(materialDescrito)
                }
            } footer: {
                Text("Prévia sobre a sua imagem de fundo atual. Vibrância do sistema, a mesma do Dock: à esquerda deixa mais do fundo atravessar; à direita fecha.")
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(DockaStore.systemIconStyle).foregroundStyle(.secondary)
                        Button("Abrir") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } label: {
                    Text("Estilo dos ícones")
                    Text("Definido em Configurações do Sistema — a bandeja acompanha.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var materialDescrito: String {
        if GlassTint.material(for: store.glassTint) == .translucido { return "Translúcido" }
        let escurecer = GlassTint.overlayOpacity(store.glassTint)
        return escurecer == 0 ? "Fosco (padrão)" : "Fosco + \(Int(escurecer * 100))%"
    }
}

// MARK: - Bandeja

private struct BandejaView: View {
    @EnvironmentObject var store: DockaStore

    private func indice(_ d: DockConfig) -> Int {
        store.docks.firstIndex(where: { $0.id == d.id }) ?? 0
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.pressureZone) {
                    Text("Pressure Zone")
                    Text("Só revela quando você empurra o cursor contra o canto de propósito.")
                }
                Toggle(isOn: $store.followDock) {
                    Text("Seguir mudanças do Dock")
                    Text("Assenta a bandeja em cima do Dock e realinha quando ele muda de tamanho ou de lado.")
                }
                Toggle(isOn: $store.bounceOnLaunch) {
                    Text("Animar abertura de aplicativos")
                    Text("O ícone quica duas vezes enquanto o app abre.")
                }
                Toggle(isOn: $store.showIndicators) {
                    Text("Mostrar indicadores para aplicativos abertos")
                    Text("Bolinha sob cada app em execução.")
                }
            }

            ForEach(store.docks) { d in
                Section {
                    Picker("Borda da tela", selection: Binding(
                        get: { d.edge },
                        set: { store.definirBorda($0, em: d.id) })) {
                        ForEach(TrayEdge.allCases, id: \.self) { Text($0.titulo).tag($0) }
                    }
                    Picker("Posição na borda", selection: Binding(
                        get: { d.alignment },
                        set: { store.definirAlinhamento($0, em: d.id) })) {
                        ForEach(TrayAlignment.allCases, id: \.self) {
                            Text($0.titulo(for: d.edge)).tag($0)
                        }
                    }
                    if d.alignment != .center {
                        LabeledContent("Distância do canto") {
                            LinhaSlider(valor: Binding(get: { d.offset },
                                                       set: { store.definirOffset($0, em: d.id) }),
                                        faixa: 0...400,
                                        texto: "\(Int(d.offset)) pt")
                        }
                    }
                    LabeledContent("Apps") {
                        HStack(spacing: 6) {
                            Text("\(d.apps.count)").foregroundStyle(.secondary)
                            ForEach(store.apps(of: d).prefix(6)) { app in
                                Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                            }
                        }
                    }
                    if store.docks.count > 1 {
                        Button("Remover esta bandeja", role: .destructive) {
                            withAnimation { store.removerDock(d.id) }
                        }
                    }
                } header: {
                    Text(store.docks.count > 1
                         ? "Bandeja \(indice(d) + 1) — \(d.titulo)"
                         : "Bandeja")
                }
            }

            Section {
                Button("Adicionar bandeja…") { withAnimation { store.adicionarDock() } }
                    .disabled(store.docks.count >= TrayEdge.allCases.count)
            } footer: {
                Text(store.docks.count >= TrayEdge.allCases.count
                     ? "Uma bandeja por borda da tela."
                     : "Cada bandeja tem os próprios apps e a própria borda. A aparência é comum a todas.")
            }

            Section {
                LabeledContent("Tamanho dos ícones") {
                    LinhaSlider(valor: $store.iconSize, faixa: 32...64, passo: 4,
                                texto: "\(Int(store.iconSize)) pt")
                }
                .accessibilityLabel("Tamanho dos ícones")
                .accessibilityValue("\(Int(store.iconSize)) pontos")

                LabeledContent("Ampliação máxima") {
                    LinhaSlider(valor: $store.maxScale, faixa: 1...2.5,
                                texto: store.maxScale <= 1 ? "Desativada"
                                       : String(format: "%.2f×", store.maxScale))
                }
                .accessibilityLabel("Ampliação máxima")

                LabeledContent("Alcance da ampliação") {
                    LinhaSlider(valor: $store.maxRange, faixa: 60...400,
                                texto: "\(Int(store.maxRange)) pt")
                }
                .accessibilityLabel("Alcance da ampliação")
            } header: {
                Text("Ampliação")
            } footer: {
                Text("O alcance é a distância em que o cursor ainda mexe com um ícone. Fora dele o ícone fica exatamente no tamanho normal, como no Dock.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Uma opção do seletor de Tom: miniatura de janela + rótulo, com contorno
/// azul quando selecionada — a anatomia do seletor de Aparência da Apple.
private struct OpcaoTom<Previa: View>: View {
    let valor: TrayAppearance
    @Binding var selecao: String
    @ViewBuilder let previa: () -> Previa

    private var selecionada: Bool { selecao == valor.rawValue }

    var body: some View {
        Button { selecao = valor.rawValue } label: {
            VStack(spacing: 7) {
                previa()
                    .frame(width: 62, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(selecionada ? Color.accentColor : .clear, lineWidth: 2))
                Text(valor.titulo)
                    .font(.system(size: 11, weight: selecionada ? .semibold : .regular))
                    .foregroundStyle(selecionada ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tom \(valor.titulo)")
        .accessibilityAddTraits(selecionada ? [.isSelected] : [])
    }
}

/// A janelinha do seletor: barra azul no topo e os três semáforos.
private struct MiniJanela: View {
    let escura: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            (escura ? Color(red: 0.10, green: 0.11, blue: 0.20) : Color(white: 0.92))
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(escura ? Color(red: 0.25, green: 0.45, blue: 0.95)
                                 : Color(red: 0.45, green: 0.62, blue: 0.98))
                    .frame(height: 9)
                    .padding(.horizontal, 5)
                    .padding(.top, 5)
                HStack(spacing: 2.5) {
                    Circle().fill(.red).frame(width: 4, height: 4)
                    Circle().fill(.yellow).frame(width: 4, height: 4)
                    Circle().fill(.green).frame(width: 4, height: 4)
                }
                .padding(.leading, 6)
            }
        }
    }
}

/// Metade clara, metade escura, com o corte diagonal do original.
private struct MiniJanelaAutomatica: View {
    var body: some View {
        ZStack {
            MiniJanela(escura: true)
            MiniJanela(escura: false).clipShape(CorteDiagonal())
        }
    }
}

private struct CorteDiagonal: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: rect.width * 0.62, y: 0))
        p.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// Prévia do material, no formato do controle Liquid Glass das Configurações:
/// a bandeja em miniatura sobre a imagem de fundo atual do usuário, reagindo ao
/// slider e ao Tom escolhidos.
///
/// A prévia NÃO usa a vibrância real — ela amostra atrás da janela, e aqui o
/// fundo é conteúdo da própria janela. Simula o resultado com os materiais
/// de dentro da janela, nas mesmas proporções do painel de verdade.
private struct MaterialPreview: View {
    let tint: Double
    let appearance: TrayAppearance
    let apps: [PinnedApp]

    /// Carregada uma vez: recarregar a cada redraw tocaria o disco no arrasto do slider.
    private static let wallpaper: NSImage? = {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Color.clear assume o tamanho proposto (330×180) e o overlay prende
            // a imagem nele — sem isso o scaledToFill estoura o frame e engole
            // a linha inteira do Form
            Color.clear.overlay(fundo)
            bandejinha.padding(.bottom, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .modifier(EsquemaDaPrevia(appearance: appearance))
    }

    @ViewBuilder
    private var fundo: some View {
        if let img = Self.wallpaper {
            Image(nsImage: img).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [.teal.opacity(0.7), .indigo.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var bandejinha: some View {
        let size: CGFloat = 30
        return HStack(spacing: TrayGeometry.gap(size: size)) {
            ForEach(iconesDaPrevia.indices, id: \.self) { i in
                Image(nsImage: iconesDaPrevia[i])
                    .resizable().interpolation(.high)
                    .frame(width: size, height: size)
            }
        }
        .padding(.horizontal, TrayGeometry.padding(size: size))
        .padding(.top, TrayGeometry.paddingTop(size: size))
        .padding(.bottom, TrayGeometry.indicatorRow(size: size) + TrayGeometry.paddingBottom(size: size))
        .background(materialSimulado)
    }

    private var materialSimulado: some View {
        let forma = RoundedRectangle(cornerRadius: TrayGeometry.cornerRadius(size: 30),
                                     style: .continuous)
        let escurecer = GlassTint.overlayOpacity(tint)
        return ZStack {
            forma.fill(GlassTint.material(for: tint) == .translucido
                       ? AnyShapeStyle(.ultraThinMaterial)
                       : AnyShapeStyle(.regularMaterial))
            if escurecer > 0 { forma.fill(.black.opacity(escurecer)) }
        }
        .overlay(forma.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.06)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: 0.8))
    }

    private var iconesDaPrevia: [NSImage] {
        if !apps.isEmpty { return apps.prefix(4).map(\.icon) }
        // antes de escolher qualquer app, a prévia usa apps do sistema
        return ["/System/Applications/App Store.app",
                "/System/Applications/Notes.app",
                "/System/Applications/Utilities/Terminal.app"]
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { PinnedApp(path: $0).icon }
    }
}

/// O Tom escolhido vale também para a prévia; automático segue o sistema.
private struct EsquemaDaPrevia: ViewModifier {
    let appearance: TrayAppearance
    func body(content: Content) -> some View {
        switch appearance {
        case .automatico: content
        case .claro:      content.environment(\.colorScheme, .light)
        case .escuro:     content.environment(\.colorScheme, .dark)
        }
    }
}

/// Slider com o valor à direita, na MESMA linha do rótulo — é como as
/// Configurações do Sistema apresentam um ajuste contínuo.
private struct LinhaSlider: View {
    @Binding var valor: Double
    let faixa: ClosedRange<Double>
    var passo: Double? = nil
    let texto: String

    var body: some View {
        HStack(spacing: 10) {
            if let passo {
                Slider(value: $valor, in: faixa, step: passo)
            } else {
                Slider(value: $valor, in: faixa)
            }
            Text(texto)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .trailing)
        }
        .frame(minWidth: 300)
        .labelsHidden()
    }
}

// MARK: - Órbita

private struct OrbitaSettingsView: View {
    @EnvironmentObject var store: DockaStore
    /// Item selecionado no anel de prévia — a "zona" da referência.
    @State private var zona: UUID?
    @State private var renomeando = false
    @State private var novoNome = ""
    @State private var escolhendoApp = false
    @State private var novoSite = ""
    @State private var adicionandoSite = false

    private var anel: AnelDaOrbita? {
        store.aneis.first { $0.id == store.anelAtivo } ?? store.aneis.first
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.orbitaControl) {
                    Text("Órbita")
                    Text("Um anel com seus itens em volta do cursor. Aponte na direção de um e clique para abrir.")
                }
            }

            if store.orbitaControl {
                secaoDeAneis
                if let anel {
                    secaoDaPrevia(anel)
                    secaoDaZona(anel)
                    secaoAdicionar(anel)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $escolhendoApp) { folhaDeApps }
    }

    // MARK: anéis

    private var secaoDeAneis: some View {
        Section {
            Picker("Anel", selection: Binding(
                get: { anel?.id ?? UUID() },
                set: { store.anelAtivo = $0; zona = nil })) {
                ForEach(store.aneis) { a in
                    Text("\(a.nome) — \(a.itens.count) \(a.itens.count == 1 ? "item" : "itens")")
                        .tag(a.id)
                }
            }
            HStack {
                Button("Novo anel") { store.adicionarAnel(); zona = nil }
                    .disabled(!Aneis.podeCriar(store.aneis))
                Button("Renomear…") {
                    novoNome = anel?.nome ?? ""
                    renomeando = true
                }
                Spacer()
                Button("Apagar anel", role: .destructive) {
                    if let anel { store.removerAnel(anel.id); zona = nil }
                }
                .disabled(store.aneis.count <= 1)
            }
        } header: {
            Text("Anéis")
        } footer: {
            Text("Até \(Aneis.maximo) anéis — Trabalho, Design, Estudo… Com a órbita aberta, a rolagem do mouse troca de anel.")
        }
        .alert("Renomear anel", isPresented: $renomeando) {
            TextField("Nome", text: $novoNome)
            Button("Renomear") {
                if let anel { store.renomearAnel(anel.id, para: novoNome) }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: prévia clicável

    private func secaoDaPrevia(_ anel: AnelDaOrbita) -> some View {
        Section {
            PreviaDoAnel(anel: anel, zona: $zona)
                .frame(maxWidth: .infinity, minHeight: 250)
                .padding(.vertical, 6)
        } footer: {
            if anel.itens.isEmpty {
                Text("O anel está vazio — adicione itens abaixo.")
            } else {
                Text("Clique num item para ver e editar a zona dele.")
            }
        }
    }

    // MARK: a zona selecionada

    @ViewBuilder
    private func secaoDaZona(_ anel: AnelDaOrbita) -> some View {
        if let zona, let i = anel.itens.firstIndex(where: { $0.id == zona }) {
            let item = anel.itens[i]
            Section("Zona \(i + 1)") {
                LabeledContent {
                    HStack(spacing: 8) {
                        // uma casa por clique, sem dar a volta: num anel,
                        // "atravessar" a ponta ao reordenar confunde
                        Button { store.moverItem(item.id, passo: -1, em: anel.id) } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .disabled(i == 0)
                        .help("Mover no sentido anti-horário")
                        .accessibilityLabel("Mover \(ItemVisual.nome(item)) no sentido anti-horário")
                        Button { store.moverItem(item.id, passo: 1, em: anel.id) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(i == anel.itens.count - 1)
                        .help("Mover no sentido horário")
                        .accessibilityLabel("Mover \(ItemVisual.nome(item)) no sentido horário")
                        if item.tipo == .site {
                            Button("Atualizar logo") {
                                FaviconStore.shared.rebuscar(item.valor)
                            }
                            .help("Baixa a logo de novo — para site que trocou de identidade")
                        }
                        Divider().frame(height: 16)
                        Button("Remover do anel", role: .destructive) {
                            store.removerItem(item.id, de: anel.id)
                            self.zona = nil
                        }
                    }
                } label: {
                    Label {
                        Text(ItemVisual.nome(item))
                        Text(item.tipo.titulo + (item.tipo == .site ? " — \(item.valor)" : "")
                             + (item.tipo == .anel ? " — abre o anel \(ItemVisual.nome(item))" : ""))
                    } icon: {
                        Image(nsImage: ItemVisual.icone(item))
                            .resizable().frame(width: 28, height: 28)
                    }
                }
            }
        }
    }

    // MARK: adicionar

    private func secaoAdicionar(_ anel: AnelDaOrbita) -> some View {
        Section {
            HStack(spacing: 10) {
                Button { escolhendoApp = true } label: {
                    Label("Aplicativo", systemImage: TipoDeItem.app.simbolo)
                }
                Button { adicionandoSite = true } label: {
                    Label("Site", systemImage: TipoDeItem.site.simbolo)
                }
                Button { escolherDoDisco(.arquivo, em: anel.id) } label: {
                    Label("Arquivo", systemImage: TipoDeItem.arquivo.simbolo)
                }
                Button { escolherDoDisco(.pasta, em: anel.id) } label: {
                    Label("Pasta", systemImage: TipoDeItem.pasta.simbolo)
                }
            }
            HStack(spacing: 10) {
                let destinos = Aneis.destinosDeSubmenu(de: anel, em: store.aneis)
                Menu {
                    ForEach(destinos) { d in
                        Button(d.nome) {
                            store.adicionarItem(ItemDaOrbita(tipo: .anel, valor: d.id.uuidString),
                                                em: anel.id)
                        }
                    }
                } label: {
                    Label("Submenu", systemImage: TipoDeItem.anel.simbolo)
                }
                .fixedSize()
                .disabled(destinos.isEmpty)
                .help(destinos.isEmpty ? "Crie outro anel para usá-lo como submenu" : "Um item que abre outro anel no mesmo lugar")
                Menu {
                    ForEach(AcaoRapida.allCases.filter(AcoesRapidasBackend.disponivel)) { a in
                        Button(a.titulo) {
                            store.adicionarItem(ItemDaOrbita(tipo: .acao, valor: a.rawValue),
                                                em: anel.id)
                        }
                    }
                } label: {
                    Label("Ação rápida", systemImage: TipoDeItem.acao.simbolo)
                }
                .fixedSize()
            }
            .disabled(anel.itens.count >= Aneis.maximoDeItens)
        } header: {
            Text("Adicionar ao anel")
        } footer: {
            Text(anel.itens.count >= Aneis.maximoDeItens
                 ? "O anel está cheio (\(Aneis.maximoDeItens) itens) — com mais, os setores ficam finos demais para apontar."
                 : "Aplicativo, site, arquivo ou pasta — cada um abre do jeito próprio: app lança, site vai ao navegador, arquivo abre no app padrão, pasta abre no Finder. Um submenu abre outro anel no mesmo lugar (clique no miolo ou Esc para voltar); uma ação rápida trava a tela, ejeta discos e afins.")
        }
        .sheet(isPresented: $adicionandoSite) {
            FolhaDeSite { url in
                store.adicionarItem(ItemDaOrbita(tipo: .site, valor: url), em: anel.id)
            }
        }
    }

    /// Painel do sistema para arquivo ou pasta — o "Browse" da referência.
    private func escolherDoDisco(_ tipo: TipoDeItem, em id: UUID) {
        let painel = NSOpenPanel()
        painel.canChooseFiles = tipo == .arquivo
        painel.canChooseDirectories = tipo == .pasta
        painel.allowsMultipleSelection = true
        painel.prompt = "Adicionar"
        guard painel.runModal() == .OK else { return }
        for url in painel.urls {
            store.adicionarItem(ItemDaOrbita(tipo: tipo, valor: url.path), em: id)
        }
    }

    private var folhaDeApps: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Aplicativos").font(.headline)
                Spacer()
                Button("Concluído") { escolhendoApp = false }
            }
            .padding()
            AppPickerGrid(
                estaSelecionado: { caminho in
                    anel?.itens.contains { $0.tipo == .app && $0.valor == caminho } ?? false
                },
                alternar: { caminho in
                    guard let anel else { return }
                    if let existente = anel.itens.first(where: { $0.tipo == .app && $0.valor == caminho }) {
                        store.removerItem(existente.id, de: anel.id)
                    } else {
                        store.adicionarItem(ItemDaOrbita(tipo: .app, valor: caminho), em: anel.id)
                    }
                })
                .environmentObject(store)
        }
        .frame(width: 560, height: 480)
    }
}

/// Adicionar site com a logo aparecendo na hora: digitou a URL, a busca parte
/// para o próprio site e a prévia mostra o que o anel vai mostrar.
private struct FolhaDeSite: View {
    let adicionar: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var texto = ""
    @State private var logo: NSImage?
    @State private var buscando = false
    /// Carimbo da última busca: só a resposta MAIS RECENTE pode pintar a
    /// prévia — sem isso, a logo de uma URL antiga que demorou atropela a nova.
    @State private var geracao = 0

    private var url: String? { ItemDaOrbita.urlDeSite(texto) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Adicionar site").font(.headline)

            TextField("exemplo.com", text: $texto)
                .textFieldStyle(.roundedBorder)
                .onSubmit { confirmar() }
                .onChange(of: texto) { _, _ in buscarPrevia() }

            HStack(spacing: 12) {
                Group {
                    if let logo {
                        Image(nsImage: logo).resizable()
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundStyle(url == nil ? Color.secondary : .blue)
                    }
                }
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill(Color(nsColor: .textBackgroundColor)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.flatMap { URL(string: $0)?.host } ?? "—")
                        .font(.system(size: 13, weight: .medium))
                    Text(estado).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if buscando { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor)))

            HStack {
                Text("Sem https:// também vale — o Docka completa.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Adicionar") { confirmar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var estado: String {
        if url == nil { return texto.isEmpty ? "Digite o endereço" : "Endereço inválido" }
        if buscando { return "Buscando a logo no site…" }
        return logo == nil ? "Sem logo — o anel usa o globo" : "Logo encontrada"
    }

    /// A busca parte assim que a URL fica válida, com um respiro para o
    /// usuário terminar de digitar — senão cada tecla dispara uma requisição.
    private func buscarPrevia() {
        logo = nil
        geracao += 1
        guard let url else { buscando = false; return }
        let minha = geracao
        buscando = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard minha == geracao else { return }
            FaviconStore.shared.buscarParaPrevia(url) { imagem in
                guard minha == geracao else { return }
                logo = imagem
                buscando = false
            }
        }
    }

    private func confirmar() {
        guard let url else { return }
        adicionar(url)
        dismiss()
    }
}

/// O anel desenhado nos ajustes, com cada item clicável — o editor visual da
/// referência: vê-se o anel como ele vai aparecer, e clicar num item abre a
/// configuração daquela zona.
private struct PreviaDoAnel: View {
    let anel: AnelDaOrbita
    @Binding var zona: UUID?

    private var itens: [ItemDaOrbita] { anel.itens }

    var body: some View {
        GeometryReader { geo in
            let lado = min(geo.size.width, geo.size.height)
            // prévia em escala: o anel real usa a geometria da Orbita, aqui só
            // reduzimos tudo pelo mesmo fator para caber na janela
            let fator = lado / Orbita.tamanhoDoPainel(total: max(1, itens.count))
            let r = Orbita.raio(total: itens.count) * fator
            let icone = Orbita.tamanhoItem * fator
            let centro = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Anel(raioInterno: Orbita.raioInterno * fator)
                    .fill(Color(nsColor: .quaternaryLabelColor), style: FillStyle(eoFill: true))
                    .frame(width: 2 * r + icone, height: 2 * r + icone)
                    .position(centro)

                ForEach(Array(itens.enumerated()), id: \.element.id) { i, item in
                    let p = Orbita.posicao(indice: i, total: itens.count)
                    Button {
                        zona = zona == item.id ? nil : item.id
                    } label: {
                        Image(nsImage: ItemVisual.icone(item))
                            .resizable()
                            .frame(width: icone, height: icone)
                            .padding(4)
                            .background(
                                Circle().fill(zona == item.id
                                              ? Color.accentColor.opacity(0.25) : .clear))
                    }
                    .buttonStyle(.plain)
                    .position(x: centro.x + p.x * fator, y: centro.y + p.y * fator)
                    .accessibilityLabel("Zona \(i + 1): \(ItemVisual.nome(item))")
                }

                if itens.isEmpty {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                        .position(centro)
                }
            }
        }
    }
}

// MARK: - Prateleira

private struct PrateleiraSettingsView: View {
    @EnvironmentObject var store: DockaStore
    @ObservedObject private var modelo = PrateleiraModelo.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.prateleiraControl) {
                    Text("Prateleira")
                    Text("Um painel na lateral para estacionar arquivos, textos e links enquanto você arrasta, e soltar depois onde quiser.")
                }
            }

            if store.prateleiraControl {
                Section {
                    Picker("Lateral", selection: $store.prateleiraBorda) {
                        ForEach(Prateleira.bordasPermitidas, id: \.self) {
                            Text($0.titulo).tag($0.rawValue)
                        }
                    }
                    Picker("Posição", selection: $store.prateleiraAlinhamento) {
                        ForEach(TrayAlignment.allCases, id: \.self) {
                            Text($0.titulo(for: .left)).tag($0.rawValue)
                        }
                    }
                    Toggle(isOn: $store.prateleiraAoArrastar) {
                        Text("Abrir ao começar a arrastar")
                        Text("Qualquer arrasto, em qualquer app, traz a prateleira. Desligado, ela só aparece encostando o cursor na borda ou pelo atalho.")
                    }
                }

                Section {
                    LabeledContent {
                        Button("Esvaziar") { modelo.esvaziar() }
                            .disabled(modelo.itens.isEmpty)
                    } label: {
                        Text("Itens guardados")
                        Text(modelo.itens.isEmpty ? "Nenhum."
                             : "\(modelo.itens.count) de até \(Prateleira.maximoDeItens). Os mais antigos saem quando passa disso.")
                    }
                } footer: {
                    Text("Clique num item para abrir (texto é copiado); arraste para levar. A alça \"Tudo\" leva todos de uma vez. Arquivos são só referenciados: a prateleira não copia nada, e um arquivo movido ou apagado some dela sozinho.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Bloco de notas

private struct NotasSettingsView: View {
    @EnvironmentObject var store: DockaStore
    @ObservedObject private var modelo = NotasModelo.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.notasControl) {
                    Text("Bloco de notas")
                    Text("Notas em abas numa lateral, salvas sozinhas enquanto você escreve, com pré-visualização de Markdown.")
                }
            }

            if store.notasControl {
                Section {
                    Picker("Lateral", selection: $store.notasBorda) {
                        ForEach(BlocoDeNotas.bordasPermitidas, id: \.self) {
                            Text($0.titulo).tag($0.rawValue)
                        }
                    }
                    Picker("Posição", selection: $store.notasAlinhamento) {
                        ForEach(TrayAlignment.allCases, id: \.self) {
                            Text($0.titulo(for: .left)).tag($0.rawValue)
                        }
                    }
                } footer: {
                    Text(store.prateleiraControl && store.prateleiraBorda == store.notasBorda
                         ? "A prateleira está na mesma lateral: as duas abrem pela mesma borda e uma pode cobrir a outra. Prefira lados opostos."
                         : "Abre encostando o cursor na borda. Com o atalho, já abre pronto para digitar.")
                }

                Section {
                    LabeledContent {
                        Button("Mostrar no Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([NotasModelo.arquivo])
                        }
                    } label: {
                        Text("Notas guardadas")
                        Text("\(modelo.notas.count) de até \(BlocoDeNotas.maximoDeNotas), num arquivo próprio em Application Support.")
                    }
                } footer: {
                    Text("Enquanto você escreve o bloco não some, mesmo com o cursor longe; Esc ou clicar em outro app devolve o teclado. O nome de cada aba é a primeira linha da nota.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Monitor do sistema

private struct MonitorSettingsView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.monitorControl) {
                    Text("Painel do sistema")
                    Text("CPU, memória e rede com gráfico dos últimos dois minutos, mais disco e bateria, num painel de borda.")
                }
                if store.monitorControl {
                    Picker("Lateral", selection: $store.monitorBorda) {
                        ForEach(Prateleira.bordasPermitidas, id: \.self) {
                            Text($0.titulo).tag($0.rawValue)
                        }
                    }
                    Picker("Posição", selection: $store.monitorAlinhamento) {
                        ForEach(TrayAlignment.allCases, id: \.self) {
                            Text($0.titulo(for: .left)).tag($0.rawValue)
                        }
                    }
                }
            } footer: {
                if store.monitorControl {
                    Text(conflito ?? "Abre encostando o cursor na borda, ou pelo atalho.")
                }
            }

            Section {
                Picker(selection: $store.leituraDaBarra) {
                    ForEach(LeituraDaBarra.allCases) { Text($0.titulo).tag($0) }
                } label: {
                    Text("Na barra de menus")
                    Text("Uma leitura ao lado do ícone do Docka, atualizada a cada 2 segundos.")
                }
            } footer: {
                Text("As medições só rodam enquanto o painel está aberto ou há uma leitura na barra — parado, o monitor não gasta nada. Tudo vem de APIs públicas do sistema, sem permissão.")
            }

            Section {
                Toggle(isOn: $store.alertas) {
                    Text("Alertas")
                    Text("Um aviso no canto da tela quando algo passa do limite. Cada alerta avisa uma vez e só volta a avisar depois que a situação normaliza.")
                }
                if store.alertas {
                    Toggle("CPU alta", isOn: $store.alertaCPU)
                    if store.alertaCPU {
                        Picker("Acima de", selection: $store.alertaCPULimite) {
                            ForEach([0.70, 0.80, 0.85, 0.90, 0.95], id: \.self) {
                                Text(Metricas.porcentagem($0)).tag($0)
                            }
                        }
                        Picker("Por", selection: $store.alertaCPUMinutos) {
                            ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) min seguidos").tag($0) }
                        }
                    }
                    Toggle("Memória apertada", isOn: $store.alertaMemoria)
                    Toggle("Disco quase cheio", isOn: $store.alertaDisco)
                    if store.alertaDisco {
                        Picker("Com menos de", selection: $store.alertaDiscoGB) {
                            ForEach([5, 10, 20, 50], id: \.self) { Text("\($0) GB livres").tag($0) }
                        }
                    }
                    Toggle("Bateria baixa", isOn: $store.alertaBateria)
                    if store.alertaBateria {
                        Picker("Em", selection: $store.alertaBateriaLimite) {
                            ForEach([0.10, 0.15, 0.20, 0.30], id: \.self) {
                                Text(Metricas.porcentagem($0)).tag($0)
                            }
                        }
                    }
                    Toggle("Mac esquentando", isOn: $store.alertaTemperatura)
                    LabeledContent {
                        Button("Mostrar um aviso de exemplo") {
                            AvisoController.shared.mostrar(Alerta(
                                tipo: .cpu, titulo: "Assim chega um alerta",
                                mensagem: "Ele some sozinho em alguns segundos, ou no ✕."))
                        }
                    } label: {
                        Text("Prévia")
                    }
                }
            } footer: {
                if store.alertas {
                    Text("O aviso é do próprio Docka, e não uma notificação do sistema — as notificações pediriam autorização. CPU, disco e bateria são lidos a cada 10 segundos; memória e temperatura chegam como evento do sistema.")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Avisa quando o painel cai no mesmo lugar de outro painel de borda.
    private var conflito: String? {
        let lugar = (store.monitorBorda, store.monitorAlinhamento)
        if store.prateleiraControl && (store.prateleiraBorda, store.prateleiraAlinhamento) == lugar {
            return "A prateleira está na mesma lateral e posição: um painel cobriria o outro. Mude um deles."
        }
        if store.notasControl && (store.notasBorda, store.notasAlinhamento) == lugar {
            return "O bloco de notas está na mesma lateral e posição: um painel cobriria o outro. Mude um deles."
        }
        return nil
    }
}

// MARK: - Área de transferência

private struct ClipboardSettingsView: View {
    @EnvironmentObject var store: DockaStore
    @ObservedObject private var historico = HistoricoModelo.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.historicoControl) {
                    Text("Histórico")
                    Text("Guarda textos, links e arquivos que você copia. O atalho abre a lista com busca; escolher um item o põe de volta na área de transferência, pronto para ⌘V.")
                }
                if store.historicoControl {
                    Picker("Guardar até", selection: $store.historicoLimite) {
                        ForEach([25, 50, 100, 200], id: \.self) { Text("\($0) itens").tag($0) }
                    }
                    Toggle(isOn: $store.historicoLembrar) {
                        Text("Lembrar entre aberturas")
                        Text("Grava o histórico num arquivo em Application Support. Desligado, ele vive só enquanto o Docka está aberto.")
                    }
                    LabeledContent {
                        HStack {
                            Button("Abrir") { HistoricoController.shared.abrir() }
                            Button("Apagar…", role: .destructive) { historico.apagarHistorico() }
                                .disabled(historico.itens.allSatisfy(\.fixado))
                        }
                    } label: {
                        Text("Itens guardados")
                        Text("\(historico.itens.count), \(historico.itens.filter(\.fixado).count) fixados. Apagar mantém os fixados.")
                    }
                }
            } footer: {
                Text("Senhas copiadas de gerenciadores (1Password, Bitwarden, Senhas da Apple e outros que seguem a convenção nspasteboard.org) não entram no histórico. Ler a área de transferência não pede permissão.")
            }

            Section {
                Toggle(isOn: $store.limparLinksAoCopiar) {
                    Text("Limpar links ao copiar")
                    Text("Tira utm_, fbclid, gclid e outros rastreadores de todo link copiado, sozinho.")
                }
                Picker(selection: Binding(get: { ApagarClipboard(persisted: store.apagarClipboard) },
                                          set: { store.apagarClipboard = $0.rawValue })) {
                    ForEach(ApagarClipboard.allCases) { Text($0.titulo).tag($0) }
                } label: {
                    Text("Apagar a área de transferência")
                    Text("Esvazia o que está copiado depois de um tempo — o histórico continua com ele.")
                }
                Toggle(isOn: $store.apagarAoBloquear) {
                    Text("Apagar ao travar a tela ou dormir")
                    Text("Quem usar o Mac depois não cola o que ficou copiado. O histórico continua.")
                }
            } header: {
                Text("Privacidade")
            }

            SecaoColarSozinho()

            SecaoDeSnippets()

            SecaoDeGatilhos()

            Section {
                LabeledContent {
                    Button("Aplicar agora") { HistoricoModelo.shared.soTexto() }
                } label: {
                    Text("Colar sem formatação")
                    Text("Troca o que está copiado pela versão em texto puro — sem negrito, cor nem fonte. Também tem atalho.")
                }
                LabeledContent {
                    Button("Aplicar agora") { HistoricoModelo.shared.limparLinkCopiado() }
                } label: {
                    Text("Limpar o link copiado")
                    Text("Tira os rastreadores do link que está na área de transferência agora.")
                }
            } header: {
                Text("Ferramentas")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Janelas

private struct JanelasSettingsView: View {
    @EnvironmentObject var store: DockaStore
    @State private var permitido = Colagem.permitido
    private let relogio = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.janelasControl) {
                    Text("Encaixar janelas")
                    Text("Atalhos e um menu na barra para mandar a janela da frente para metades, quartos e terços, maximizar, centralizar, levar para outra tela e voltar ao tamanho de antes.")
                }
                if store.janelasControl {
                    LabeledContent {
                        if !permitido {
                            Button("Abrir Privacidade") { Colagem.abrirAjustesDePrivacidade() }
                        }
                    } label: {
                        Label(permitido ? "Acessibilidade concedida" : "Falta conceder a Acessibilidade",
                              systemImage: permitido ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(permitido ? .green : .orange)
                    }
                }
            } header: {
                Text("Módulo com permissão")
            } footer: {
                Text("Mover a janela de outro app exige a permissão de Acessibilidade — a mesma do \"Colar sozinho\". Repetir o atalho de uma metade alterna a largura entre ½, ⅓ e ⅔.")
            }
            .onReceive(relogio) { _ in
                if permitido != Colagem.permitido {
                    permitido = Colagem.permitido
                    ArrastoDeJanelas.shared.sincronizar()
                }
            }

            Section {
                Toggle(isOn: $store.arrastarComTecla) {
                    Text("Arrastar segurando teclas")
                    Text("Segure as teclas e arraste de qualquer ponto da janela para movê-la — sem mirar na barra de título. Pede Acessibilidade.")
                }
                if store.arrastarComTecla {
                    Picker("Teclas", selection: $store.arrastarTeclas) {
                        ForEach(TeclasDoArrasto.allCases) { Text($0.simbolo).tag($0.rawValue) }
                    }
                    Toggle(isOn: $store.arrastarRedimensiona) {
                        Text("Botão direito redimensiona")
                        Text("Com as mesmas teclas, o botão direito puxa o canto da janela mais perto do clique.")
                    }
                }
            } footer: {
                Text("Sem as teclas, nenhum clique é tocado. Com elas, o clique não chega ao app de baixo — só move a janela.")
            }

            if store.janelasControl {
                Section {
                    Toggle(isOn: $store.janelasArrastar) {
                        Text("Encaixar arrastando até a borda")
                        Text("Leve a janela pela barra de título até a borda: laterais dão metades, cantos dão quartos, o topo maximiza. Uma prévia mostra onde ela vai parar.")
                    }
                } footer: {
                    Text("A borda de baixo sozinha não encaixa — é onde mora o Dock, e soltar ali por acidente é comum.")
                }
                Section {
                    Toggle(isOn: $store.botaoVerdeMaximiza) {
                        Text("O botão verde maximiza")
                        Text("Preenche a tela sem criar outro Espaço; clicar de novo volta ao tamanho de antes. Com ⌥, o botão faz o de sempre.")
                    }
                }
            }

            if store.janelasControl {
                ForEach(LayoutDeJanela.grupos.indices, id: \.self) { g in
                    Section(g == 0 ? "Atalhos" : "") {
                        ForEach(LayoutDeJanela.grupos[g]) { l in
                            LabeledContent {
                                ShortcutRecorder(acao: .janela(l))
                            } label: {
                                Label(l.titulo, systemImage: l.simbolo)
                            }
                            if let erro = store.erroDoAtalho(.janela(l)) {
                                Label(erro, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange).font(.callout)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Captura

private struct CapturaSettingsView: View {
    @EnvironmentObject var store: DockaStore
    @State private var permitido = CapturaController.permitido
    private let relogio = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.capturaControl) {
                    Text("Captura")
                    Text("Conta-gotas, texto da tela (com leitor de QR) e captura de área — pelo menu Captura na barra ou por atalho.")
                }
                if store.capturaControl {
                    LabeledContent {
                        if !permitido {
                            Button("Abrir Privacidade") { CapturaController.abrirAjustesDePrivacidade() }
                        }
                    } label: {
                        Label(permitido ? "Gravação de Tela concedida" : "Falta conceder a Gravação de Tela",
                              systemImage: permitido ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(permitido ? .green : .orange)
                    }
                }
            } header: {
                Text("Módulo com permissão")
            } footer: {
                Text("O texto da tela e a captura de área precisam de Gravação de Tela: sem ela, o macOS entrega só o fundo da mesa. O conta-gotas não precisa de nada. O reconhecimento de texto roda no próprio Mac — nenhuma imagem sai daqui. Pode ser preciso reabrir o Docka depois de conceder.")
            }
            .onReceive(relogio) { _ in permitido = CapturaController.permitido }

            if store.capturaControl {
                Section("Conta-gotas") {
                    Picker("Copiar a cor como", selection: $store.formatoDeCor) {
                        ForEach(FormatoDeCor.allCases) { Text($0.titulo).tag($0.rawValue) }
                    }
                    linha(.contaGotas, "Atalho do conta-gotas")
                }
                Section("Texto da tela") {
                    linha(.textoDaTela, "Atalho")
                }
                Section("Captura de área") {
                    Toggle(isOn: $store.capturaEditar) {
                        Text("Abrir no editor de anotação")
                        Text("Seta, retângulo, caneta, marca-texto, texto, borrão e recorte; depois copie ou salve. O borrão pixeliza de verdade — quem recebe não recupera o que estava embaixo.")
                    }
                    if !store.capturaEditar {
                        Toggle(isOn: $store.capturaNaMesa) {
                            Text("Salvar na Mesa")
                            Text("Desligado, a captura vai para a área de transferência.")
                        }
                    }
                    linha(.capturaArea, "Atalho")
                }
                Section {
                    Toggle(isOn: $store.gravacaoSomDoSistema) {
                        Text("Gravar o som do Mac")
                        Text("O que os apps tocam, numa faixa própria; o som do Docka fica de fora.")
                    }
                    Toggle(isOn: $store.gravacaoMicrofone) {
                        Text("Gravar o microfone")
                        Text("Numa faixa separada do som do Mac. O macOS pede o acesso ao microfone na primeira vez.")
                    }
                    Toggle("Mostrar os cliques", isOn: $store.gravacaoCliques)
                    Picker("Quadros por segundo", selection: $store.gravacaoQuadros) {
                        Text("30").tag(30)
                        Text("60").tag(60)
                    }
                    Picker("Ao terminar", selection: $store.gravacaoDepois) {
                        Text("Mostrar no Finder").tag("finder")
                        Text("Abrir o vídeo").tag("abrir")
                        Text("Só avisar").tag("nada")
                    }
                    linha(.gravarTela, "Atalho (de novo para parar)")
                    LabeledContent("Testar") {
                        Button("Gravar agora…") { GravacaoController.shared.escolherArea() }
                    }
                } header: {
                    Text("Gravação de tela")
                } footer: {
                    Text("Arraste para gravar uma área ou clique para gravar a tela inteira; um controle pequeno no topo mostra o tempo e para. O vídeo (.mov, HEVC) vai para a pasta das capturas do macOS. As janelas do Docka não aparecem na gravação. Pede o macOS 15 ou mais novo.")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func linha(_ acao: AcaoDeAtalho, _ titulo: String) -> some View {
        LabeledContent(titulo) { ShortcutRecorder(acao: acao) }
        if let erro = store.erroDoAtalho(acao) {
            Label(erro, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
        }
    }
}

// MARK: - Mouse

private struct MouseSettingsView: View {
    @EnvironmentObject var store: DockaStore
    @State private var permitido = Colagem.permitido
    private let relogio = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.mouseControl) {
                    Text("Ajustes do mouse")
                    Text("Rolagem e botões do mouse com fio ou Bluetooth. O trackpad e o Magic Mouse ficam como estão.")
                }
                if store.mouseControl {
                    LabeledContent {
                        if !permitido {
                            Button("Abrir Privacidade") { Colagem.abrirAjustesDePrivacidade() }
                        }
                    } label: {
                        Label(permitido ? "Acessibilidade concedida" : "Falta conceder a Acessibilidade",
                              systemImage: permitido ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(permitido ? .green : .orange)
                    }
                }
            } header: {
                Text("Módulo com permissão")
            } footer: {
                Text("Mudar a rolagem e os cliques de outros apps exige interceptar esses eventos, o que só a Acessibilidade permite. Só eventos do mouse passam pelo Docka — o teclado não.")
            }
            .onReceive(relogio) { _ in
                if permitido != Colagem.permitido {
                    permitido = Colagem.permitido
                    MouseController.shared.sincronizar()   // concedeu agora: liga sem reabrir
                }
            }

            if store.mouseControl {
                Section("Rolagem") {
                    Toggle("Inverter a rolagem vertical", isOn: $store.mouseInverterVertical)
                    Toggle("Inverter a rolagem horizontal", isOn: $store.mouseInverterHorizontal)
                    Picker(selection: $store.mouseLinhas) {
                        Text("Do sistema (com aceleração)").tag(0)
                        ForEach([1, 3, 5, 10], id: \.self) { Text("\($0) \($0 == 1 ? "linha" : "linhas") por dente").tag($0) }
                    } label: {
                        Text("Rolagem linear")
                        Text("Cada dente da roda rola sempre o mesmo, por mais rápido que se gire.")
                    }
                    Toggle(isOn: $store.mouseSuave) {
                        Text("Rolagem suave")
                        Text("Cada dente vira um deslize curto, em vez de um salto.")
                    }
                    Picker(selection: $store.mouseDeLado) {
                        Text("Nenhuma").tag(0)
                        Text("⌥ Option").tag(Int(Shortcut.Modifiers.option.rawValue))
                        Text("⌃ Control").tag(Int(Shortcut.Modifiers.control.rawValue))
                        Text("⌘ Command").tag(Int(Shortcut.Modifiers.command.rawValue))
                    } label: {
                        Text("Rolar de lado segurando")
                        Text("A roda rola na horizontal enquanto a tecla está apertada. (⇧ já faz isso no macOS.)")
                    }
                }
                Section {
                    Toggle(isOn: $store.mouseBotoes) {
                        Text("Botões laterais voltam e avançam")
                        Text("No Finder, no Safari, no Chrome e em outros apps que entendem ⌘[ e ⌘].")
                    }
                } header: {
                    Text("Botões")
                } footer: {
                    if store.orbitaControl && BotaoDoMouse.valido(store.orbitaBotao) {
                        Text("O \(BotaoDoMouse.nome(store.orbitaBotao).lowercased()) abre a Órbita e continua com ela.")
                    }
                }
                Section {
                    ForEach(MouseETeclado.botoesConfiguraveis.prefix(4), id: \.self) { b in
                        Picker(MouseETeclado.nomeDoBotao(b), selection: Binding(
                            get: { store.mouseAcoesDosBotoes[String(b)] ?? MouseETeclado.AcaoDoBotao.nada.rawValue },
                            set: { store.mouseAcoesDosBotoes[String(b)] = $0 })) {
                            ForEach(MouseETeclado.AcaoDoBotao.allCases) { Text($0.titulo).tag($0.rawValue) }
                        }
                    }
                } header: {
                    Text("O que cada botão faz")
                } footer: {
                    Text("\"O de sempre\" deixa o botão como estava (inclusive voltar e avançar, se ligados acima). O botão que abre a Órbita continua com ela.")
                }
                SecaoDeAppsIgnorados()
            }

            Section {
                Toggle(isOn: $store.focoSegueMouse) {
                    Text("O foco segue o mouse")
                    Text("Parar o cursor sobre a janela de outro app traz esse app para a frente — sem clicar. Arrastando algo ou segurando uma tecla, nada muda.")
                }
                if store.focoSegueMouse {
                    Picker("Depois de parado por", selection: $store.focoAtraso) {
                        Text("Na hora").tag(0.1)
                        Text("0,3 segundo").tag(0.3)
                        Text("Meio segundo").tag(0.5)
                        Text("Um segundo").tag(1.0)
                    }
                }
                Toggle(isOn: $store.filtroDeClique) {
                    Text("Filtrar o clique duplo acidental")
                    Text("Para mouses com o botão gasto, que dão dois cliques num só: um segundo clique que chega em poucos milissegundos, no mesmo lugar, é descartado. O clique duplo de propósito continua funcionando.")
                }
                if store.filtroDeClique {
                    LabeledContent("Janela do repique") {
                        Slider(value: $store.filtroDeCliqueMs, in: 30...120, step: 5).frame(width: 200)
                        Text("\(Int(store.filtroDeCliqueMs)) ms").monospacedDigit().frame(width: 50)
                    }
                }
                Toggle(isOn: $store.cliqueDoMeio) {
                    Text("Clique com três dedos é o clique do meio")
                    Text("No trackpad, clicar com três dedos encostados vira o clique do meio — abrir link em nova aba, fechar aba no navegador.")
                }
            } header: {
                Text("Mais do mouse")
            } footer: {
                Text("Estes três pedem Acessibilidade e funcionam mesmo com o módulo do mouse desligado.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Ajustes → Finder: recortar e colar arquivos, e o instalador de .dmg.
private struct FinderSettingsView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.recorteNoFinder) {
                    Text("⌘X e ⌘V movem arquivos")
                    Text("No Finder, ⌘X marca os arquivos e o ⌘V em outra pasta move-os para lá — sem lembrar do ⌥⌘V. Renomeando um arquivo, ⌘X continua recortando o texto. Pede Acessibilidade.")
                }
            } header: {
                Text("Recortar e colar")
            }
            Section {
                Toggle(isOn: $store.instaladorDeDmg) {
                    Text("Oferecer instalar ao abrir um .dmg")
                    Text("Abrindo uma imagem de disco que traz um app, o Docka oferece copiá-lo para Aplicativos e ejetar a imagem. Uma versão antiga já instalada vai para o Lixo, de onde dá para recuperar.")
                }
                if store.instaladorDeDmg {
                    Toggle("Depois de instalar, mandar o .dmg para o Lixo", isOn: $store.dmgParaOLixo)
                }
            } header: {
                Text("Imagem de disco")
            }
        }
        .formStyle(.grouped)
    }
}

/// Ajustes → Teclado: repique de teclas e a tecla super.
private struct TecladoSettingsView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.repiqueDeTeclas) {
                    Text("Ignorar o repique das teclas")
                    Text("Para teclados que repetem a letra sem querer: a mesma tecla de novo em poucos milissegundos é descartada. Segurar a tecla para repetir continua funcionando.")
                }
                if store.repiqueDeTeclas {
                    LabeledContent("Janela do repique") {
                        Slider(value: $store.repiqueMs, in: 20...100, step: 5).frame(width: 200)
                        Text("\(Int(store.repiqueMs)) ms").monospacedDigit().frame(width: 50)
                    }
                }
            } header: {
                Text("Repique")
            }
            Section {
                Toggle(isOn: $store.teclaSuper) {
                    Text("Caps Lock vira a tecla super (⌃⌥⇧⌘)")
                    Text("Segurar o Caps Lock aperta ⌃⌥⇧⌘ de uma vez — quatro modificadores num dedo só, para atalhos que nenhum app usa. O Caps Lock deixa de travar as maiúsculas enquanto a opção estiver ligada, e volta ao normal ao desligar ou ao fechar o Docka.")
                }
            } header: {
                Text("Tecla super")
            } footer: {
                Text("Pedem Acessibilidade. Os atalhos com ⌃⌥⇧⌘ podem ser gravados nos ajustes de Atalhos do Docka ou de qualquer app.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Apps em que o mouse fica como o sistema manda — um jogo, um app de
/// desenho que já trata a roda do jeito dele.
private struct SecaoDeAppsIgnorados: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Section {
            ForEach(store.mouseIgnorados, id: \.self) { id in
                HStack {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 20, height: 20)
                        Text(FileManager.default.displayName(atPath: url.path))
                    } else {
                        Text(id)
                    }
                    Spacer()
                    Button { store.mouseIgnorados.removeAll { $0 == id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Adicionar app…") { escolher() }
        } header: {
            Text("Apps a ignorar")
        } footer: {
            Text("Com um destes apps na frente, a rolagem e os botões ficam como o sistema manda.")
        }
    }

    private func escolher() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowsMultipleSelection = true
        p.prompt = "Ignorar"
        guard p.runModal() == .OK else { return }
        for url in p.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !store.mouseIgnorados.contains(id) {
                store.mouseIgnorados.append(id)
            }
        }
    }
}

// MARK: - Ao fechar

/// Uma lista de apps escolhidos, com adicionar e tirar.
private struct ListaDeApps: View {
    @Binding var ids: [String]
    let prompt: String
    var excluir: Set<String> = []

    var body: some View {
        ForEach(ids, id: \.self) { id in
            HStack {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                    Text(FileManager.default.displayName(atPath: url.path))
                } else {
                    Text(id)
                }
                Spacer()
                Button { ids.removeAll { $0 == id } } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        Button("Adicionar app…") {
            let p = NSOpenPanel()
            p.allowedContentTypes = [.application]
            p.directoryURL = URL(fileURLWithPath: "/Applications")
            p.allowsMultipleSelection = true
            p.prompt = prompt
            guard p.runModal() == .OK else { return }
            for url in p.urls {
                if let id = Bundle(url: url)?.bundleIdentifier, !ids.contains(id), !excluir.contains(id) { ids.append(id) }
            }
        }
    }
}

private struct EncerrarSettingsView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.sairAoFecharControl) {
                    Text("Sair ao fechar a última janela")
                    Text("Os apps da lista são encerrados quando a última janela deles fecha. Um app com trabalho não salvo pergunta antes, como sempre.")
                }
                if store.sairAoFecharControl {
                    ListaDeApps(ids: $store.sairAoFecharApps, prompt: "Escolher", excluir: SairAoFechar.nuncaEncerrar)
                }
            } header: {
                Text("Sair ao fechar")
            } footer: {
                Text("O Finder e o Dock nunca entram. Pede Acessibilidade, para contar as janelas de cada app.")
            }

            Section {
                Toggle("Proteger o ⌘Q (encerrar)", isOn: $store.protecaoQ)
                Toggle("Proteger o ⌘W (fechar janela)", isOn: $store.protecaoW)
                if store.protecaoQ || store.protecaoW {
                    Picker("Para confirmar", selection: $store.protecaoModo) {
                        ForEach(ModoDeProtecao.allCases) { Text($0.titulo).tag($0.rawValue) }
                    }
                }
            } header: {
                Text("Proteção contra ⌘Q e ⌘W sem querer")
            } footer: {
                Text("Segurar: mantenha o atalho apertado até a barra encher. Duas vezes: aperte de novo em até 1 s. Com ⌥: use ⌥⌘Q. Pede Acessibilidade para interceptar só esses dois atalhos — as outras teclas passam direto, sem serem guardadas.")
            }

            if store.protecaoQ || store.protecaoW {
                Section {
                    ListaDeApps(ids: $store.protecaoApps, prompt: "Proteger")
                } header: {
                    Text("Só nestes apps")
                } footer: {
                    Text(store.protecaoApps.isEmpty ? "Lista vazia: a proteção vale em todos os apps." : "A proteção vale só nos apps da lista.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dock

private struct DockSettingsView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.previaDoDock) {
                    Text("Prévia das janelas")
                    Text("Pare o cursor num ícone de app no Dock para ver as janelas dele. Clique numa para trazê-la para a frente — minimizada, ela volta do Dock; o × fecha.")
                }
                if store.previaDoDock {
                    Picker("Aparece depois de", selection: $store.previaDoDockAtraso) {
                        Text("Na hora").tag(0.15)
                        Text("Meio segundo").tag(0.5)
                        Text("Um segundo").tag(1.0)
                    }
                    Toggle(isOn: $store.previaDoDockMiniaturas) {
                        Text("Miniaturas das janelas")
                        Text("Pede Gravação de Tela. Sem ela, cada janela aparece com o ícone do app e o título.")
                    }
                }
            } header: {
                Text("Prévia do Dock")
            } footer: {
                Text("Pede Acessibilidade, para saber sobre qual ícone o cursor está e listar as janelas. As miniaturas ficam só na memória, enquanto a prévia está aberta.")
            }
            Section {
                Toggle(isOn: $store.cliquesNoDock) {
                    Text("Clicar no ícone do app ativo")
                    Text("Com o app já na frente e janela à vista, clicar no ícone dele no Dock faz a ação abaixo. Nos outros casos, o Dock faz o de sempre.")
                }
                if store.cliquesNoDock {
                    Picker("Ação", selection: $store.acaoNoCliqueDoDock) {
                        ForEach(AcaoNoCliqueDoDock.allCases) { Text($0.titulo).tag($0.rawValue) }
                    }
                }
            } header: {
                Text("Cliques no Dock")
            } footer: {
                Text("Vale para o Dock da Apple, não para as bandejas do Docka. Pede Acessibilidade, para saber qual ícone foi clicado.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlternadorSettingsView: View {
    var body: some View {
        Form { SecaoDoAlternador() }.formStyle(.grouped)
    }
}

private struct SecaoDoAlternador: View {
    @EnvironmentObject var store: DockaStore

    /// ⌥Tab: a sugestão — perto do ⌘Tab na mão, sem tomar o lugar dele.
    private let sugestao = Shortcut(keyCode: 48, modifiers: [.option])

    var body: some View {
        Section {
            Toggle(isOn: $store.alternadorControl) {
                Text("Alternador de apps")
                Text("Segure o modificador do atalho, aperte de novo para avançar (⇧ volta) e solte para trocar. Os apps vêm na ordem em que você os usou. Digite para buscar pelo nome ou pelo título — aí ↩ escolhe.")
            }
            if store.alternadorControl {
                LabeledContent {
                    HStack {
                        ShortcutRecorder(acao: .alternador)
                        if store.atalho(de: .alternador) == nil {
                            Button("Usar ⌥Tab") { store.definirAtalho(sugestao, para: .alternador) }
                        }
                    }
                } label: {
                    Text("Atalho")
                    Text("Precisa de ⌘, ⌥ ou ⌃: é soltando ele que a troca acontece.")
                }
                if let erro = store.erroDoAtalho(.alternador) {
                    Label(erro, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
                Toggle(isOn: $store.alternadorJanelas) {
                    Text("Mostrar cada janela")
                    Text("Uma entrada por janela, com o título, e a escolhida vem para a frente. Pede Acessibilidade; sem ela, o alternador troca de app.")
                }
                Toggle(isOn: $store.alternadorSoTela) {
                    Text("Só a tela do cursor")
                    Text("Mostra apenas o que está no monitor onde o cursor está. Pede Acessibilidade.")
                }
                Toggle(isOn: $store.alternadorSemJanela) {
                    Text("Esconder apps sem janela")
                    Text("Apps abertos sem nenhuma janela ficam de fora. Pede Acessibilidade.")
                }
                Toggle(isOn: $store.alternadorPrevias) {
                    Text("Prévias das janelas")
                    Text("Uma miniatura de cada janela no lugar do ícone. Pede Gravação de Tela; sem ela, ficam os ícones. As imagens não saem do Mac nem ficam gravadas.")
                }
            }
        } header: {
            Text("Alternador")
        } footer: {
            Text("Não substitui o ⌘Tab do sistema — interceptá-lo exigiria ler o teclado inteiro. O alternador abre na hora com os ícones; as prévias chegam em seguida.")
        }
    }
}

/// O módulo com permissão: o interruptor, o estado da Acessibilidade e o
/// caminho para concedê-la.
private struct SecaoColarSozinho: View {
    @EnvironmentObject var store: DockaStore
    @State private var permitido = Colagem.permitido
    private let relogio = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            Toggle(isOn: $store.colarSozinho) {
                Text("Colar sozinho")
                Text("Ao escolher no histórico ou num snippet, o Docka cola direto no app da frente, em vez de só deixar pronto para o ⌘V.")
            }
            if store.colarSozinho {
                LabeledContent {
                    if !permitido {
                        Button("Abrir Privacidade") { Colagem.abrirAjustesDePrivacidade() }
                    }
                } label: {
                    Label(permitido ? "Acessibilidade concedida" : "Falta conceder a Acessibilidade",
                          systemImage: permitido ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(permitido ? .green : .orange)
                }
            }
        } header: {
            Text("Módulo com permissão")
        } footer: {
            Text("Mandar um ⌘V para outro app exige a permissão de Acessibilidade — é a única coisa que o Docka faz com ela. Sem a permissão, nada quebra: o item só fica copiado. Com o Docka assinado sem certificado de desenvolvedor, o macOS pode pedir a permissão de novo a cada versão nova.")
        }
        // a permissão é dada nos Ajustes do Sistema, fora do Docka: relê sozinho
        .onReceive(relogio) { _ in permitido = Colagem.permitido }
    }
}

/// O módulo mais sensível: escuta o teclado para achar os gatilhos.
private struct SecaoDeGatilhos: View {
    @EnvironmentObject var store: DockaStore
    @State private var escuta = GatilhosController.podeEscutar
    @State private var acessibilidade = Colagem.permitido
    private let relogio = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            Toggle(isOn: $store.gatilhosControl) {
                Text("Expandir gatilhos digitados")
                Text("Digitar o gatilho de um snippet (como ;hoje) em qualquer app troca ele pelo texto.")
            }
            if store.gatilhosControl {
                linha(escuta, "Monitoramento de Entrada", "ver as teclas") { GatilhosController.abrirAjustesDeEscuta() }
                linha(acessibilidade, "Acessibilidade", "apagar o gatilho e colar") { Colagem.abrirAjustesDePrivacidade() }
            }
        } header: {
            Text("Módulo com permissão")
        } footer: {
            Text("Para achar o gatilho, o Docka vê cada tecla digitada — e guarda só os últimos 32 caracteres, na memória, sem gravar nem enviar nada. Campos de senha ficam de fora: neles o macOS não entrega as teclas a ninguém. Atalhos com ⌘ ou ⌃, setas, ↩ e cliques zeram o que foi guardado.")
        }
        .onReceive(relogio) { _ in
            let e = GatilhosController.podeEscutar, a = Colagem.permitido
            if e != escuta || a != acessibilidade {
                escuta = e; acessibilidade = a
                GatilhosController.shared.sincronizar()
            }
        }
    }

    private func linha(_ ok: Bool, _ nome: String, _ para: String, abrir: @escaping () -> Void) -> some View {
        LabeledContent {
            if !ok { Button("Abrir Privacidade", action: abrir) }
        } label: {
            Label(ok ? "\(nome) concedido — para \(para)" : "Falta \(nome) — para \(para)",
                  systemImage: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}

/// Lista e editor dos snippets.
private struct SecaoDeSnippets: View {
    @ObservedObject private var modelo = SnippetsModelo.shared
    @State private var editando: UUID?

    var body: some View {
        Section {
            ForEach($modelo.lista) { $s in
                DisclosureGroup(isExpanded: Binding(get: { editando == s.id },
                                                    set: { editando = $0 ? s.id : nil })) {
                    TextField("Nome", text: $s.nome)
                    TextField("Gatilho (opcional, ex.: ;email)", text: $s.gatilho)
                        .font(.system(size: 12, design: .monospaced))
                    if !s.gatilho.isEmpty && !Snippets.gatilhoValido(s.gatilho, entre: modelo.lista, ignorando: s.id) {
                        Label("Gatilho sem espaço, de 2 a 20 caracteres, que não seja o começo de outro.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.caption)
                    }
                    TextEditor(text: $s.texto)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 70)
                    HStack {
                        Text("Prévia: \(SnippetsModelo.expandido(s))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Button("Apagar", role: .destructive) { modelo.remover(s.id) }
                    }
                } label: {
                    HStack {
                        Text(s.nome)
                        if !s.gatilho.isEmpty {
                            Text(s.gatilho).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Button("Novo snippet") { editando = modelo.novo().id }
                Spacer()
                Button("Abrir a lista") { SnippetsController.shared.abrir() }
                    .disabled(modelo.lista.isEmpty)
            }
        } header: {
            Text("Snippets")
        } footer: {
            Text("Textos prontos, escolhidos pelo atalho dos snippets. Variáveis: " + Snippets.variaveis.map { "\($0.chave) — \($0.descricao)" }.joined(separator: "; ") + ". Com gatilhos, digitar o gatilho em qualquer app troca ele pelo texto — veja o módulo abaixo.")
        }
    }
}

// MARK: - Brilho e volume

/// A mesma página para os dois controles de borda: o que muda entre eles cabe
/// no `Deslizador`, então uma página só evita que as duas se desencontrem.
private struct DeslizadorView: View {
    let deslizador: Deslizador
    @EnvironmentObject var store: DockaStore

    private var ligado: Bool { store[keyPath: deslizador.ligado] }
    private var disponivel: Bool { deslizador.disponivel() }

    var body: some View {
        Form {
            if !disponivel {
                Section {
                    Label(deslizador.avisoIndisponivel,
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle(isOn: interruptor) {
                    Text("Controle de \(deslizador.titulo.lowercased())")
                    Text(deslizador.descricao)
                }
            }

            if ligado && disponivel {
                Section {
                    Picker("Lateral", selection: escolha(deslizador.borda)) {
                        ForEach(Deslizante.bordasPermitidas, id: \.self) {
                            Text($0.titulo).tag($0.rawValue)
                        }
                    }
                    Picker("Posição", selection: escolha(deslizador.alinhamento)) {
                        ForEach(TrayAlignment.allCases, id: \.self) {
                            Text($0.titulo(for: .left)).tag($0.rawValue)
                        }
                    }
                } footer: {
                    Text(rodapeDaPosicao)
                }

                Section {
                    LabeledContent("Nível") {
                        HStack(spacing: 14) {
                            ReguaVertical(deslizador: deslizador, level: nivel,
                                          comprimento: 190, espessura: 46)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(Int(nivel.wrappedValue * 100))%")
                                    .font(.title3).monospacedDigit()
                                Button("Reler do sistema") {
                                    if let real = deslizador.ler() {
                                        store[keyPath: deslizador.nivel] = real
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text(deslizador.nota)
                }
            }

            if deslizador.id == "brilho" {
                TelasDeBrilhoSection()
            }
        }
        .formStyle(.grouped)
    }

    /// Avisa quando os dois controles caem na mesma lateral e posição: eles não
    /// se cobrem (o volume se acomoda ao lado), mas o usuário merece saber por
    /// que o painel não apareceu onde ele pediu.
    private var rodapeDaPosicao: String {
        let base = "Só laterais: a régua é vertical, e deitada na borda inferior viraria outra coisa."
        let mesmaBorda = store.brightnessEdge == store.volumeEdge
        let mesmaPosicao = store.brightnessAlignment == store.volumeAlignment
        guard store.brightnessControl && store.volumeControl && mesmaBorda && mesmaPosicao else {
            return base
        }
        return base + " Brilho e volume estão na mesma lateral e na mesma posição: o volume se acomoda logo ao lado do brilho para os dois caberem."
    }

    private var nivel: Binding<Double> {
        Binding(get: { store[keyPath: deslizador.nivel] },
                set: { store[keyPath: deslizador.nivel] = $0 })
    }

    private var interruptor: Binding<Bool> {
        Binding(get: { store[keyPath: deslizador.ligado] },
                set: { novo in
                    if deslizador.id == "volume" { store.volumeControl = novo }
                    else { store.brightnessControl = novo }
                })
    }

    private func escolha(_ kp: KeyPath<DockaStore, String>) -> Binding<String> {
        Binding(get: { store[keyPath: kp] },
                set: { novo in
                    switch kp {
                    case \DockaStore.brightnessEdge:      store.brightnessEdge = novo
                    case \DockaStore.brightnessAlignment: store.brightnessAlignment = novo
                    case \DockaStore.volumeEdge:          store.volumeEdge = novo
                    case \DockaStore.volumeAlignment:     store.volumeAlignment = novo
                    default: break
                    }
                })
    }
}

// MARK: - Energia

private struct EnergiaView: View {
    @EnvironmentObject var store: DockaStore
    @ObservedObject private var sessao = AcordadoSessao.shared

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if sessao.ativo {
                        Button("Desligar") { sessao.desligar() }
                    } else {
                        Button("Ligar") { store.alternarAcordado() }
                    }
                } label: {
                    Text("Manter acordado")
                    Text(sessao.ativo
                         ? "Ligado — \(sessao.fim == nil ? "até você desligar" : "faltam \(sessao.restante)")."
                         : "Impede o Mac de dormir sozinho enquanto estiver ligado.")
                }

                Picker(selection: $store.acordadoDuracao) {
                    ForEach(DuracaoAcordado.allCases) { d in Text(d.titulo).tag(d) }
                } label: {
                    Text("Duração padrão")
                    Text("Usada pelo atalho e pelo botão acima. O menu da barra oferece todas.")
                }

                Toggle(isOn: $store.acordadoTelaAcesa) {
                    Text("Manter a tela acesa")
                    Text("Desligado, só o sistema fica acordado: downloads e builds continuam, mas a tela apaga.")
                }
            } footer: {
                Text("Usa a mesma asserção de energia do caffeinate, sem permissão. Encerrar o Docka libera o Mac na hora; fechar a tampa ainda faz o Mac dormir.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Som

/// O que a página de som mostra, relido quando um dispositivo muda.
private final class SomEstado: ObservableObject {
    @Published var saidas: [SaidasDeAudio.Saida] = []
    @Published var entradas: [SomController.Entrada] = []
    @Published var entradaAtual: AudioObjectID?
    @Published var nivel: Double = 0
    @Published var nivelAjustavel = false
    @Published var mudos = false
    private var observador: NSObjectProtocol?

    init() {
        reler()
        observador = NotificationCenter.default.addObserver(forName: .somMudou, object: nil, queue: .main) { [weak self] _ in
            self?.reler()
        }
    }

    func reler() {
        saidas = SaidasDeAudio.lista()
        entradas = SomController.entradas()
        entradaAtual = SomController.entradaPadrao
        nivelAjustavel = entradaAtual.map(SomController.nivelAjustavel) ?? false
        nivel = Double(entradaAtual.flatMap(SomController.nivel) ?? 0)
        mudos = SomController.shared.microfonesMudos
    }
}

/// Ajustes → Som: a saída de cada app, a troca de saída, os fones e os microfones.
private struct SomSettingsView: View {
    @EnvironmentObject var store: DockaStore
    @StateObject private var som = SomEstado()

    private var appsComRegra: [String] { store.saidaPorApp.keys.sorted { nome($0) < nome($1) } }

    var body: some View {
        Form {
            Section {
                ForEach(appsComRegra, id: \.self) { bundle in
                    LabeledContent {
                        HStack {
                            Picker("Saída", selection: Binding(
                                get: { store.saidaPorApp[bundle] ?? "" },
                                set: { store.saidaPorApp[bundle] = $0 })) {
                                ForEach(som.saidas) { s in Text(s.nome).tag(s.uid) }
                                if let uid = store.saidaPorApp[bundle], !som.saidas.contains(where: { $0.uid == uid }) {
                                    Text("Desconectada").tag(uid)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                            Button {
                                store.saidaPorApp[bundle] = nil
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remover")
                        }
                    } label: {
                        Label {
                            Text(nome(bundle))
                        } icon: {
                            Image(nsImage: icone(bundle)).resizable().frame(width: 18, height: 18)
                        }
                    }
                }
                Menu("Adicionar app") {
                    ForEach(appsAbertos(), id: \.self) { bundle in
                        Button(nome(bundle)) {
                            store.saidaPorApp[bundle] = SaidasDeAudio.padrao.flatMap(SaidasDeAudio.uid) ?? som.saidas.first?.uid ?? ""
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Saída de cada app")
            } footer: {
                Text("A música nos alto-falantes e a chamada no fone, por exemplo. Enquanto o app toca, o som dele passa pelo Docka até a saída escolhida — nada é gravado; o macOS pede a permissão de gravação de áudio do sistema na primeira vez. Com a saída desconectada, o app toca na saída padrão.")
            }

            Section {
                LabeledContent("Atalho") { ShortcutRecorder(acao: .proximaSaida) }
                Toggle(isOn: $store.baixarAoTirarFone) {
                    Text("Baixar o volume quando o fone sair")
                    Text("Tirou o fone (Bluetooth ou de fio) e o som foi para o alto-falante: o volume desce até o limite, para não tocar alto na sala.")
                }
                if store.baixarAoTirarFone {
                    LabeledContent("No máximo") {
                        Slider(value: $store.volumeSemFone, in: 0...0.5, step: 0.05).frame(width: 200)
                        Text(Som.porcentagem(Float(store.volumeSemFone))).monospacedDigit().frame(width: 44)
                    }
                }
            } header: {
                Text("Saída")
            } footer: {
                Text("O atalho passa o som para a próxima saída conectada e mostra o nome dela.")
            }

            Section {
                Picker("Microfone preferido", selection: $store.entradaPreferida) {
                    Text("Nenhum — o sistema escolhe").tag("")
                    ForEach(som.entradas) { e in Text(e.nome).tag(e.uid) }
                    if !store.entradaPreferida.isEmpty, !som.entradas.contains(where: { $0.uid == store.entradaPreferida }) {
                        Text("Desconectado").tag(store.entradaPreferida)
                    }
                }
                LabeledContent("Nível do microfone atual") {
                    Slider(value: Binding(get: { som.nivel }, set: { v in
                        som.nivel = v
                        if let d = som.entradaAtual { SomController.definirNivel(d, Float(v)) }
                    }), in: 0...1).frame(width: 200)
                    .disabled(!som.nivelAjustavel)
                    Text(som.nivelAjustavel ? Som.porcentagem(Float(som.nivel)) : "fixo").monospacedDigit().frame(width: 44)
                }
                LabeledContent("Atalho para silenciar") { ShortcutRecorder(acao: .mudoMicrofones) }
                LabeledContent(som.mudos ? "Todos os microfones estão mudos" : "Testar") {
                    Button(som.mudos ? "Religar" : "Silenciar todos") { SomController.shared.alternarMudo() }
                }
            } header: {
                Text("Microfone")
            } footer: {
                Text("Com um preferido, ele volta a ser o microfone do sistema sempre que estiver conectado — os AirPods não tomam o lugar do microfone do Mac. Silenciar vale para todos, inclusive os que conectarem depois, e religar devolve cada um como estava; ao fechar o Docka, eles voltam sozinhos. Alguns microfones não deixam mudar o nível, e o do iPhone (Continuidade) não tem mudo nem nível no macOS — silencie esse no próprio iPhone.")
            }
        }
        .formStyle(.grouped)
        .onAppear { som.reler() }
    }

    private func appsAbertos() -> [String] {
        let comRegra = Set(store.saidaPorApp.keys)
        let bundles = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !comRegra.contains($0) && $0 != Bundle.main.bundleIdentifier }
        return Array(Set(bundles)).sorted { nome($0).localizedCaseInsensitiveCompare(nome($1)) == .orderedAscending }
    }

    private func nome(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        var n = FileManager.default.displayName(atPath: url.path)
        if n.hasSuffix(".app") { n.removeLast(4) }
        return n
    }

    private func icone(_ bundle: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Painéis

/// Ajustes → Painéis: a barra de comando, o painel rápido e o modo de limpeza.
private struct PaineisSettingsView: View {
    @EnvironmentObject var store: DockaStore

    private var ferramentas: [AcaoDeAtalho] {
        Ferramentas.disponiveis().filter { $0 != .painelRapido }
    }

    private var favoritos: [String] {
        let ids = Set(ferramentas.map(\.id))
        return PainelRapido.favoritos(gravados: store.painelRapidoItens) { ids.contains($0) }
    }

    var body: some View {
        Form {
            Section {
                atalho(.barraDeComando)
                Toggle(isOn: $store.barraArquivos) {
                    Text("Buscar arquivos")
                    Text("Pelo Spotlight, na sua pasta pessoal; os usados por último primeiro.")
                }
                Toggle(isOn: $store.barraMenus) {
                    Text("Comandos de menu do app da frente")
                    Text("Ache e execute qualquer item dos menus sem caçar onde ele está. Pede Acessibilidade.")
                }
                LabeledContent("Testar") {
                    Button("Abrir a barra") { BarraDeComandoController.shared.abrir() }
                }
            } header: {
                Text("Barra de comando")
            } footer: {
                Text("Um campo só para apps, janelas, arquivos, o que você copiou, snippets, comandos de menu e as ferramentas do Docka. Também faz contas (15% de 80), converte unidades (10 km em mi, 100 f para c) e acha emoji (joinha). ↩ escolhe; num arquivo, ⌘↩ mostra no Finder.")
            }

            Section {
                ForEach($store.scripts) { $s in
                    HStack(spacing: 8) {
                        TextField("Nome", text: $s.nome)
                            .frame(width: 150)
                        TextField("Comando", text: $s.comando)
                            .font(.system(.body, design: .monospaced))
                        Button {
                            store.scripts.removeAll { $0.id == s.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remover")
                    }
                    .labelsHidden()
                }
                Button("Adicionar script") {
                    store.scripts.append(ScriptSalvo(nome: "Novo script", comando: "echo pronto"))
                }
            } header: {
                Text("Scripts da barra")
            } footer: {
                Text("Digite o nome na barra para rodar. Roda no zsh de login (com o seu PATH), na pasta pessoal, e a primeira linha da saída aparece num aviso. Cadastre só comandos em que você confia.")
            }

            Section {
                atalho(.painelRapido)
                ForEach(ferramentas, id: \.id) { a in
                    Toggle(isOn: Binding(
                        get: { favoritos.contains(a.id) },
                        set: { _ in store.painelRapidoItens = PainelRapido.alternar(a.id, em: favoritos) }
                    )) {
                        Label(Ferramentas.titulo(a), systemImage: Ferramentas.simbolo(a))
                    }
                }
                LabeledContent("Testar") {
                    HStack {
                        Button("Voltar ao padrão") { store.painelRapidoItens = nil }
                            .disabled(store.painelRapidoItens == nil)
                        Button("Abrir o painel") { PainelRapidoController.shared.abrir() }
                    }
                }
            } header: {
                Text("Painel rápido")
            } footer: {
                Text("Uma paleta com as ferramentas marcadas, aberta em volta do cursor, na ordem em que foram marcadas. Clique, ↩ ou o número da posição escolhe. Recursos desligados não aparecem.")
            }

            Section {
                atalho(.limpeza)
                Picker("Enquanto limpa", selection: $store.limpezaVisual) {
                    ForEach(ModoDeLimpeza.Visual.allCases) { v in Text(v.titulo).tag(v.rawValue) }
                }
                .pickerStyle(.segmented)
                Picker("Duração", selection: $store.limpezaDuracao) {
                    ForEach(ModoDeLimpeza.duracoes, id: \.self) { d in
                        Text(d < 60 ? "\(Int(d)) segundos" : (d == 60 ? "1 minuto" : "\(Int(d / 60)) minutos")).tag(d)
                    }
                }
                LabeledContent("Testar") {
                    Button("Começar agora") { ModoDeLimpezaController.shared.comecar() }
                }
            } header: {
                Text("Modo de limpeza")
            } footer: {
                Text("O teclado inteiro para de responder, inclusive brilho, volume e mídia; o botão de ligar e o Touch ID continuam. Com as telas pretas, os cliques também não chegam aos apps. Termina sozinho no fim do tempo, ou segurando o botão na tela. Pede Acessibilidade.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func atalho(_ acao: AcaoDeAtalho) -> some View {
        LabeledContent("Atalho") { ShortcutRecorder(acao: acao) }
        if let erro = store.erroDoAtalho(acao) {
            Label(erro, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        }
    }
}

// MARK: - Ações rápidas

private struct AcoesRapidasView: View {
    @EnvironmentObject var store: DockaStore

    private var disponiveis: [AcaoRapida] {
        AcaoRapida.allCases.filter(AcoesRapidasBackend.disponivel)
    }

    var body: some View {
        Form {
            Section {
                ForEach(disponiveis) { a in
                    LabeledContent {
                        Button("Executar") { AcoesRapidasBackend.executar(a) }
                    } label: {
                        Label {
                            Text(AcoesRapidasBackend.titulo(a))
                            Text(a.descricao)
                        } icon: {
                            Image(systemName: a.simbolo)
                        }
                    }
                }
            } footer: {
                Text("Elas também ficam na aba Rápido do painel da barra de menus, no painel rápido e na barra de comando, e cada uma pode ter um atalho. As alternâncias (claro/escuro, Night Shift, Dock, arquivos ocultos, ícones da mesa) aparecem destacadas quando ligadas. Só esvaziar o Lixo pede permissão: o macOS pergunta uma vez se o Docka pode controlar o Finder.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Brilho por tela

/// Uma linha por tela conectada: o brilho de hardware, onde a tela aceita, e o
/// escurecimento por software em todas — que também vai abaixo do mínimo.
private struct TelasDeBrilhoSection: View {
    @ObservedObject private var telas = TelasDeBrilho.shared

    var body: some View {
        Section {
            ForEach(telas.telas) { tela in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(tela.nome, systemImage: tela.hardware ? "laptopcomputer" : "display")
                        Spacer()
                        Text(tela.hardware ? "Brilho do painel" : (tela.ddc ? "Brilho do monitor (DDC)" : "Só por software"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if tela.hardware {
                        LinhaDeBrilho(tela: tela)
                    } else if tela.ddc {
                        LinhaDeBrilhoDDC(tela: tela)
                    } else if let motivo = tela.semDDC {
                        Label {
                            Text("Sem brilho de hardware: " + motivo)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    LabeledContent {
                        HStack {
                            Slider(value: Binding(get: { telas.escurecimento(tela) },
                                                  set: { telas.definirEscurecimento($0, em: tela) }),
                                   in: 0...Escurecimento.maximo)
                            Text("\(Int((telas.escurecimento(tela) * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    } label: {
                        Text(tela.hardware ? "Escurecer além do mínimo" : "Escurecer")
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Telas")
        } footer: {
            Text("Monitores externos que entendem DDC/CI ajustam o brilho do próprio painel — o Docka só lê e muda o brilho, nada mais; quem não responde fica no escurecimento. O escurecimento pinta a imagem mais escura pela tabela de gama — funciona em qualquer monitor, inclusive nos que não aceitam controle de brilho, e para em \(Int(Escurecimento.maximo * 100))% para a tela nunca ficar preta. Se o Docka for encerrado, as cores voltam ao normal sozinhas.")
        }
        .onAppear { telas.atualizarTelas() }
    }
}

/// O brilho do painel de um monitor externo, pelo DDC — escrito na fila,
/// só o último valor do arrasto.
private struct LinhaDeBrilhoDDC: View {
    let tela: TelasDeBrilho.Tela
    @State private var nivel: Double = 0.5

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: Binding(get: { nivel }, set: {
                    nivel = $0
                    DDCBackend.shared.escrever($0, em: tela.id)
                }), in: 0...1)
                Text("\(Int((nivel * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        } label: {
            Text("Brilho")
        }
        .onAppear { nivel = DDCBackend.shared.nivel(tela.id) ?? nivel }
    }
}

/// O brilho de hardware de uma tela, lido ao aparecer e escrito ao arrastar.
private struct LinhaDeBrilho: View {
    let tela: TelasDeBrilho.Tela
    @State private var nivel: Double = 0.5

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: Binding(get: { nivel }, set: {
                    nivel = $0
                    BrightnessBackend.escrever($0, tela.id)
                }), in: 0...1)
                Text("\(Int((nivel * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        } label: {
            Text("Brilho")
        }
        .onAppear { nivel = BrightnessBackend.ler(tela.id) ?? nivel }
    }
}

// MARK: - Atalhos

private struct AtalhoView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                ForEach(Array(store.docks.enumerated()), id: \.element.id) { i, d in
                    linha(.bandeja(d.id),
                          titulo: "Bandeja \(i + 1)",
                          detalhe: "\(d.edge.titulo), \(d.alignment.titulo(for: d.edge).lowercased()) — \(d.apps.count) \(d.apps.count == 1 ? "app" : "apps")")
                }
            } header: {
                Text("Bandejas")
            } footer: {
                Text(store.docks.count > 1
                     ? "Cada bandeja tem o seu atalho: ele fixa aquela bandeja aberta e a esconde no segundo toque."
                     : "O atalho fixa a bandeja aberta e a esconde no segundo toque.")
            }

            if store.brightnessControl || store.volumeControl || store.orbitaControl
                || store.prateleiraControl || store.notasControl || store.monitorControl {
                Section {
                    if store.brightnessControl {
                        linha(.brilho, titulo: "Controle de brilho",
                              detalhe: "Abre a régua fixada, sem precisar encostar na borda")
                    }
                    if store.volumeControl {
                        linha(.volume, titulo: "Controle de volume",
                              detalhe: "Abre a régua fixada, sem precisar encostar na borda")
                    }
                    if store.monitorControl {
                        linha(.monitor, titulo: "Monitor do sistema",
                              detalhe: "Fixa o painel aberto; o segundo toque esconde")
                    }
                    if store.notasControl {
                        linha(.blocoDeNotas, titulo: "Bloco de notas",
                              detalhe: "Abre pronto para digitar; o segundo toque esconde")
                    }
                    if store.prateleiraControl {
                        linha(.prateleira, titulo: "Prateleira",
                              detalhe: "Fixa a prateleira aberta; o segundo toque esconde")
                    }
                    if store.orbitaControl {
                        linha(.orbita, titulo: "Órbita",
                              detalhe: "Abre no último anel usado; a rolagem troca")
                        // um atalho por anel só faz sentido havendo mais de um
                        if store.aneis.count > 1 {
                            ForEach(store.aneis) { anel in
                                linha(.anel(anel.id), titulo: "Órbita — \(anel.nome)",
                                      detalhe: "Abre direto neste anel, sem rolar até ele")
                            }
                        }
                    }
                } header: {
                    Text("Controles de borda")
                }
            }

            Section {
                if store.historicoControl {
                    linha(.historico, titulo: "Histórico",
                          detalhe: "Abre a lista com busca; ↩ copia o escolhido")
                }
                linha(.textoPuro, titulo: "Colar sem formatação",
                      detalhe: "Deixa o que está copiado em texto puro — depois é só ⌘V")
                linha(.snippets, titulo: "Snippets",
                      detalhe: "Abre a lista; ↩ insere o escolhido")
            } header: {
                Text("Área de transferência")
            }

            Section {
                linha(.acordado, titulo: "Manter acordado",
                      detalhe: "Liga com a duração padrão; o segundo toque desliga")
            } header: {
                Text("Energia")
            }

            Section {
                linha(.barraDeComando, titulo: "Barra de comando",
                      detalhe: "Apps, janelas, arquivos, comandos de menu, contas e emoji")
                linha(.painelRapido, titulo: "Painel rápido",
                      detalhe: "As ferramentas favoritas em volta do cursor")
                linha(.limpeza, titulo: "Modo de limpeza",
                      detalhe: "Trava o teclado para limpar; segure o botão na tela para sair")
            } header: {
                Text("Painéis")
            }

            Section {
                linha(.proximaSaida, titulo: "Próxima saída de som",
                      detalhe: "Passa o som para a próxima saída conectada")
                linha(.mudoMicrofones, titulo: "Silenciar os microfones",
                      detalhe: "Todos de uma vez; o segundo toque religa")
            } header: {
                Text("Som")
            }

            Section {
                if store.capturaControl {
                    linha(.gravarTela, titulo: "Gravar a tela",
                          detalhe: "Escolhe a área e grava; de novo, para")
                }
                linha(.midia, titulo: "Ferramentas de mídia",
                      detalhe: "Comprimir e converter vídeo e imagem, GIF, texto")
                linha(.manutencao, titulo: "Manutenção",
                      detalhe: "Atualizações, limpeza, mensageiros, desinstalador, Homebrew, portas")
            } header: {
                Text("Mídia")
            }

            Section {
                ForEach(AcaoRapida.allCases.filter(AcoesRapidasBackend.disponivel)) { a in
                    linha(.rapida(a), titulo: a.titulo, detalhe: a.descricao)
                }
            } header: {
                Text("Ações rápidas")
            }

            Section {
                linha(.ajustes, titulo: "Abrir os ajustes",
                      detalhe: "Esta janela, de qualquer lugar")
            } header: {
                Text("Aplicativo")
            } footer: {
                Text("A combinação precisa incluir ⌘, ⌥ ou ⌃ — sem um deles, a tecla seria engolida no sistema inteiro. O ✕ remove o atalho: uma ação pode ficar sem nenhum.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func linha(_ acao: AcaoDeAtalho, titulo: String, detalhe: String) -> some View {
        LabeledContent {
            ShortcutRecorder(acao: acao)
        } label: {
            Text(titulo)
            Text(detalhe)
        }
        if let erro = store.erroDoAtalho(acao) {
            Label(erro, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        }
    }
}

// MARK: - Sobre

private struct SobreView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AppLogo(size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Docka").font(.title2).bold()
                        Text("Versão \(AppInfo.version)")
                            .foregroundStyle(.secondary).monospacedDigit()
                        Text("Uma bandeja de apps que vive na borda da sua tela.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section {
                Button("Encerrar o Docka") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Autoteste visual

/// Desenha a janela de ajustes e a aba de permissões fora da tela, em PNG —
/// confere o visual sem abrir nada na tela de ninguém.
enum AjustesAutoteste {
    static func rodar(pasta: String) -> String {
        func desenhar<V: View>(_ v: V, _ nome: String, _ tamanho: NSSize) -> String {
            // fundo da janela atrás: a página de Recursos não tem fundo próprio
            let hv = NSHostingView(rootView: v.environmentObject(DockaStore.shared)
                .background(Color(nsColor: .windowBackgroundColor)))
            let janela = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: tamanho.width, height: tamanho.height),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            janela.contentView = hv
            for _ in 0..<8 {
                hv.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            guard let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds) else { return "FALHOU — \(nome)" }
            hv.cacheDisplay(in: hv.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(pasta)/\(nome).png"))
            janela.contentView = nil
            return "OK — \(nome).png"
        }
        return [
            desenhar(SettingsWindowView(), "ajustes-janela", NSSize(width: 820, height: 760)),
            desenhar(RecursosView(aba: .permissoes).frame(width: 600, height: 760), "ajustes-permissoes", NSSize(width: 600, height: 760)),
            desenhar(RecursosView(aba: .recursos).frame(width: 600, height: 760), "ajustes-recursos", NSSize(width: 600, height: 760)),
            desenhar(EncerrarSettingsView().frame(width: 600, height: 560), "ajustes-encerrar", NSSize(width: 600, height: 560)),
            desenhar(DockSettingsView().frame(width: 600, height: 300), "ajustes-dock", NSSize(width: 600, height: 300)),
            desenhar(IlhaSettingsView().frame(width: 600, height: 900), "ajustes-ilha", NSSize(width: 600, height: 900)),
            desenhar(AjustesDoSistemaView().frame(width: 600, height: 720), "ajustes-sistema", NSSize(width: 600, height: 720)),
            desenhar(TecladoSettingsView().frame(width: 600, height: 420), "ajustes-teclado", NSSize(width: 600, height: 420)),
            desenhar(FinderSettingsView().frame(width: 600, height: 380), "ajustes-finder", NSSize(width: 600, height: 380)),
            InstaladorPanel.desenhar(pasta: pasta),
            desenhar(PaineisSettingsView().frame(width: 600, height: 1500), "ajustes-paineis", NSSize(width: 600, height: 1500)),
            desenhar(SomSettingsView().frame(width: 600, height: 760), "ajustes-som", NSSize(width: 600, height: 760)),
            desenhar(CapturaSettingsView().frame(width: 600, height: 1100), "ajustes-captura", NSSize(width: 600, height: 1100)),
            {
                let m = MidiaModelo()
                m.itens = [.init(url: URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/Sonoma.heic")),
                           .init(url: URL(fileURLWithPath: "/tmp/viagem.mov"))]
                return desenhar(MidiaView().environmentObject(m).frame(width: 560, height: 640), "midia", NSSize(width: 560, height: 640))
            }(),
            BarraDeComandoController.desenhar(pasta: pasta, busca: "15% de 80", arquivo: "barra-conta.png"),
            BarraDeComandoController.desenhar(pasta: pasta, busca: "10 km em mi", arquivo: "barra-conversao.png"),
            BarraDeComandoController.desenhar(pasta: pasta, busca: "term", arquivo: "barra-busca.png"),
            BarraDeComandoController.desenhar(pasta: pasta, busca: "joinha", arquivo: "barra-emoji.png"),
            PainelRapidoController.desenhar(pasta: pasta),
            desenhar(MouseSettingsView().frame(width: 600, height: 1300), "ajustes-mouse", NSSize(width: 600, height: 1300)),
            {
                // o DDC responde (ou não) em segundo plano: espera a resposta antes de desenhar
                TelasDeBrilho.shared.atualizarTelas()
                RunLoop.current.run(until: Date().addingTimeInterval(1.5))
                return desenhar(Form { TelasDeBrilhoSection() }.formStyle(.grouped).frame(width: 600, height: 420),
                                "ajustes-brilho", NSSize(width: 600, height: 420))
            }(),
        ].joined(separator: "\n")
    }
}
