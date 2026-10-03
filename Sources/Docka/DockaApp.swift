import SwiftUI
import DockaCore

// MARK: - Janela de configurações

// A janela é criada à mão em vez de sair de um WindowGroup. Dois motivos:
// um WindowGroup sempre abre uma janela ao iniciar — inaceitável para um app que
// agora sobe sozinho no login — e, uma vez fechada, a janela do WindowGroup é
// destruída, deixando o botão de engrenagem sem nada para reabrir.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    /// Mostra a janela e traz o Docka para frente (com ícone no Dock enquanto ela existir).
    func show() {
        if window == nil { build() }
        DockaStore.shared.refreshLaunchAtLogin()   // pode ter mudado nas Configurações do Sistema
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Esconde a janela e devolve o Docka para a barra de menus:
    /// sem ícone no Dock e fora do ⌘Tab.
    func hide() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    private func build() {
        let root = RootView().environmentObject(DockaStore.shared)

        // Janela padrão do sistema: barra de título normal, sem transparência e
        // sem forçar tema. É o que faz o gerenciador parecer um painel nativo —
        // e o que deixa Tom claro/escuro funcionar sozinho.
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Docka"
        w.minSize = NSSize(width: 720, height: 540)
        w.contentView = NSHostingView(rootView: root)
        w.delegate = self
        w.setFrameAutosaveName("DockaSettings2")
        w.center()
        window = w
    }

    // fechar a janela não encerra o Docka nem destrói a janela: apenas esconde
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}

private struct RootView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Group {
            if store.onboarded {
                SettingsWindowView()
            } else {
                // a configuração inicial tem visual próprio, sempre escuro
                OnboardingView().preferredColorScheme(.dark)
            }
        }
    }
}

// MARK: - Ciclo de vida

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.module.url(forResource: "logo", withExtension: "png",
                                       subdirectory: "Assets"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        TrayManager.shared.start()
        HotKeyManager.shared.onPress = { acao in
            guard let acao = AcaoDeAtalho(id: acao) else { return }
            TrayManager.shared.executar(acao)
        }
        DockaStore.shared.ativarAtalhos()

        if DockaStore.shared.onboarded {
            // já configurado: nasce direto na barra de menus, sem piscar janela
            NSApp.setActivationPolicy(.accessory)
        } else {
            SettingsWindowController.shared.show()
        }

        if CommandLine.arguments.contains("--brightness-selftest") {
            // verificação no contexto REAL do app, sem permissões herdadas
            let saida = ProcessInfo.processInfo.environment["DOCKA_SELFTEST_OUT"]
                ?? "/tmp/docka-brightness-selftest.txt"
            print("brilho: \(BrightnessBackend.autoteste(paraArquivo: saida))")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }

        if CommandLine.arguments.contains("--volume-selftest") {
            let saida = ProcessInfo.processInfo.environment["DOCKA_SELFTEST_OUT"]
                ?? "/tmp/docka-volume-selftest.txt"
            print("volume: \(VolumeBackend.autoteste(paraArquivo: saida))")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }

        if CommandLine.arguments.contains("--acordado-selftest") {
            let saida = ProcessInfo.processInfo.environment["DOCKA_SELFTEST_OUT"]
                ?? "/tmp/docka-acordado-selftest.txt"
            print("acordado: \(AcordadoBackend.autoteste(paraArquivo: saida))")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }

        if CommandLine.arguments.contains("--monitor-selftest") {
            print("monitor: \(MonitorModelo.autoteste())")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }

        if CommandLine.arguments.contains("--demo") {
            TrayManager.shared.startDemo()
        }
    }

    // o bloco de notas grava meio segundo depois da última tecla: encerrar
    // nesse meio-tempo perderia o fim do que foi escrito
    func applicationWillTerminate(_ notification: Notification) {
        NotasModelo.shared.gravarAgora()
    }

    // a bandeja continua viva com a janela fechada — é o ponto do app
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // clique no ícone do Dock (quando ele existe) reabre as configurações
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }
}

@main
struct DockaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DockaStore.shared
    @StateObject private var acordado = AcordadoSessao.shared
    @StateObject private var monitor = MonitorModelo.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent().environmentObject(store).environmentObject(acordado)
        } label: {
            // a xícara avisa que o Mac está sendo segurado acordado — sem ela,
            // é fácil esquecer ligado e estranhar a bateria no fim do dia
            let icone = Image(systemName: acordado.ativo ? "cup.and.saucer.fill" : "tray.full.fill")
            // a barra de menus só desenha um Text ou uma Image: o ícone vai
            // interpolado no texto para a leitura caber ao lado dele
            if let leitura = monitor.textoDaBarra(store.leituraDaBarra) {
                Text("\(icone) \(leitura)").monospacedDigit()
            } else {
                icone
            }
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: DockaStore
    @EnvironmentObject var acordado: AcordadoSessao

    var body: some View {
        Button("Abrir Configurações") { SettingsWindowController.shared.show() }
        Divider()
        menuAcordado
        if store.acoesRapidas {
            Menu("Ações rápidas") {
                ForEach(AcaoRapida.allCases.filter(AcoesRapidasBackend.disponivel)) { a in
                    Button {
                        AcoesRapidasBackend.executar(a)
                    } label: {
                        Label(AcoesRapidasBackend.titulo(a), systemImage: a.simbolo)
                    }
                }
            }
        }
        Divider()
        Toggle("Sons", isOn: $store.soundsEnabled)
        Toggle("Pressure Zone", isOn: $store.pressureZone)
        Toggle("Abrir no login", isOn: Binding(get: { store.launchAtLogin },
                                               set: { store.setLaunchAtLogin($0) }))
        Divider()
        Button("Encerrar o Docka") { NSApp.terminate(nil) }
    }

    @ViewBuilder
    private var menuAcordado: some View {
        if acordado.ativo {
            Menu("Acordado — \(acordado.restante)") {
                Button("Desligar") { acordado.desligar() }
                Divider()
                duracoes(titulo: "Recomeçar com")
            }
        } else {
            Menu("Manter acordado") { duracoes(titulo: nil) }
        }
    }

    @ViewBuilder
    private func duracoes(titulo: String?) -> some View {
        if let titulo { Text(titulo) }
        ForEach(DuracaoAcordado.allCases) { d in
            Button(d.titulo) { acordado.ligar(d, telaAcesa: store.acordadoTelaAcesa) }
        }
    }
}
