import SwiftUI
import DockaCore

/// Campo que captura uma nova combinação de teclas.
///
/// Usa um monitor **local** de eventos (`addLocalMonitorForEvents`): ele só
/// enxerga teclas enquanto a janela do Docka está em foco, e por isso continua
/// dispensando a permissão de Monitoramento de Entrada.
struct ShortcutRecorder: View {
    @EnvironmentObject var store: DockaStore
    @State private var gravando = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Button { gravando ? parar() : gravar() } label: {
                Text(gravando ? "Pressione a combinação…" : store.shortcut.display)
                    .font(.system(size: 13, weight: .semibold,
                                  design: gravando ? .default : .rounded))
                    .foregroundStyle(gravando ? Theme.accent : .white)
                    .frame(minWidth: 150)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(.black.opacity(gravando ? 0.4 : 0.25)))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(gravando ? Theme.accent : .white.opacity(0.12),
                                      lineWidth: gravando ? 1.5 : 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Atalho global do Docka")
            .accessibilityValue(gravando ? "Gravando" : store.shortcut.spokenDescription)
            .accessibilityHint(gravando
                               ? "Pressione a nova combinação, ou Esc para cancelar"
                               : "Ative para gravar uma nova combinação")

            if store.shortcut != .padrao && !gravando {
                Button("Restaurar padrão") { store.resetShortcut() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
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
                store.setShortcut(novo)
                // combinação recusada: segue gravando para o usuário tentar outra
                if novo.isValid && store.shortcutError == nil { parar() }
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
