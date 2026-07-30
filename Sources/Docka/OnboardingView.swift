import SwiftUI

// Onboarding em 3 passos: boas-vindas → escolher apps → modo de borda
struct OnboardingView: View {
    @EnvironmentObject var store: DockaStore
    @State private var step = 0

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                // indicador de passos
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Theme.accent : Color.white.opacity(0.15))
                            .frame(width: i == step ? 28 : 10, height: 5)
                    }
                }
                .animation(.spring(duration: 0.4), value: step)
                .padding(.top, 42)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Passo \(step + 1) de 3")

                Group {
                    switch step {
                    case 0: welcome
                    case 1: chooseApps
                    default: edgeMode
                    }
                }
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .animation(.spring(duration: 0.5), value: step)
        }
    }

    // MARK: passo 1 — boas-vindas

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()

            AppLogo(size: 116)
                .pulseGlow(Theme.accent)
                .reveal(delay: 0.05)

            Text("Bem-vindo ao Docka")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.75)],
                                                startPoint: .top, endPoint: .bottom))
                .reveal(delay: 0.15)

            Text("Uma bandeja de apps escondida na borda da tela,\nao lado do seu Dock. Empurre o cursor para baixo e ela aparece.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.65))
                .reveal(delay: 0.25)

            Spacer()

            PrimaryButton(title: "Começar", icon: "arrow.right") {
                step = 1
            }
            .reveal(delay: 0.35)

            Spacer().frame(height: 60)
        }
        .padding(.horizontal, 60)
    }

    // MARK: passo 2 — escolher apps

    private var chooseApps: some View {
        VStack(spacing: 14) {
            Text("Escolha seus apps")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 28)
                .reveal(delay: 0.02)

            Text("Selecione os apps que ficam no Docka. Você pode mudar quando quiser.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .reveal(delay: 0.08)

            AppPickerGrid(dockID: store.principal.id)
                .reveal(delay: 0.15)

            HStack {
                Text(store.principal.apps.isEmpty
                     ? "Escolha pelo menos um app para continuar."
                     : "\(store.principal.apps.count) apps no Docka")
                    .font(.system(size: 12))
                    .foregroundStyle(store.principal.apps.isEmpty ? .white.opacity(0.5) : Theme.accent)
                    .contentTransition(.numericText())

                Spacer()

                PrimaryButton(title: "Continuar", icon: "arrow.right") {
                    if !store.principal.apps.isEmpty { step = 2 }
                }
                .opacity(store.principal.apps.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
    }

    // MARK: passo 3 — modo de borda

    private var edgeMode: some View {
        VStack(spacing: 16) {
            Text("Como revelar o Docka?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 40)
                .reveal(delay: 0.02)

            Text("Escolha como a bandeja deve aparecer na borda inferior.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .reveal(delay: 0.08)

            VStack(spacing: 12) {
                ModeCard(icon: "cursorarrow.motionlines",
                         title: "Modo Normal",
                         desc: "Encoste o cursor na borda inferior e o Docka aparece. Mais rápido.",
                         selected: !store.pressureZone) { store.pressureZone = false }
                    .reveal(delay: 0.15)

                ModeCard(icon: "rectangle.compress.vertical",
                         title: "Pressure Zone",
                         desc: "Só abre quando você empurra o cursor contra o canto de propósito. Evita aberturas acidentais em apps fullscreen.",
                         selected: store.pressureZone) { store.pressureZone = true }
                    .reveal(delay: 0.23)
            }
            .padding(.horizontal, 60)

            Spacer()

            VStack(spacing: 10) {
                PrimaryButton(title: "Concluir", icon: "checkmark") {
                    store.onboarded = true
                    store.playSound("Glass")
                }
                Text("Depois de concluir, empurre o cursor para a borda inferior direita da tela.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .reveal(delay: 0.3)

            Spacer().frame(height: 40)
        }
    }
}

// MARK: - Grade de seleção de apps

struct AppPickerGrid: View {
    /// A grade serve as bandejas E a órbita: quem decide o que "selecionado"
    /// significa é quem a cria, por estes dois fechamentos.
    let estaSelecionado: (String) -> Bool
    let alternar: (String) -> Void
    @EnvironmentObject var store: DockaStore
    @State private var query = ""
    private let all = DockaStore.installedApps()

    /// A forma histórica: a grade de uma bandeja.
    init(dockID: UUID) {
        let store = DockaStore.shared
        estaSelecionado = { store.estaNaBandeja($0, dockID) }
        alternar = { store.alternarApp($0, em: dockID) }
    }

    init(estaSelecionado: @escaping (String) -> Bool,
         alternar: @escaping (String) -> Void) {
        self.estaSelecionado = estaSelecionado
        self.alternar = alternar
    }

    private var filtered: [PinnedApp] {
        query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar apps…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .padding(.horizontal, 16)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                          spacing: 10) {
                    ForEach(filtered) { app in
                        AppPickCell(app: app,
                                    selected: estaSelecionado(app.path)) {
                            withAnimation(.spring(duration: 0.3)) {
                                alternar(app.path)
                            }
                            store.playSound("Tink")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
        }
    }
}

struct AppPickCell: View {
    let app: PinnedApp
    let selected: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Text(app.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18)
                          : hovering ? Color.primary.opacity(0.06) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                        .padding(5)
                        .transition(.scale)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.spring(duration: 0.25), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(selected ? "Remove do Docka" : "Adiciona ao Docka")
    }
}

struct ModeCard: View {
    let icon: String
    let title: String
    let desc: String
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accent.opacity(selected ? 0.25 : 0.12))
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text(desc).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Theme.accent : .white.opacity(0.3))
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(desc)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .glassCard(hoverLift: false)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(selected ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
    }
}
