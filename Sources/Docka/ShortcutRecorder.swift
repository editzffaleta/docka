import SwiftUI
import DockaCore

/// Campo que captura uma nova combinação de teclas para uma ação.
///
/// Usa um monitor **local** de eventos (`addLocalMonitorForEvents`): ele só
/// enxerga teclas enquanto a janela do Docka está em foco, e por isso continua
/// dispensando a permissão de Monitoramento de Entrada.
struct ShortcutRecorder: View {
    let acao: AcaoDeAtalho
    @EnvironmentObject var store: DockaStore
    @State private var gravando = false
    @State private var monitor: Any?

    private var atual: Shortcut? { store.atalho(de: acao) }

    var body: some View {
        HStack(spacing: 8) {
            Button { gravando ? parar() : gravar() } label: {
                Text(gravando ? "Pressione…" : (atual?.display ?? "Nenhum"))
                    .monospacedDigit()
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .tint(gravando ? .accentColor : nil)
            .accessibilityLabel("Atalho de \(store.nomeDaAcao(acao.id))")
            .accessibilityValue(gravando ? "Gravando"
                                : (atual?.spokenDescription ?? "Nenhum atalho"))
            .accessibilityHint(gravando
                               ? "Pressione a nova combinação, ou Esc para cancelar"
                               : "Ative para gravar uma nova combinação")

            // limpar é uma opção de verdade: uma ação pode simplesmente não ter
            // atalho, e antes não havia como abrir mão do que estava gravado
            if atual != nil && !gravando {
                Button { store.definirAtalho(nil, para: acao) } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remover este atalho")
                .accessibilityLabel("Remover o atalho de \(store.nomeDaAcao(acao.id))")
            }
        }
        // sair da aba com o monitor ativo deixaria o teclado sequestrado
        .onDisappear { parar() }
    }

    private func gravar() {
        gravando = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {          // Esc cancela sem trocar nada
                parar()
                return nil
            }
            if let novo = Shortcut(event: event) {
                store.definirAtalho(novo, para: acao)
                // combinação recusada: segue gravando para o usuário tentar outra
                if novo.isValid && store.erroDoAtalho(acao) == nil { parar() }
            }
            return nil                        // a tecla não vaza para a janela
        }
    }

    private func parar() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        gravando = false
    }
}
