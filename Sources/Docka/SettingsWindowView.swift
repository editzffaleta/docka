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
    case geral, apps, aparencia, bandeja, atalho, sobre
    var id: String { rawValue }

    /// As Configurações agrupam a barra lateral em blocos separados por um vão.
    static let grupos: [[Secao]] = [[.geral, .apps], [.aparencia, .bandeja, .atalho], [.sobre]]

    var titulo: String {
        switch self {
        case .geral:     return "Geral"
        case .apps:      return "Apps"
        case .aparencia: return "Aparência"
        case .bandeja:   return "Bandeja"
        case .atalho:    return "Atalho"
        case .sobre:     return "Sobre"
        }
    }

    var simbolo: String {
        switch self {
        case .geral:     return "gearshape.fill"
        case .apps:      return "square.grid.2x2.fill"
        case .aparencia: return "circle.lefthalf.filled"
        case .bandeja:   return "dock.rectangle"
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
        case .atalho:    return .orange
        case .sobre:     return .secondary
        }
    }
}

/// O quadradinho com o símbolo, como na barra lateral das Configurações.
struct IconeSecao: View {
    let secao: Secao

    var body: some View {
        Image(systemName: secao.simbolo)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(secao.cor))
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

    var body: some View {
        Form {
            Section("Na bandeja") {
                if store.apps.isEmpty {
                    ContentUnavailableView("Nenhum app na bandeja",
                                           systemImage: "square.dashed",
                                           description: Text("Escolha abaixo os apps que ficam no Docka."))
                } else {
                    ForEach(store.apps) { app in
                        LabeledContent {
                            Button {
                                withAnimation { store.toggle(app.path) }
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
                AppPickerGrid()
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
                Picker("Tom", selection: $store.appearance) {
                    ForEach(TrayAppearance.allCases, id: \.rawValue) { modo in
                        Text(modo.titulo).tag(modo.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                // no formato do controle Liquid Glass das Configurações:
                // rótulo à esquerda, prévia simulada à direita e o slider embaixo dela
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 10) {
                        MaterialPreview(tint: store.glassTint,
                                        appearance: TrayAppearance(persisted: store.appearance),
                                        apps: store.apps)
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

            Section("Posição") {
                Picker("Posição na tela", selection: $store.position) {
                    Text("Esquerda").tag("left")
                    Text("Centro").tag("center")
                    Text("Direita").tag("right")
                }
                .pickerStyle(.segmented)

                LabeledContent("Distância da borda") {
                    LinhaSlider(valor: $store.offsetX, faixa: 0...400,
                                texto: "\(Int(store.offsetX)) pt")
                }
                .accessibilityLabel("Distância da borda")
                .accessibilityValue("\(Int(store.offsetX)) pontos")
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

// MARK: - Atalho

private struct AtalhoView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    ShortcutRecorder()
                } label: {
                    Text("Atalho global")
                    Text("Fixa a bandeja aberta e a esconde no segundo toque.")
                }
                if let erro = store.shortcutError {
                    Label(erro, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("A combinação precisa incluir ⌘, ⌥ ou ⌃.")
            }
        }
        .formStyle(.grouped)
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
