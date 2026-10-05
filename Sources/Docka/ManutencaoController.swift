import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DockaCore

/// A janela de manutenção: atualizações, limpeza, downloads dos mensageiros,
/// desinstalador, Homebrew e portas abertas. Nada roda sozinho: cada seção
/// só lê ou mexe quando você clica, e o que sai vai para o Lixo.
final class ManutencaoController: NSObject, NSWindowDelegate {
    static let shared = ManutencaoController()

    enum Secao: String, CaseIterable, Identifiable {
        case atualizacoes, limpeza, mensageiros, desinstalador, homebrew, portas
        var id: String { rawValue }
        var titulo: String {
            switch self {
            case .atualizacoes:  return "Atualizações"
            case .limpeza:       return "Limpeza"
            case .mensageiros:   return "Mensageiros"
            case .desinstalador: return "Desinstalador"
            case .homebrew:      return "Homebrew"
            case .portas:        return "Portas abertas"
            }
        }
        var simbolo: String {
            switch self {
            case .atualizacoes:  return "arrow.down.app"
            case .limpeza:       return "sparkles"
            case .mensageiros:   return "bubble.left.and.bubble.right"
            case .desinstalador: return "trash"
            case .homebrew:      return "mug"
            case .portas:        return "network"
            }
        }
    }

    final class Estado: ObservableObject {
        @Published var secao: Secao = .atualizacoes
        let atualizacoes = AtualizacoesModelo()
        let limpeza = LimpezaModelo()
        let mensageiros = MensageirosModelo()
        let desinstalador = DesinstaladorModelo()
        let homebrew = HomebrewModelo()
        let portas = PortasModelo()
    }

    let estado = Estado()
    private var janela: NSWindow?

    func abrir(_ secao: Secao? = nil) {
        if let secao { estado.secao = secao }
        let w = janela ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Manutenção"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 760, height: 480)
            let hv = NSHostingView(rootView: ManutencaoView().environmentObject(estado))
            // a janela tem o tamanho que você der: sem isto, uma lista longa
            // a esticava além da tela
            hv.sizingOptions = []
            w.contentView = hv
            w.center()
            w.delegate = self
            return w
        }()
        janela = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let outras = NSApp.windows.contains { $0 !== janela && $0.isVisible && $0.styleMask.contains(.titled) }
        if !outras { NSApp.setActivationPolicy(.accessory) }
    }
}

struct ManutencaoView: View {
    @EnvironmentObject var e: ManutencaoController.Estado

    /// Barra lateral fixa e o conteúdo ao lado. (O NavigationSplitView, numa
    /// janela AppKit, media o conteúdo pela lista inteira e o empurrava para
    /// fora da janela.)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ManutencaoController.Secao.allCases) { s in
                    Button { e.secao = s } label: {
                        Label(s.titulo, systemImage: s.simbolo)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(e.secao == s ? Color.accentColor.opacity(0.25) : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(e.secao == s ? .isSelected : [])
                }
                Spacer()
            }
            .padding(8)
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.04))
            Divider()
            Group {
                switch e.secao {
                case .atualizacoes:  AtualizacoesView(m: e.atualizacoes, brew: e.homebrew)
                case .limpeza:       LimpezaView(m: e.limpeza)
                case .mensageiros:   MensageirosView(m: e.mensageiros)
                case .desinstalador: DesinstaladorView(m: e.desinstalador)
                case .homebrew:      HomebrewView(m: e.homebrew)
                case .portas:        PortasView(m: e.portas)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

// MARK: - Peças comuns

private struct Cabecalho: View {
    let titulo: String
    let texto: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.title2.bold())
            Text(texto).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

private struct LinhaMarcavel: View {
    let item: ItemParaLimpar
    let alternar: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { item.marcado }, set: { _ in alternar() })).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.titulo).lineLimit(1).truncationMode(.middle)
                Text(item.detalhe).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Manutencao.tamanho(item.tamanho)).monospacedDigit().foregroundStyle(.secondary)
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help("Mostrar no Finder")
        }
    }
}

// MARK: - Atualizações

private struct AtualizacoesView: View {
    @ObservedObject var m: AtualizacoesModelo
    @ObservedObject var brew: HomebrewModelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cabecalho(titulo: "Atualizações",
                      texto: "Confere os apps de Aplicativos no feed que cada um declara (o do próprio desenvolvedor), na App Store e no Homebrew. Só quando você clica em Procurar — o Docka não fica olhando nada sozinho.")
            HStack {
                Button(m.procurando ? "Procurando…" : "Procurar") { m.procurar() }.disabled(m.procurando)
                let doBrew = m.resultados.compactMap { a -> String? in if case .homebrew(let alvo) = a.origem { return alvo }; return nil }
                if !doBrew.isEmpty {
                    Button("Atualizar \(doBrew.count) pelo Homebrew") { m.atualizarPeloBrew(doBrew, log: brew) }
                        .disabled(brew.trabalhando)
                }
                Spacer()
                Text(m.estado).font(.callout).foregroundStyle(.secondary)
            }
            List(m.resultados) { a in
                HStack {
                    Group {
                        if let app = a.app { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable() }
                        else { Image(systemName: "mug").resizable().scaledToFit().padding(3) }
                    }
                    .frame(width: 22, height: 22)
                    Text(a.nome)
                    Text("\(a.atual) → \(a.nova)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    switch a.origem {
                    case .desenvolvedor:
                        Button("Abrir o app") { if let app = a.app { NSWorkspace.shared.open(app) } }
                            .help("O app se atualiza pelo próprio menu (Procurar atualizações)")
                    case .appStore(let url):
                        Button("App Store") { NSWorkspace.shared.open(url ?? URL(string: "macappstore://showUpdatesPage")!) }
                    case .homebrew(let alvo):
                        Button("Atualizar") { m.atualizarPeloBrew([alvo], log: brew) }.disabled(brew.trabalhando)
                    }
                }
            }
            if !brew.registro.isEmpty { RegistroView(texto: brew.registro).frame(height: 110) }
        }
    }
}

private struct RegistroView: View {
    let texto: String
    var body: some View {
        ScrollView {
            Text(texto).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Limpeza

private struct LimpezaView: View {
    @ObservedObject var m: LimpezaModelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cabecalho(titulo: "Limpeza",
                      texto: "Caches e registros se refazem sozinhos; os restos são de apps que já não estão instalados. Os caches do macOS, o de um app aberto e os restos vêm desmarcados — revise antes. Tudo vai para o Lixo, de onde dá para recuperar.")
            HStack {
                Button(m.analisando ? "Medindo…" : "Analisar") { m.analisar() }.disabled(m.analisando)
                Button("Mover os marcados para o Lixo") { m.limpar() }.disabled(m.marcados.isEmpty || m.analisando)
                Spacer()
                Text(m.estado).font(.callout).foregroundStyle(.secondary)
            }
            List {
                ForEach(LimpezaModelo.Grupo.allCases) { g in
                    if let lista = m.itens[g], !lista.isEmpty {
                        Section("\(g.titulo) — \(Manutencao.tamanho(lista.reduce(0) { $0 + $1.tamanho }))") {
                            ForEach(lista) { i in LinhaMarcavel(item: i) { m.alternar(g, i.id) } }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Mensageiros

private struct MensageirosView: View {
    @ObservedObject var m: MensageirosModelo
    @EnvironmentObject var e: ManutencaoController.Estado

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cabecalho(titulo: "Downloads dos mensageiros",
                      texto: "Fotos, vídeos e arquivos que o WhatsApp e o Telegram guardam, e as pastas que você acrescentar. Os mais velhos que o prazo podem ir para o Lixo ou ser juntados em Downloads › Mensageiros, por mês.")
            HStack {
                Picker("Mais velhos que", selection: $m.dias) {
                    ForEach([7, 30, 90, 180, 365], id: \.self) { Text("\($0) dias").tag($0) }
                }
                .fixedSize()
                Button(m.analisando ? "Procurando…" : "Procurar") { m.analisar() }.disabled(m.analisando)
                Button("Acrescentar pasta…") { acrescentar() }
                Spacer()
            }
            HStack {
                Text(m.estado).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Organizar em pastas") { m.organizar() }.disabled(!m.achados.contains(where: \.marcado))
                Button("Mover para o Lixo") { m.paraOLixo() }.disabled(!m.achados.contains(where: \.marcado))
            }
            if !m.semAcesso.isEmpty {
                HStack {
                    Label("O macOS não deixa ler a pasta de \(m.semAcesso.joined(separator: " e ")): ela é dado de outro app. Libere o Docka em Acesso Total ao Disco e procure de novo.",
                          systemImage: "lock.fill")
                        .font(.callout).foregroundStyle(.orange)
                    Spacer()
                    Button("Abrir Privacidade") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
            }
            List(m.achados) { i in LinhaMarcavel(item: i) { m.alternar(i.id) } }
        }
    }

    private func acrescentar() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        guard p.runModal() == .OK, let u = p.url else { return }
        if !DockaStore.shared.pastasDeMensageiros.contains(u.path) { DockaStore.shared.pastasDeMensageiros.append(u.path) }
    }
}

// MARK: - Desinstalador

private struct DesinstaladorView: View {
    @ObservedObject var m: DesinstaladorModelo
    @State private var alvo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cabecalho(titulo: "Desinstalador",
                      texto: "Escolha ou solte um app: ele e os arquivos dele na Biblioteca (ajustes, caches, dados, agentes) vão para o Lixo juntos. Revise a lista antes; apps do macOS não são removidos.")
            HStack {
                Menu("Escolher app") {
                    ForEach(Arquivos.apps(), id: \.self) { a in Button(Arquivos.nome(a)) { m.escolher(a) } }
                }
                .fixedSize()
                if let app = m.app {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 22, height: 22)
                    Text(Arquivos.nome(app)).bold()
                }
                Spacer()
                if let aberto = m.aberto {
                    Button("Encerrar o app") { aberto.terminate() }
                }
                Button("Mover para o Lixo") { m.desinstalar() }
                    .disabled(m.itens.isEmpty || m.procurando || m.aberto != nil)
            }
            Text(m.estado).font(.callout).foregroundStyle(.secondary)
            List(m.itens) { i in LinhaMarcavel(item: i) { m.alternar(i.id) } }
                .overlay {
                    if m.itens.isEmpty {
                        Text("Solte um app aqui").foregroundStyle(alvo ? Color.accentColor : .secondary)
                    }
                }
        }
        .onDrop(of: [.fileURL], isTargeted: $alvo) { ps in
            _ = ps.first?.loadObject(ofClass: URL.self) { u, _ in
                if let u, u.pathExtension == "app" { DispatchQueue.main.async { m.escolher(u) } }
            }
            return true
        }
    }
}

// MARK: - Homebrew

private struct HomebrewView: View {
    @ObservedObject var m: HomebrewModelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cabecalho(titulo: "Homebrew",
                      texto: "Procure, instale e remova fórmulas e casks sem abrir o Terminal. Os comandos são os do próprio brew, e a saída aparece embaixo.")
            if !m.disponivel {
                Text("O Homebrew não está instalado neste Mac (brew.sh).").foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField("Procurar fórmula ou cask", text: $m.busca).onSubmit { m.buscar() }
                    Button("Procurar") { m.buscar() }
                }
                if !m.encontrados.formulas.isEmpty || !m.encontrados.casks.isEmpty {
                    List {
                        Section("Encontrados") {
                            ForEach(m.encontrados.casks, id: \.self) { c in linhaBusca(c, cask: true) }
                            ForEach(m.encontrados.formulas, id: \.self) { f in linhaBusca(f, cask: false) }
                        }
                    }
                    .frame(maxHeight: 160)
                }
                List {
                    Section("Instalados (\(m.instalados.count))") {
                        ForEach(m.instalados) { p in
                            HStack {
                                Image(systemName: p.cask ? "app.badge" : "terminal").frame(width: 18)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(p.nome)
                                    if !p.descricao.isEmpty { Text(p.descricao).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Text(p.versao).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                Button("Remover") { m.remover(p) }.disabled(m.trabalhando)
                            }
                        }
                    }
                }
                if !m.registro.isEmpty { RegistroView(texto: m.registro).frame(height: 110) }
            }
        }
        .onAppear { if m.instalados.isEmpty { m.carregar() } }
    }

    private func linhaBusca(_ nome: String, cask: Bool) -> some View {
        let instalado = m.instalados.contains { $0.nome == nome && $0.cask == cask }
        return HStack {
            Image(systemName: cask ? "app.badge" : "terminal").frame(width: 18)
            Text(nome)
            Text(cask ? "cask" : "fórmula").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if instalado { Text("instalado").font(.caption).foregroundStyle(.secondary) }
            else { Button("Instalar") { m.instalar(nome, cask: cask) }.disabled(m.trabalhando) }
        }
    }
}

// MARK: - Portas

private struct PortasView: View {
    @ObservedObject var m: PortasModelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cabecalho(titulo: "Portas abertas",
                      texto: "Os programas seus que estão esperando conexões. \"Só neste Mac\" não aceita ninguém de fora; \"na rede\" aceita conexões de outros aparelhos. Os do sistema (de outros usuários) não aparecem sem a senha de administrador.")
            HStack {
                Button("Atualizar") { m.atualizar() }
                Spacer()
                Text(m.estado).font(.callout).foregroundStyle(.secondary)
            }
            List(m.portas) { p in
                HStack {
                    Group {
                        if let i = NSRunningApplication(processIdentifier: p.pid)?.icon { Image(nsImage: i).resizable() }
                        else { Image(systemName: "gearshape").resizable().scaledToFit().padding(3) }
                    }
                    .frame(width: 20, height: 20)
                    Text(p.processo)
                    Text(verbatim: "pid \(p.pid)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: "\(p.protocolo) \(p.porta)").monospacedDigit()
                    Text(p.exposta ? "na rede" : "só neste Mac")
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(p.exposta ? Color.orange.opacity(0.2) : Color.green.opacity(0.15)))
                    Button("Encerrar") { m.encerrar(p) }
                }
            }
        }
        .onAppear { m.atualizar() }
    }
}

// MARK: - Autoteste (só leitura)

extension ManutencaoController {
    /// Lê tudo e não mexe em nada: nenhum arquivo vai para o Lixo, nenhum
    /// comando do brew muda o sistema. A rede só com `DOCKA_REDE` definido.
    static func autoteste(pasta: String) async -> String {
        var r: [String] = []
        func conferir(_ nome: String, _ ok: Bool) { r.append("\(ok ? "OK" : "FALHOU") — \(nome)") }
        let apps = Arquivos.apps()
        conferir("\(apps.count) apps em Aplicativos", !apps.isEmpty)

        let (lsof, _) = await Comando.rodar("/usr/sbin/lsof", ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP"], soSaida: true)
        let portas = Manutencao.lerPortas(lsof)
        conferir("portas: \(portas.count) abertas, \(portas.filter(\.exposta).count) na rede — " +
                 portas.prefix(6).map { "\($0.processo):\($0.porta)" }.joined(separator: ", "), true)

        let caches = Arquivos.conteudo("~/Library/Caches").reduce(Int64(0)) { $0 + Arquivos.tamanho($1) }
        let logs = Arquivos.conteudo("~/Library/Logs").reduce(Int64(0)) { $0 + Arquivos.tamanho($1) }
        conferir("caches \(Manutencao.tamanho(caches)), registros \(Manutencao.tamanho(logs)) (só medido)", caches > 0)

        let limpeza = LimpezaModelo()
        await MainActor.run { limpeza.analisar() }
        for _ in 0..<600 where await MainActor.run(body: { limpeza.analisando }) { try? await Task.sleep(nanoseconds: 100_000_000) }
        let restos = await MainActor.run { limpeza.itens[.restos] ?? [] }
        conferir("restos de apps removidos: \(restos.count), \(Manutencao.tamanho(restos.reduce(0) { $0 + $1.tamanho })) — " +
                 restos.prefix(5).map(\.titulo).joined(separator: ", ") + " (nenhum marcado: \(restos.allSatisfy { !$0.marcado }))",
                 restos.allSatisfy { !$0.marcado })

        // o desinstalador num app de terceiros qualquer, só listando
        if let alvo = apps.first(where: { !Manutencao.protegido(Arquivos.info($0)["CFBundleIdentifier"] as? String ?? "") }) {
            let d = DesinstaladorModelo()
            await MainActor.run { d.escolher(alvo) }
            for _ in 0..<300 where await MainActor.run(body: { d.procurando }) { try? await Task.sleep(nanoseconds: 100_000_000) }
            let itens = await MainActor.run { d.itens }
            conferir("desinstalador (\(Arquivos.nome(alvo)), sem remover): " +
                     itens.map { "\($0.detalhe)/\($0.titulo)" }.prefix(8).joined(separator: "; "), itens.first?.url == alvo)
        }
        let sistema = DesinstaladorModelo()
        await MainActor.run { sistema.escolher(URL(fileURLWithPath: "/System/Applications/Calculator.app")) }
        conferir("app do macOS é recusado", await MainActor.run { sistema.itens.isEmpty })

        if let brew = AtualizacoesModelo.brew {
            let (saida, codigo) = await Comando.rodar(brew, ["info", "--json=v2", "--installed"], ambiente: ["HOMEBREW_NO_AUTO_UPDATE": "1"], soSaida: true)
            let json = (try? JSONSerialization.jsonObject(with: Data(saida.utf8))) as? [String: Any]
            conferir("Homebrew: \((json?["formulae"] as? [Any])?.count ?? 0) fórmulas, \((json?["casks"] as? [Any])?.count ?? 0) casks", codigo == 0)
        } else { r.append("ℹ️ Homebrew não instalado") }

        for f in MensageirosModelo.conhecidas {
            let existe = FileManager.default.fileExists(atPath: (f.pasta as NSString).expandingTildeInPath)
            r.append("ℹ️ \(f.nome): \(existe ? "pasta encontrada" : "não usado neste Mac")")
        }

        if ProcessInfo.processInfo.environment["DOCKA_REDE"] != nil {
            let a = AtualizacoesModelo()
            await MainActor.run { a.procurar() }
            for _ in 0..<900 where await MainActor.run(body: { a.procurando }) { try? await Task.sleep(nanoseconds: 100_000_000) }
            let (estado, res) = await MainActor.run { (a.estado, a.resultados) }
            conferir("atualizações: \(estado) " + res.map { "\($0.nome) \($0.atual)→\($0.nova)" }.joined(separator: "; "), !estado.isEmpty)
        }
        return r.joined(separator: "\n")
    }
}
