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

    var body: some View {
        NavigationSplitView {
            List(Secao.allCases, selection: $secao) { s in
                NavigationLink(value: s) {
                    Label { Text(s.titulo) } icon: { IconeSecao(secao: s) }
                }
            }
            // largura fixa: nas Configurações a barra lateral não é
            // redimensionável nem recolhível
            .navigationSplitViewColumnWidth(200)
            // fora o botão de recolher — ele desalinha a barra de título e o
            // painel da Apple não tem esse controle
            .toolbar(removing: .sidebarToggle)
        } detail: {
            conteudo
                .navigationTitle(secao.titulo)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { store.refreshLaunchAtLogin() }
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
                LabeledContent("Material do painel") {
                    Text(materialDescrito).foregroundStyle(.secondary)
                }
                Slider(value: $store.glassTint, in: 0...1) {
                    Text("Material do painel")
                } minimumValueLabel: {
                    Image(systemName: "square.on.square.dashed")
                } maximumValueLabel: {
                    Image(systemName: "square.filled.on.square")
                }
                .labelsHidden()
                if !GlassTint.isSystemNeutral(store.glassTint) {
                    Button("Voltar ao padrão") {
                        withAnimation { store.matchSystemGlassTint() }
                    }
                }
            } footer: {
                Text("Vibrância do sistema, a mesma do Dock e da barra de menus. À esquerda deixa mais do fundo atravessar; à direita fecha.")
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
