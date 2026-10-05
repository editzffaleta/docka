import SwiftUI
import DockaCore

/// Ajustes → Ilha Dinâmica: ligar, quando abrir, seções (ordem, quais
/// aparecem e o atalho de cada uma) e os botões dos lados.
struct IlhaSettingsView: View {
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.ilhaControl) {
                    Text("Ilha Dinâmica")
                    Text("Uma ilha preta em volta do recorte da câmera: passe o cursor e ela cresce; clique e ela abre numa grade de seções. Fechada, mostra o que está correndo — como o tempo do timer.")
                }
                if store.ilhaControl {
                    Picker("Abrir ao parar o cursor", selection: $store.ilhaAbrirAoPairar) {
                        Text("Só no clique").tag(0.0)
                        Text("Rápido").tag(0.25)
                        Text("Meio segundo").tag(0.5)
                        Text("Um segundo").tag(1.0)
                    }
                    Toggle(isOn: $store.ilhaCombinar) {
                        Text("Combinar atividades")
                        Text("Com duas coisas correndo (timer e música, por exemplo), cada uma fica numa asa da ilha.")
                    }
                    Toggle("Tocar um som quando o timer terminar", isOn: $store.ilhaSomDoTimer)
                    LabeledContent("Atalho para abrir") { ShortcutRecorder(acao: .ilha) }
                }
            } header: {
                Text("Ilha Dinâmica")
            } footer: {
                Text("Fica na tela com o recorte da câmera. Em Macs sem recorte, a ilha é simulada no meio do topo da tela principal. Não pede permissão nenhuma.")
            }

            if store.ilhaControl {
                Section {
                    let ordem = Ilha.ordem(gravada: store.ilhaOrdem)
                    ForEach(Array(ordem.enumerated()), id: \.element) { i, s in
                        linha(s, indice: i, total: ordem.count)
                    }
                } header: {
                    Text("Seções")
                } footer: {
                    Text("A ordem aqui é a da grade. As marcadas \"em breve\" chegam nas próximas versões.")
                }

                Section {
                    Toggle(isOn: $store.ilhaLetra) {
                        Text("Letra sincronizada")
                        Text("Mostra o verso que está tocando. A letra vem do lrclib.net, uma base aberta: vão o título, o artista, o álbum e a duração da música.")
                    }
                    Toggle(isOn: $store.ilhaEqualizadorAoVivo) {
                        Text("Equalizador ao vivo")
                        Text("As barras medem o som de verdade. Pede Gravação de Tela, e o macOS mostra o aviso de gravação na barra de menus enquanto a música toca. Desligado, as barras só animam.")
                    }
                } header: {
                    Text("Música")
                } footer: {
                    Text("A ilha mostra o que toca em qualquer app ou aba do navegador que anuncie a música ao sistema. Para isso usa um caminho interno do macOS: se uma atualização fechá-lo, a seção avisa.")
                }

                Section {
                    Toggle(isOn: $store.ilhaNotificacoes) {
                        Text("Notificações na ilha")
                        Text("Guarda os avisos que aparecem na tela para você rever na ilha. Só na memória: tudo some ao travar a tela ou desligar. Pede Acessibilidade.")
                    }
                } header: {
                    Text("Notificações")
                }

                Section {
                    Toggle(isOn: $store.ilhaAvisoAgentes) {
                        Text("Avisar quando uma tarefa longa terminar")
                        Text("Quando o Claude Code termina de trabalhar depois de um bom tempo, a ilha abre com um aviso e um som.")
                    }
                    if store.ilhaAvisoAgentes {
                        Picker("Tarefa longa é a partir de", selection: $store.ilhaAvisoAgentesMinutos) {
                            Text("1 minuto").tag(1.0)
                            Text("3 minutos").tag(3.0)
                            Text("5 minutos").tag(5.0)
                            Text("10 minutos").tag(10.0)
                        }
                    }
                } header: {
                    Text("Agentes de IA")
                } footer: {
                    Text("A ilha lê os registros que o Claude Code e o Codex gravam no Mac (~/.claude e ~/.codex): só números de uso, modelos e horários — o texto das conversas nunca é lido para guardar. O valor em dólares é uma estimativa pelos preços públicos da API, e só aparece para modelos com preço conhecido.")
                }

                Section {
                    Toggle("Carregador e bateria baixa", isOn: $store.ilhaAvisoBateria)
                    Toggle("Fones conectando", isOn: $store.ilhaAvisoFones)
                    Toggle("Volume", isOn: $store.ilhaAvisoVolume)
                    Toggle("Brilho da tela do Mac", isOn: $store.ilhaAvisoBrilho)
                    Toggle("Algo copiado", isOn: $store.ilhaAvisoCopiado)
                } header: {
                    Text("Avisos rápidos")
                } footer: {
                    Text("Aparecem nas asas da ilha fechada por alguns segundos: ao ligar ou tirar o carregador, com a bateria em 20%, 10% e 5%, quando um fone conecta, ao mudar o volume ou o brilho e ao copiar algo. Não pedem permissão.")
                }

                Section("Botões dos lados") {
                    lado("Esquerda", $store.ilhaBotoesEsquerda)
                    lado("Direita", $store.ilhaBotoesDireita)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func linha(_ s: Ilha.Secao, indice: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { !store.ilhaOcultas.contains(s.rawValue) },
                set: { mostrar in
                    store.ilhaOcultas.removeAll { $0 == s.rawValue }
                    if !mostrar { store.ilhaOcultas.append(s.rawValue) }
                }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(systemName: s.simbolo).frame(width: 20).foregroundStyle(Color.accentColor)
            Text(s.titulo)
            if !s.disponivel {
                Text("em breve").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            Spacer()
            if s.disponivel { ShortcutRecorder(acao: .secaoDaIlha(s)) }
            Button { mover(s, -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(indice == 0)
                .accessibilityLabel("Subir \(s.titulo)")
            Button { mover(s, 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(indice == total - 1)
                .accessibilityLabel("Descer \(s.titulo)")
        }
    }

    private func mover(_ s: Ilha.Secao, _ passo: Int) {
        var ordem = Ilha.ordem(gravada: store.ilhaOrdem)
        guard let i = ordem.firstIndex(of: s), ordem.indices.contains(i + passo) else { return }
        ordem.swapAt(i, i + passo)
        store.ilhaOrdem = ordem.map(\.rawValue)
    }

    /// Até três botões de cada lado.
    private func lado(_ titulo: String, _ lista: Binding<[String]>) -> some View {
        LabeledContent(titulo) {
            HStack {
                ForEach(0..<3, id: \.self) { i in
                    Picker("", selection: Binding(
                        get: { lista.wrappedValue.indices.contains(i) ? lista.wrappedValue[i] : "" },
                        set: { novo in
                            var l = lista.wrappedValue
                            while l.count <= i { l.append("") }
                            l[i] = novo
                            lista.wrappedValue = l.filter { !$0.isEmpty }
                        })) {
                        Text("Nenhum").tag("")
                        ForEach(Ilha.BotaoLateral.allCases.filter(\.disponivel)) { b in
                            Label(b.titulo, systemImage: b.simbolo).tag(b.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
        }
    }
}
