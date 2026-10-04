import SwiftUI
import DockaCore

// Gerenciador do Docka.
//
// Construído com os idiomas nativos que PRODUZEM o visual das Configurações do
// Sistema — NavigationSplitView com barra lateral e Form com .formStyle(.grouped)
// — em vez de redesenhar aquele visual com formas próprias. É o que garante que
// as linhas, os espaçamentos, os controles e o comportamento em Tom claro/escuro
// acompanhem o sistema sozinhos.

enum Secao: String, CaseIterable, Identifiable {
    case geral, apps, aparencia, bandeja, orbita, prateleira, notas, monitor, clipboard, janelas, mouse, captura, brilho, volume, energia, acoes, atalho, sobre
    var id: String { rawValue }

    /// As Configurações agrupam a barra lateral em blocos separados por um vão.
    static let grupos: [[Secao]] = [[.geral, .apps], [.aparencia, .bandeja, .orbita, .prateleira, .notas, .monitor, .clipboard, .janelas, .mouse, .captura, .brilho, .volume, .energia, .acoes, .atalho], [.sobre]]

    var titulo: String {
        switch self {
        case .geral:     return "Geral"
        case .apps:      return "Apps"
        case .aparencia: return "Aparência"
        case .bandeja:   return "Bandeja"
        case .orbita:    return "Órbita"
        case .prateleira: return "Prateleira"
        case .notas:     return "Bloco de notas"
        case .monitor:   return "Monitor do sistema"
        case .clipboard: return "Área de transferência"
        case .janelas:   return "Janelas"
        case .mouse:     return "Mouse"
        case .captura:   return "Captura"
        case .brilho:    return "Brilho"
        case .volume:    return "Volume"
        case .energia:   return "Energia"
        case .acoes:     return "Ações rápidas"
        case .atalho:    return "Atalhos"
        case .sobre:     return "Sobre"
        }
    }

    var simbolo: String {
        switch self {
        case .geral:     return "gearshape.fill"
        case .apps:      return "square.grid.2x2.fill"
        case .aparencia: return "circle.lefthalf.filled"
        case .bandeja:   return "dock.rectangle"
        case .orbita:    return "circle.circle.fill"
        case .prateleira: return "tray.and.arrow.down.fill"
        case .notas:     return "note.text"
        case .monitor:   return "gauge.with.dots.needle.67percent"
        case .clipboard: return "doc.on.clipboard.fill"
        case .janelas:   return "rectangle.split.2x1.fill"
        case .mouse:     return "computermouse.fill"
        case .captura:   return "camera.viewfinder"
        case .brilho:    return "sun.max.fill"
        case .volume:    return "speaker.wave.2.fill"
        case .energia:   return "cup.and.saucer.fill"
        case .acoes:     return "bolt.fill"
        case .atalho:    return "keyboard.fill"
        case .sobre:     return "info"
        }
    }

    // As Configurações do Sistema usam um quadradinho colorido por seção
    var cor: Color {
        switch self {
        case .geral:     return .gray
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
        case .captura:   return .purple
        case .brilho:    return .yellow
        case .volume:    return .pink
        case .energia:   return .brown
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

    var body: some View {
        Image(systemName: secao.simbolo)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(secao.cor.gradient))
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject var store: DockaStore
    @State private var secao: Secao = .geral
    @State private var busca = ""
    /// Histórico de navegação, para os botões voltar/avançar funcionarem de fato.
    @State private var anteriores: [Secao] = []
    @State private var posteriores: [Secao] = []

    var body: some View {
        NavigationSplitView {
            barraLateral
                // largura fixa: nas Configurações a barra lateral não é
                // redimensionável nem recolhível
                .navigationSplitViewColumnWidth(215)
                // fora o botão de recolher — ele desalinha a barra de título e o
                // painel da Apple não tem esse controle
                .toolbar(removing: .sidebarToggle)
        } detail: {
            conteudo
                .navigationTitle(secao.titulo)
                .toolbar { navegacao }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { store.refreshLaunchAtLogin() }
    }

    private var resultados: [Secao] {
        busca.isEmpty ? [] : Secao.allCases.filter {
            $0.titulo.localizedCaseInsensitiveContains(busca)
        }
    }

    @ViewBuilder
    private var barraLateral: some View {
        List(selection: selecao) {
            if busca.isEmpty {
                ForEach(Secao.grupos.indices, id: \.self) { i in
                    Section { linhas(Secao.grupos[i]) }
                }
            } else {
                Section { linhas(resultados) }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $busca, placement: .sidebar, prompt: "Buscar")
    }

    private func linhas(_ itens: [Secao]) -> some View {
        ForEach(itens) { s in
            NavigationLink(value: s) {
                Label { Text(s.titulo) } icon: { IconeSecao(secao: s) }
            }
        }
    }

    /// Grava o histórico a cada troca de seção pela barra lateral.
    private var selecao: Binding<Secao?> {
        Binding(get: { secao }, set: { novo in
            guard let novo, novo != secao else { return }
            anteriores.append(secao)
            posteriores.removeAll()
            secao = novo
        })
    }

    @ToolbarContentBuilder
    private var navegacao: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { voltar() } label: { Image(systemName: "chevron.backward") }
                .disabled(anteriores.isEmpty)
                .help("Voltar")
            Button { avancar() } label: { Image(systemName: "chevron.forward") }
                .disabled(posteriores.isEmpty)
                .help("Avançar")
        }
    }

    private func voltar() {
        guard let destino = anteriores.popLast() else { return }
        posteriores.append(secao)
        secao = destino
    }

    private func avancar() {
        guard let destino = posteriores.popLast() else { return }
        anteriores.append(secao)
        secao = destino
    }

    @ViewBuilder
    private var conteudo: some View {
        switch secao {
        case .geral:     GeralView()
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
        case .captura:   CapturaSettingsView()
        case .brilho:    DeslizadorView(deslizador: .brilho)
        case .volume:    DeslizadorView(deslizador: .volume)
        case .energia:   EnergiaView()
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
            } header: {
                Text("Privacidade")
            }

            SecaoColarSozinho()

            SecaoDeSnippets()

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
            .onReceive(relogio) { _ in permitido = Colagem.permitido }

            SecaoDoAlternador()

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
            }
        }
        .formStyle(.grouped)
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
                Text("Segure o modificador do atalho, aperte de novo para avançar (⇧ volta) e solte para trocar. Os apps vêm na ordem em que você os usou.")
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
            }
        } header: {
            Text("Alternador")
        } footer: {
            Text("Não substitui o ⌘Tab do sistema — interceptá-lo exigiria ler o teclado inteiro. Prévias ao vivo das janelas pediriam Gravação de Tela e ficam para depois.")
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
                    Text(s.nome)
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
            Text("Textos prontos, escolhidos pelo atalho dos snippets. Variáveis: " + Snippets.variaveis.map { "\($0.chave) — \($0.descricao)" }.joined(separator: "; ") + ". Expandir um gatilho digitado (como ;email) pediria Monitoramento de Entrada e fica para depois.")
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

// MARK: - Ações rápidas

private struct AcoesRapidasView: View {
    @EnvironmentObject var store: DockaStore

    private var disponiveis: [AcaoRapida] {
        AcaoRapida.allCases.filter(AcoesRapidasBackend.disponivel)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.acoesRapidas) {
                    Text("Mostrar no menu da barra")
                    Text("Um submenu com as ações abaixo. Os atalhos funcionam mesmo com ele desligado.")
                }
            }

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
                Text("Nenhuma pede permissão. Esvaziar o Lixo e trocar claro/escuro ficaram de fora porque exigiriam autorizar o Docka a controlar o Finder e os Eventos do Sistema.")
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
                        Text(tela.hardware ? "Brilho do painel" : "Só por software")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if tela.hardware {
                        LinhaDeBrilho(tela: tela)
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
            Text("O escurecimento pinta a imagem mais escura pela tabela de gama — funciona em qualquer monitor, inclusive nos que não aceitam controle de brilho, e para em \(Int(Escurecimento.maximo * 100))% para a tela nunca ficar preta. Se o Docka for encerrado, as cores voltam ao normal sozinhas.")
        }
        .onAppear { telas.atualizarTelas() }
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
