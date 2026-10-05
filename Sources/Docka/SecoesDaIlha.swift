import SwiftUI
import AppKit
import QuickLookThumbnailing
import DockaCore

// MARK: - O modelo dos arquivos (capturas e downloads)

/// As capturas recentes e os downloads, lidos do disco só com a seção à
/// vista — e o progresso dos downloads em andamento, que os navegadores
/// publicam para o Finder desenhar a barrinha no ícone.
final class ArquivosDaIlhaModelo: ObservableObject {
    static let shared = ArquivosDaIlhaModelo()

    struct EmAndamento: Identifiable, Equatable {
        let id: String          // o caminho
        let nome: String
        var fracao: Double
    }

    @Published private(set) var capturas: [ArquivosDaIlha.Arquivo] = []
    @Published private(set) var downloads: [ArquivosDaIlha.Arquivo] = []
    @Published private(set) var emAndamento: [EmAndamento] = []
    @Published private(set) var miniaturas: [String: NSImage] = [:]
    @Published private(set) var pastaDeCapturas = ""

    /// Para o arrasto para fora (a mesma origem de arrasto da prateleira).
    let estadoDeArrasto = PrateleiraEstado()

    private var assinatura: Any?
    private var progressos: [String: Progress] = [:]

    static var pastaDeDownloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    // MARK: leitura das pastas

    func atualizarCapturas() {
        let gravada = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
        let pasta = ArquivosDaIlha.pastaDeCapturas(gravada: gravada, home: NSHomeDirectory())
        pastaDeCapturas = pasta
        ler(pasta) { [weak self] lista in
            let r = ArquivosDaIlha.capturas(lista, limite: 6)
            if r != self?.capturas { self?.capturas = r }
            self?.miniaturasDe(r)
        }
    }

    func atualizarDownloads() {
        ler(Self.pastaDeDownloads.path) { [weak self] lista in
            let r = ArquivosDaIlha.recentes(lista, limite: 6)
            if r != self?.downloads { self?.downloads = r }
            self?.miniaturasDe(r)
        }
    }

    /// Lê a pasta fora da linha principal: uma pasta de rede lenta não pode
    /// travar a ilha.
    private func ler(_ pasta: String, _ pronto: @escaping ([ArquivosDaIlha.Arquivo]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let chaves: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .isPackageKey]
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: pasta), includingPropertiesForKeys: chaves,
                options: [.skipsHiddenFiles])) ?? []
            let lista = urls.compactMap { u -> ArquivosDaIlha.Arquivo? in
                guard let v = try? u.resourceValues(forKeys: Set(chaves)) else { return nil }
                // pastas ficam de fora; pacotes (.app, .download do Safari) entram
                if v.isDirectory == true && v.isPackage != true { return nil }
                return ArquivosDaIlha.Arquivo(caminho: u.path, data: v.contentModificationDate ?? .distantPast,
                                              tamanho: Int64(v.fileSize ?? 0))
            }
            DispatchQueue.main.async { pronto(lista) }
        }
    }

    private func miniaturasDe(_ arquivos: [ArquivosDaIlha.Arquivo]) {
        for a in arquivos where miniaturas[chave(a)] == nil {
            let pedido = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: a.caminho),
                                                      size: CGSize(width: 120, height: 80), scale: 2,
                                                      representationTypes: .thumbnail)
            let k = chave(a)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: pedido) { [weak self] r, _ in
                let img = r?.nsImage ?? NSWorkspace.shared.icon(forFile: a.caminho)
                DispatchQueue.main.async { self?.miniaturas[k] = img }
            }
        }
    }

    func chave(_ a: ArquivosDaIlha.Arquivo) -> String { "\(a.caminho)|\(a.data.timeIntervalSince1970)" }

    // MARK: downloads em andamento

    /// Assina o progresso publicado para os arquivos da pasta Downloads. Não
    /// lê a pasta: só recebe o que os navegadores anunciam.
    func observarDownloads(_ ligar: Bool) {
        if ligar, assinatura == nil {
            assinatura = Progress.addSubscriber(forFileURL: Self.pastaDeDownloads) { [weak self] p in
                // do lado de quem assina, a propriedade `fileURL` vem vazia; o
                // endereço chega só no userInfo (visto no teste com um
                // download anunciado de verdade)
                let url = p.fileURL ?? p.userInfo[.fileURLKey] as? URL
                let k = url?.path ?? "download-\(ObjectIdentifier(p).hashValue)"
                DispatchQueue.main.async { self?.progressos[k] = p; self?.lerProgressos() }
                return {
                    DispatchQueue.main.async {
                        self?.progressos[k] = nil
                        self?.lerProgressos()
                        self?.atualizarDownloads()
                    }
                }
            }
        } else if !ligar, let a = assinatura {
            Progress.removeSubscriber(a)
            assinatura = nil
            progressos = [:]
            emAndamento = []
        }
    }

    /// Chamado pelo tique da ilha: a fração anda sem avisar.
    func lerProgressos() {
        let novos = progressos.map { k, p in
            EmAndamento(id: k, nome: ArquivosDaIlha.nomeFinal((k as NSString).lastPathComponent),
                        fracao: p.fractionCompleted)
        }.sorted { $0.id < $1.id }
        if novos != emAndamento { emAndamento = novos }
    }

    var atividade: Ilha.Atividade? {
        guard let geral = ArquivosDaIlha.progressoGeral(emAndamento.map(\.fracao)) else { return nil }
        return Ilha.Atividade(id: "download", tipo: .download, simbolo: "arrow.down.circle",
                              valor: ArquivosDaIlha.porcentagem(geral), prioridade: 30, progresso: geral)
    }
}

// MARK: - Peças comuns

/// Um cartão escuro, como os blocos da grade.
private struct CartaoDaIlha<C: View>: View {
    @ViewBuilder let conteudo: C
    var body: some View {
        conteudo
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }
}

private struct BotaoPilula: View {
    let titulo: String
    var simbolo: String? = nil
    var destaque = false
    let acao: () -> Void
    var body: some View {
        Button(action: acao) {
            HStack(spacing: 4) {
                if let simbolo { Image(systemName: simbolo).font(.system(size: 10, weight: .semibold)) }
                Text(titulo).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(destaque ? Color.black : Color.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(destaque ? Color.orange : Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Um arquivo como bloco: miniatura e nome, arrastável para fora; o clique abre.
private struct BlocoDeArquivo: View {
    let arquivo: ArquivosDaIlha.Arquivo
    let agora: Date
    @ObservedObject var modelo = ArquivosDaIlhaModelo.shared

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let img = modelo.miniaturas[modelo.chave(arquivo)] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: arquivo.caminho)).resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 80, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(arquivo.nome).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.white)
            Text(ArquivosDaIlha.quando(arquivo.data, agora: agora)).font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(width: 92)
        .overlay(ArrastoDeSaida(itens: [ItemDaPrateleira(tipo: .arquivo, valor: arquivo.caminho)],
                                estado: modelo.estadoDeArrasto,
                                aoClicar: { NSWorkspace.shared.open(URL(fileURLWithPath: arquivo.caminho)) }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(arquivo.nome)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { NSWorkspace.shared.open(URL(fileURLWithPath: arquivo.caminho)) }
    }
}

// MARK: - Controles

struct ControlesDaIlha: View {
    let fechar: () -> Void
    @EnvironmentObject var store: DockaStore
    @ObservedObject private var acordado = AcordadoSessao.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CartaoDaIlha {
                HStack(spacing: 10) {
                    Image(systemName: acordado.ativo ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 16)).foregroundStyle(acordado.ativo ? Color.orange : .white.opacity(0.6))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Manter acordado").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        Text(acordado.ativo ? (acordado.fim == nil ? "Ligado até você desligar" : "Faltam \(acordado.restante)")
                                            : "O Mac não dorme sozinho")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    ForEach([DuracaoAcordado.trintaMinutos, .umaHora, .duasHoras, .semLimite]) { d in
                        BotaoPilula(titulo: d == .semLimite ? "Sempre" : d.titulo) {
                            acordado.ligar(d, telaAcesa: store.acordadoTelaAcesa)
                        }
                    }
                    if acordado.ativo { BotaoPilula(titulo: "Desligar", destaque: true) { acordado.desligar() } }
                }
            }
            .frame(height: 50)
            let acoes = AcaoRapida.allCases.filter(AcoesRapidasBackend.disponivel)
            HStack(spacing: 8) {
                ForEach(acoes) { a in
                    Button {
                        fechar()
                        // depois de a ilha sumir: travar a tela com ela aberta deixaria o
                        // desenho dela na foto da tela de bloqueio
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AcoesRapidasBackend.executar(a) }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: a.simbolo).font(.system(size: 15))
                            Text(AcoesRapidasBackend.titulo(a)).font(.system(size: 9.5))
                                .multilineTextAlignment(.center).lineLimit(2)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(a.descricao)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }
}

// MARK: - Sistema

struct SistemaDaIlha: View {
    @ObservedObject private var m = MonitorModelo.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                medida("CPU", Metricas.porcentagem(m.cpu), "cpu") {
                    GraficoPequeno(historico: m.historicoCPU, teto: 1, cor: .blue)
                }
                medida("Memória", "\(Metricas.bytes(m.memoria, binario: true)) de \(Metricas.bytes(m.memoriaTotal, binario: true))",
                       "memorychip") {
                    GraficoPequeno(historico: m.historicoMemoria, teto: 1, cor: .purple)
                }
                medida("Rede", "↓ \(Metricas.taxa(m.entrada))  ↑ \(Metricas.taxa(m.saida))", "network") {
                    ZStack {
                        GraficoPequeno(historico: m.historicoEntrada, teto: nil, cor: .green)
                        GraficoPequeno(historico: m.historicoSaida, teto: nil, cor: .orange)
                    }
                }
            }
            .frame(height: 92)
            HStack(spacing: 8) {
                if let b = m.bateria {
                    barra(b.carregando ? "Carregando" : (b.naTomada ? "Na tomada" : "Bateria"),
                          Metricas.porcentagem(b.fracao) + (Metricas.tempo(minutos: b.minutos).map { " · \($0)" } ?? ""),
                          b.carregando ? "battery.100.bolt" : "battery.75", b.fracao, .green)
                }
                if let d = m.disco, d.total > 0 {
                    barra("Disco", "\(Metricas.bytes(d.livre)) livres", "internaldrive",
                          1 - Double(d.livre) / Double(d.total), .blue)
                }
                if m.termico.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    Label(m.termico == .critical ? "Muito quente" : "Esquentando", systemImage: "thermometer.high")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                }
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 16).padding(.top, 8)
        .onAppear { m.interesse("ilha", true) }
        .onDisappear { m.interesse("ilha", false) }
    }

    private func medida<G: View>(_ titulo: String, _ valor: String, _ simbolo: String,
                                 @ViewBuilder grafico: () -> G) -> some View {
        CartaoDaIlha {
            VStack(alignment: .leading, spacing: 4) {
                Label(titulo, systemImage: simbolo).font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(valor).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                grafico()
            }
        }
    }

    private func barra(_ titulo: String, _ valor: String, _ simbolo: String, _ fracao: Double, _ cor: Color) -> some View {
        CartaoDaIlha {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(titulo, systemImage: simbolo).font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(valor).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(cor).frame(width: g.size.width * min(1, max(0, fracao)))
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

// MARK: - Arquivos (a prateleira dentro da ilha)

struct ArquivosDaIlhaView: View {
    let alvo: Bool
    @ObservedObject private var prateleira = PrateleiraModelo.shared
    @ObservedObject private var modelo = ArquivosDaIlhaModelo.shared

    private var arquivos: [URL] {
        prateleira.itens.filter { $0.tipo == .arquivo }.map { URL(fileURLWithPath: $0.valor) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if prateleira.itens.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22))
                    Text("Solte arquivos, links ou texto aqui").font(.system(size: 12, weight: .medium))
                    Text("Ficam guardados na ilha até você levar para outro lugar")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(alvo ? Color.orange : Color.white.opacity(0.25)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(prateleira.itens) { item in bloco(item) }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(alvo ? Color.orange : Color.clear, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 6) {
                    levarTudo
                    BotaoPilula(titulo: "AirDrop", simbolo: "dot.radiowaves.left.and.right") {
                        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: arquivos)
                    }
                    .disabled(arquivos.isEmpty)
                    BotaoPilula(titulo: "Compactar", simbolo: "doc.zipper") { compactar() }
                        .disabled(arquivos.isEmpty)
                    BotaoPilula(titulo: "Esvaziar", simbolo: "trash") { prateleira.esvaziar() }
                }
                .frame(width: 112, alignment: .leading)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .onAppear { prateleira.limparSumidos() }
    }

    private var levarTudo: some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.draw").font(.system(size: 10, weight: .semibold))
            Text("Levar tudo").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.orange))
        .overlay(ArrastoDeSaida(itens: Prateleira.paraLevarTudo(prateleira.itens), estado: modelo.estadoDeArrasto))
        .help("Arraste para levar todos os arquivos de uma vez")
    }

    private func bloco(_ item: ItemDaPrateleira) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let i = PrateleiraModelo.icone(item) { Image(nsImage: i).resizable().aspectRatio(contentMode: .fit) }
                    else { Image(systemName: item.tipo == .link ? "link" : "text.alignleft").font(.system(size: 24)) }
                }
                .frame(width: 48, height: 48)
                .frame(width: 80, height: 54)
                .overlay(ArrastoDeSaida(itens: [item], estado: modelo.estadoDeArrasto,
                                        aoClicar: { PrateleiraModelo.abrir(item) }))
                Button { prateleira.remover(item.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(Circle().fill(Color.white.opacity(0.25)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tirar da ilha")
            }
            Text(nome(item)).font(.system(size: 10)).lineLimit(1).truncationMode(.middle).foregroundStyle(.white)
        }
        .frame(width: 88)
    }

    private func nome(_ item: ItemDaPrateleira) -> String {
        item.tipo == .arquivo ? (item.valor as NSString).lastPathComponent : item.valor
    }

    /// Compacta os arquivos num .zip ao lado do primeiro, como o "Comprimir"
    /// do Finder, e põe o resultado na ilha.
    private func compactar() {
        let urls = arquivos
        guard let primeiro = urls.first else { return }
        let pasta = primeiro.deletingLastPathComponent()
        let nome = urls.count == 1 ? primeiro.deletingPathExtension().lastPathComponent : "Arquivos"
        var destino = pasta.appendingPathComponent("\(nome).zip")
        var n = 2
        while FileManager.default.fileExists(atPath: destino.path) {
            destino = pasta.appendingPathComponent("\(nome) \(n).zip"); n += 1
        }
        let saida = destino
        DispatchQueue.global(qos: .userInitiated).async {
            // ditto, e não zip: guarda os atributos do macOS como o Finder guarda
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for u in urls { try? FileManager.default.copyItem(at: u, to: temp.appendingPathComponent(u.lastPathComponent)) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = urls.count == 1 ? ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, saida.path]
                                          : ["-c", "-k", "--sequesterRsrc", temp.path, saida.path]
            try? p.run()
            p.waitUntilExit()
            try? FileManager.default.removeItem(at: temp)
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: saida.path) {
                    PrateleiraModelo.shared.adicionar([ItemDaPrateleira(tipo: .arquivo, valor: saida.path)])
                }
            }
        }
    }
}

// MARK: - Rascunho

struct RascunhoDaIlha: View {
    @ObservedObject private var notas = NotasModelo.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(notas.notas) { n in
                    Button { notas.selecionar(n.id) } label: {
                        Text(n.titulo.isEmpty ? "Nota" : n.titulo)
                            .font(.system(size: 11, weight: n.id == notas.selecionada ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(n.id == notas.selecionada ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(n.id == notas.selecionada ? 0.14 : 0)))
                            .frame(maxWidth: 140)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    if n.id == notas.selecionada && notas.notas.count > 1 {
                        Button { notas.fechar(n.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 16, height: 16).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fechar a nota")
                    }
                }
                if notas.podeCriar {
                    Button { notas.nova() } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Nova nota")
                }
                Spacer()
            }
            TextEditor(text: Binding(get: { notas.texto }, set: { notas.texto = $0 }))
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 14)
    }
}

// MARK: - Capturas recentes e Downloads

struct CapturasDaIlha: View {
    let agora: Date
    @ObservedObject private var modelo = ArquivosDaIlhaModelo.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((modelo.pastaDeCapturas as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                Spacer()
                BotaoPilula(titulo: "Abrir pasta", simbolo: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: modelo.pastaDeCapturas))
                }
            }
            if modelo.capturas.isEmpty {
                Text("Nenhuma captura recente por aqui").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    ForEach(modelo.capturas, id: \.caminho) { BlocoDeArquivo(arquivo: $0, agora: agora) }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 6)
        .onAppear { modelo.atualizarCapturas() }
    }
}

struct DownloadsDaIlha: View {
    let agora: Date
    @ObservedObject private var modelo = ArquivosDaIlhaModelo.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(modelo.emAndamento.prefix(2)) { d in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
                    Text(d.nome).font(.system(size: 11)).lineLimit(1).truncationMode(.middle).foregroundStyle(.white)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(Color.blue).frame(width: g.size.width * d.fracao)
                        }
                    }
                    .frame(height: 4)
                    Text(ArquivosDaIlha.porcentagem(d.fracao)).font(.system(size: 11, weight: .semibold))
                        .monospacedDigit().foregroundStyle(.white).frame(width: 40, alignment: .trailing)
                }
            }
            HStack {
                Text("Recentes").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                BotaoPilula(titulo: "Abrir Downloads", simbolo: "folder") {
                    NSWorkspace.shared.open(ArquivosDaIlhaModelo.pastaDeDownloads)
                }
            }
            // o que ainda está chegando já aparece em cima, com a barra
            let recentes = modelo.downloads.filter { d in !modelo.emAndamento.contains { $0.id == d.caminho } }
            if recentes.isEmpty {
                Text("Nada baixado por aqui").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    ForEach(recentes, id: \.caminho) { BlocoDeArquivo(arquivo: $0, agora: agora) }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 6)
        .onAppear { modelo.atualizarDownloads() }
    }
}
