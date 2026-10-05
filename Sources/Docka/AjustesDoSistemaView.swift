import SwiftUI
import DockaCore

/// Ajustes → Ajustes do sistema: pequenas opções do macOS num lugar só.
struct AjustesDoSistemaView: View {
    @EnvironmentObject var store: DockaStore
    @State private var espacosFixos = AjustesDoSistemaController.espacosFixos
    @State private var aceleracaoAtual = AjustesDoSistemaController.aceleracaoAtual

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { espacosFixos }, set: { v in
                    espacosFixos = v
                    AjustesDoSistemaController.espacosFixos = v
                })) {
                    Text("Manter os Espaços na ordem")
                    Text("O macOS reorganiza os Espaços pelo uso mais recente; ligado, eles ficam sempre na ordem em que você os deixou. O Dock reinicia por um instante para valer.")
                }
            } header: {
                Text("Espaços")
            }

            Section {
                Toggle(isOn: $store.bloquearMusica) {
                    Text("Impedir o app Música de abrir sozinho")
                    Text("Quando o Música abre pelas costas — pela tecla de tocar, ao conectar fones —, o Docka o fecha. Abrindo de propósito (pelo Dock, Spotlight ou Launchpad), ele fica.")
                }
            } header: {
                Text("Música")
            }

            Section {
                Toggle(isOn: $store.bluetoothNoRepouso) {
                    Text("Desligar o Bluetooth no repouso")
                    Text("Ao dormir, o Bluetooth desliga — fones e caixinhas não ficam presos ao Mac fechado. Ao acordar, volta a ligar, só se estava ligado antes. Pede a permissão de Bluetooth.")
                }
                if store.bluetoothNoRepouso && !AjustesDoSistemaController.bluetoothPermitido {
                    Label("Falta a permissão de Bluetooth — o macOS pergunta ao ligar a opção.", systemImage: "exclamationmark.shield")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Bluetooth")
            }

            Section {
                Toggle(isOn: $store.aceleracaoControl) {
                    Text("Ajustar a aceleração do mouse")
                    Text("Com aceleração, mover a mão rápido leva o ponteiro mais longe. Sem ela, o ponteiro anda sempre na mesma proporção da mão — o que muita gente prefere para precisão. Ao desligar a opção, volta o que estava antes.")
                }
                if store.aceleracaoControl {
                    Toggle("Sem aceleração", isOn: Binding(
                        get: { store.aceleracao < 0 },
                        set: { store.aceleracao = $0 ? AjustesDoSistema.semAceleracao : 0.875 }))
                    if store.aceleracao >= 0 {
                        LabeledContent("Curva") {
                            Slider(value: $store.aceleracao, in: 0...3)
                                .frame(width: 220)
                            Text(String(format: "%.2f", store.aceleracao).replacingOccurrences(of: ".", with: ",")).monospacedDigit().frame(width: 40)
                        }
                    }
                }
            } header: {
                Text("Mouse")
            } footer: {
                if let a = aceleracaoAtual {
                    Text(a < 0 ? "Agora: sem aceleração."
                         : "Agora: aceleração " + String(format: "%.3f", a).replacingOccurrences(of: ".", with: ",") + ". O trackpad não é afetado.")
                }
            }
            .onChange(of: store.aceleracaoControl) { _, _ in aceleracaoAtual = AjustesDoSistemaController.aceleracaoAtual }
            .onChange(of: store.aceleracao) { _, _ in aceleracaoAtual = AjustesDoSistemaController.aceleracaoAtual }
        }
        .formStyle(.grouped)
    }
}
