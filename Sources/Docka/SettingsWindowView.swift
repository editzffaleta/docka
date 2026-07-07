import SwiftUI

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
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.6)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
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
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.25)))
                .reveal(delay: 0.1)

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
                            Button {
                                withAnimation(.spring(duration: 0.3)) { store.toggle(app.path) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
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
                settingRow(icon: "cursorarrow.motionlines",
                           title: "Pressure Zone",
                           desc: "Só revela quando você empurra o cursor contra o canto de propósito.",
                           on: Binding(get: { store.pressureZone }, set: { store.pressureZone = $0 }))

                settingRow(icon: "speaker.wave.2",
                           title: "Sons",
                           desc: "Toca um som ao revelar a bandeja e ao abrir um app.",
                           on: Binding(get: { store.soundsEnabled }, set: { store.soundsEnabled = $0 }))

                settingRow(icon: "dock.rectangle",
                           title: "Seguir mudanças do Dock",
                           desc: "Mantém o Docka alinhado quando o Dock muda de tamanho.",
                           on: Binding(get: { store.followDock }, set: { store.followDock = $0 }))

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
                    Slider(value: Binding(get: { store.offsetX }, set: { store.offsetX = $0 }),
                           in: 0...400).tint(Theme.accent)

                    HStack {
                        Text("Tamanho dos ícones")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text("\(Int(store.iconSize)) pt")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                    }
                    Slider(value: Binding(get: { store.iconSize }, set: { store.iconSize = $0 }),
                           in: 32...64, step: 4).tint(Theme.accent)

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
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 90, height: 90)
                    .pulseGlow(Theme.accent)
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 40)).foregroundStyle(.white)
            }
            Text("Docka").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            Text("Versão 2.0.0 (recriação em SwiftUI)")
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
