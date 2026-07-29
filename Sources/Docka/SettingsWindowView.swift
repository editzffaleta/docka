import SwiftUI
import DockaCore

// Janela principal pós-onboarding: gerenciar apps e ajustes
struct SettingsWindowView: View {
    @EnvironmentObject var store: DockaStore
    @State private var tab = "Apps"

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 18) {
                // cabeçalho
                HStack(spacing: 12) {
                    AppLogo(size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Docka").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        Text("Empurre o cursor para a borda inferior direita para revelar a bandeja")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    // status
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: 0.45, green: 0.85, blue: 0.6))
                            .frame(width: 8, height: 8)
                            .pulseGlow(Color(red: 0.45, green: 0.85, blue: 0.6))
                        Text("Ativo").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.08)))
                }
                .padding(.horizontal, 30)
                .padding(.top, 42)
                .reveal(delay: 0.02)

                // tabs
                HStack(spacing: 2) {
                    ForEach(["Apps", "Comportamento", "Sobre"], id: \.self) { t in
                        Button { withAnimation(.spring(duration: 0.3)) { tab = t } } label: {
                            Text(t)
                                .font(.system(size: 12, weight: tab == t ? .bold : .medium))
                                .foregroundStyle(tab == t ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 9)
                                    .fill(tab == t ? Color.white.opacity(0.14) : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == t ? [.isSelected] : [])
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.25)))
                .reveal(delay: 0.1)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Seções")

                Group {
                    switch tab {
                    case "Apps": appsTab
                    case "Comportamento": behaviorTab
                    default: aboutTab
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
        }
    }

    // MARK: aba Apps

    private var appsTab: some View {
        VStack(spacing: 12) {
            if store.apps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Nenhum app no Docka ainda.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(height: 90)
            } else {
                // prévia da bandeja
                HStack(spacing: 10) {
                    ForEach(store.apps) { app in
                        VStack(spacing: 4) {
                            Image(nsImage: app.icon)
                                .resizable().frame(width: 40, height: 40)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                .accessibilityHidden(true)   // o nome vai no botão abaixo
                            Button {
                                withAnimation(.spring(duration: 0.3)) { store.toggle(app.path) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remover \(app.name) do Docka")
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .glassCard(hoverLift: false)
            }

            AppPickerGrid()
        }
        .padding(.bottom, 20)
    }

    // MARK: aba Comportamento

    private var behaviorTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                launchAtLoginRow

                settingRow(icon: "cursorarrow.motionlines",
                           title: "Pressure Zone",
                           desc: "Só revela quando você empurra o cursor contra o canto de propósito.",
                           on: $store.pressureZone)

                settingRow(icon: "speaker.wave.2",
                           title: "Sons",
                           desc: "Toca um som ao revelar a bandeja e ao abrir um app.",
                           on: $store.soundsEnabled)

                settingRow(icon: "dock.rectangle",
                           title: "Seguir mudanças do Dock",
                           desc: "Assenta a bandeja em cima do Dock e realinha quando ele muda de tamanho ou de lado.",
                           on: $store.followDock)

                settingRow(icon: "arrow.up.circle",
                           title: "Animar abertura de aplicativos",
                           desc: "O ícone quica duas vezes enquanto o app abre.",
                           on: $store.bounceOnLaunch)

                settingRow(icon: "smallcircle.filled.circle",
                           title: "Mostrar indicadores para aplicativos abertos",
                           desc: "Bolinha branca sob cada app em execução.",
                           on: $store.showIndicators)

                aparenciaCard

                // atalho global
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.accent.opacity(0.14))
                            Image(systemName: "keyboard")
                                .font(.system(size: 15)).foregroundStyle(Theme.accent)
                        }
                        .frame(width: 38, height: 38)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Atalho global")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            Text("Fixa a bandeja aberta e a esconde no segundo toque.")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        ShortcutRecorder()
                    }

                    if let erro = store.shortcutError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.35))
                            Text(erro)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.65))
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glassCard(hoverLift: false)

                // calibração
                VStack(alignment: .leading, spacing: 14) {
                    Label("Calibração", systemImage: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)

                    HStack {
                        Text("Distância da borda direita")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text("\(Int(store.offsetX)) pt")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                    }
                    Slider(value: $store.offsetX, in: 0...400).tint(Theme.accent)
                        .accessibilityLabel("Distância da borda")
                        .accessibilityValue("\(Int(store.offsetX)) pontos")

                    HStack {
                        Text("Tamanho dos ícones")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text("\(Int(store.iconSize)) pt")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                    }
                    Slider(value: $store.iconSize, in: 32...64, step: 4).tint(Theme.accent)
                        .accessibilityLabel("Tamanho dos ícones")
                        .accessibilityValue("\(Int(store.iconSize)) pontos")

                    HStack {
                        Text("Ampliação máxima")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text(store.maxScale <= 1
                             ? "Desativada"
                             : String(format: "%.2f×", store.maxScale))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                    }
                    Slider(value: $store.maxScale, in: 1...2.5).tint(Theme.accent)
                        .accessibilityLabel("Ampliação máxima")
                        .accessibilityValue(store.maxScale <= 1
                                            ? "Desativada"
                                            : String(format: "%.2f vezes", store.maxScale))

                    HStack {
                        Text("Alcance da ampliação")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text("\(Int(store.maxRange)) pt")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                    }
                    Slider(value: $store.maxRange, in: 60...400).tint(Theme.accent)
                        .accessibilityLabel("Alcance da ampliação")
                        .accessibilityValue("\(Int(store.maxRange)) pontos")

                    Text("O alcance é a distância em que o cursor ainda mexe com um ícone. Fora dele o ícone fica exatamente no tamanho normal, como no Dock.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))

                    HStack {
                        Text("Posição da bandeja na tela")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Picker("", selection: $store.position) {
                            Text("Esquerda").tag("left")
                            Text("Centro").tag("center")
                            Text("Direita").tag("right")
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }

                    Text("Dica: mexa nos valores e empurre o cursor para a borda para testar na hora.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(hoverLift: false)

                Button {
                    store.onboarded = false
                } label: {
                    Text("Refazer Onboarding")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        // o usuário pode ter mexido nos Itens de Início de Sessão por fora
        .onAppear { store.refreshLaunchAtLogin() }
    }

    // MARK: aparência da bandeja (espelha a tela Aparência do sistema)

    private var aparenciaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Aparência da bandeja", systemImage: "circle.lefthalf.filled")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)

            HStack {
                Text("Tom")
                    .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Picker("", selection: $store.appearance) {
                    ForEach(TrayAppearance.allCases, id: \.rawValue) { modo in
                        Text(modo.titulo).tag(modo.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityLabel("Tom da bandeja")
            }

            Divider().overlay(.white.opacity(0.08))

            HStack {
                Text("Material do painel")
                    .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(GlassTint.material(for: store.glassTint) == .translucido ? "Translúcido"
                     : GlassTint.overlayOpacity(store.glassTint) == 0 ? "Fosco (padrão)"
                     : "Fosco + \(Int(GlassTint.overlayOpacity(store.glassTint) * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 10) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
                    .accessibilityHidden(true)
                Slider(value: $store.glassTint, in: 0...1).tint(Theme.accent)
                    .accessibilityLabel("Tonalização do vidro")
                    .accessibilityValue(GlassTint.usesClearGlass(store.glassTint) ? "Transparente"
                                        : GlassTint.isSystemNeutral(store.glassTint) ? "Como o sistema"
                                        : "Tonalizado")
                Image(systemName: "square.filled.on.square")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 10) {
                Text("Vibrância do sistema, a mesma do Dock e da barra de menus. À esquerda deixa mais do fundo atravessar; à direita fecha.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                if !GlassTint.isSystemNeutral(store.glassTint) {
                    Button("Voltar ao padrão") {
                        withAnimation(.spring(duration: 0.3)) { store.matchSystemGlassTint() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
            }

            Divider().overlay(.white.opacity(0.08))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estilo dos ícones")
                        .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                    // Não é ajuste do Docka: quem tematiza os ícones é o macOS, e o
                    // NSWorkspace já entrega o ícone com o estilo aplicado. Um
                    // controle nosso aqui faria a bandeja DESTOAR do resto do sistema.
                    Text("Definido em Configurações do Sistema — a bandeja acompanha.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Text(DockaStore.systemIconStyle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.08)))
                Button("Abrir") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(hoverLift: false)
    }

    // Linha própria porque, além do toggle, ela precisa explicar quando o macOS
    // recusa o registro (app fora de Aplicativos, ou bloqueado nas Configurações).
    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingRow(icon: "power",
                       title: "Abrir no login",
                       desc: "O Docka sobe sozinho quando você entra no Mac.",
                       on: Binding(get: { store.launchAtLogin },
                                   set: { store.setLaunchAtLogin($0) }))

            if let note = store.launchAtLoginNote {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.35))
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Button("Abrir Configurações do Sistema") { store.openLoginItemsSettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func settingRow(icon: String, title: String, desc: String, on: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.accent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text(desc).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Toggle("", isOn: on).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassCard(hoverLift: false)
    }

    // MARK: aba Sobre

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            AppLogo(size: 96).pulseGlow(Theme.accent)
            Text("Docka").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            Text("Versão \(AppInfo.version)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text("Uma bandeja de apps que vive na borda da sua tela.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Button("Encerrar o Docka") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.96, green: 0.5, blue: 0.5))
                .padding(.bottom, 30)
        }
    }
}
