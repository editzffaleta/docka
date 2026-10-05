import AppKit
import DockaCore

// MARK: - Utilidades

/// Roda um programa fora da main thread e devolve a saída (stdout + stderr).
enum Comando {
    /// Com `soSaida`, os avisos (stderr) ficam de fora — para comandos que
    /// devolvem JSON, onde um "Warning:" no meio estragaria a leitura.
    static func rodar(_ executavel: String, _ argumentos: [String], ambiente: [String: String] = [:],
                      soSaida: Bool = false) async -> (saida: String, codigo: Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executavel)
                p.arguments = argumentos
                var env = ProcessInfo.processInfo.environment
                env.merge(ambiente) { _, novo in novo }
                p.environment = env
                let cano = Pipe()
                p.standardOutput = cano
                p.standardError = soSaida ? FileHandle.nullDevice : cano
                p.standardInput = FileHandle.nullDevice
                do {
                    try p.run()
                    let dados = cano.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    cont.resume(returning: (String(decoding: dados, as: UTF8.self), p.terminationStatus))
                } catch {
                    cont.resume(returning: (error.localizedDescription, -1))
                }
            }
        }
    }
}

enum Arquivos {
    /// O espaço que a pasta (ou o arquivo) ocupa no disco.
    static func tamanho(_ url: URL) -> Int64 {
        let chaves: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let v = try? url.resourceValues(forKeys: chaves) else { return 0 }
        guard v.isDirectory == true else { return Int64(v.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(chaves), options: [],
                                               errorHandler: { _, _ in true })
        while let f = e?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static func conteudo(_ pasta: String) -> [URL] {
        let url = URL(fileURLWithPath: (pasta as NSString).expandingTildeInPath)
        return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
    }

    /// Para o Lixo — nunca apagado de vez. O que o Docka não pode mover (um
    /// app instalado pelo administrador) vai pelo Finder, que pede a senha.
    @discardableResult
    static func paraOLixo(_ urls: [URL]) -> [URL] {
        var falhas: [URL] = []
        for u in urls {
            do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) } catch { falhas.append(u) }
        }
        guard !falhas.isEmpty else { return [] }
        let lista = falhas.map { "POSIX file \"\($0.path.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ")
        var erro: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to delete {\(lista)}")?.executeAndReturnError(&erro)
        return falhas.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Lê o Info.plist de um app.
    static func info(_ app: URL) -> [String: Any] {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
    }

    static func apps() -> [URL] {
        ["/Applications", "/Applications/Utilities", "~/Applications"].flatMap(conteudo)
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func nome(_ app: URL) -> String {
        var n = FileManager.default.displayName(atPath: app.path)
        if n.hasSuffix(".app") { n.removeLast(4) }
        return n
    }
}

/// Uma linha que pode ser marcada para ir ao Lixo.
struct ItemParaLimpar: Identifiable {
    let id = UUID()
    let url: URL
    let titulo: String
    let detalhe: String
    var tamanho: Int64
    var marcado: Bool
}

// MARK: - Atualizações

final class AtualizacoesModelo: ObservableObject {
    struct Atualizacao: Identifiable {
        let id = UUID()
        let nome: String
        let app: URL?
        let atual: String
        let nova: String
        enum Origem { case desenvolvedor, appStore(URL?), homebrew(String) }
        let origem: Origem
    }

    @Published var resultados: [Atualizacao] = []
    @Published var procurando = false
    @Published var estado = ""

    private static let sessao: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.httpAdditionalHeaders = ["User-Agent": "Docka"]
        return URLSession(configuration: c)
    }()

    /// Pergunta ao feed de cada app (o do próprio desenvolvedor, declarado no
    /// app), à App Store pelos da loja e ao Homebrew pelos casks — só agora,
    /// porque você pediu.
    func procurar() {
        guard !procurando else { return }
        procurando = true
        resultados = []
        estado = "Procurando…"
        let sistema = ProcessInfo.processInfo.operatingSystemVersion
        let versaoDoSistema = "\(sistema.majorVersion).\(sistema.minorVersion).\(sistema.patchVersion)"
        Task { @MainActor in
            let apps = Arquivos.apps()
            var achados: [Atualizacao] = []
            await withTaskGroup(of: Atualizacao?.self) { grupo in
                var fila = apps.makeIterator()
                func proximo() {
                    guard let app = fila.next() else { return }
                    grupo.addTask { await Self.conferir(app, sistema: versaoDoSistema) }
                }
                for _ in 0..<6 { proximo() }
                for await r in grupo {
                    if let r { achados.append(r) }
                    proximo()
                }
            }
            let doBrew = await Self.homebrew()
            // o app que também é um cask aparece uma vez só, pelo Homebrew
            // (que atualiza direto)
            let casks = Set(doBrew.compactMap { a -> String? in
                if case .homebrew(let alvo) = a.origem, alvo.hasPrefix("--cask ") { return a.nome.lowercased() }
                return nil
            })
            achados.removeAll { casks.contains($0.nome.lowercased().replacingOccurrences(of: " ", with: "-")) }
            resultados = (achados + doBrew).sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
            estado = resultados.isEmpty ? "Tudo em dia (\(apps.count) apps conferidos)."
                : "\(achados.count) de \(apps.count) apps e \(doBrew.count) pacotes do Homebrew com versão nova."
            procurando = false
        }
    }

    private static func conferir(_ app: URL, sistema: String) async -> Atualizacao? {
        let info = Arquivos.info(app)
        let curta = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? curta
        let nome = Arquivos.nome(app)
        if let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)), feed.scheme == "https" {
            guard let (dados, _) = try? await sessao.data(from: feed), dados.count < 4_000_000,
                  let melhor = Manutencao.melhor(Manutencao.lerFeed(dados), sistema: sistema),
                  Manutencao.maisNova(melhor.versao, que: build) else { return nil }
            return Atualizacao(nome: nome, app: app, atual: curta, nova: melhor.versaoCurta ?? melhor.versao, origem: .desenvolvedor)
        }
        let recibo = app.appendingPathComponent("Contents/_MASReceipt/receipt")
        if FileManager.default.fileExists(atPath: recibo.path), let id = info["CFBundleIdentifier"] as? String,
           let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)") {
            guard let (dados, _) = try? await sessao.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
                  let r = (json["results"] as? [[String: Any]])?.first,
                  let nova = r["version"] as? String, Manutencao.maisNova(nova, que: curta) else { return nil }
            let loja = (r["trackViewUrl"] as? String).flatMap(URL.init(string:))
            return Atualizacao(nome: nome, app: app, atual: curta, nova: nova, origem: .appStore(loja))
        }
        return nil
    }

    static var brew: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func homebrew() async -> [Atualizacao] {
        guard let brew else { return [] }
        let (saida, codigo) = await Comando.rodar(brew, ["outdated", "--json=v2", "--greedy"],
                                                  ambiente: ["HOMEBREW_NO_AUTO_UPDATE": "1"], soSaida: true)
        guard codigo == 0, let json = try? JSONSerialization.jsonObject(with: Data(saida.utf8)) as? [String: Any] else { return [] }
        func itens(_ chave: String, cask: Bool) -> [Atualizacao] {
            (json[chave] as? [[String: Any]] ?? []).compactMap { i in
                guard let nome = i["name"] as? String, let nova = i["current_version"] as? String else { return nil }
                let atual = (i["installed_versions"] as? [String])?.last ?? "?"
                return Atualizacao(nome: nome, app: nil, atual: atual, nova: nova,
                                   origem: .homebrew(cask ? "--cask \(nome)" : nome))
            }
        }
        return itens("casks", cask: true) + itens("formulae", cask: false)
    }

    func atualizarPeloBrew(_ alvos: [String], log: HomebrewModelo) {
        guard Self.brew != nil, !alvos.isEmpty else { return }
        log.executar(["upgrade"] + alvos.flatMap { $0.split(separator: " ").map(String.init) }) { [weak self] in
            self?.resultados.removeAll { if case .homebrew = $0.origem { return true }; return false }
        }
    }
}

// MARK: - Limpeza

final class LimpezaModelo: ObservableObject {
    enum Grupo: String, CaseIterable, Identifiable {
        case caches, registros, restos
        var id: String { rawValue }
        var titulo: String {
            switch self {
            case .caches:    return "Caches"
            case .registros: return "Registros"
            case .restos:    return "Restos de apps removidos"
            }
        }
    }

    @Published var itens: [Grupo: [ItemParaLimpar]] = [:]
    @Published var analisando = false
    @Published var estado = ""

    var marcados: [ItemParaLimpar] { itens.values.flatMap { $0.filter(\.marcado) } }

    func analisar() {
        guard !analisando else { return }
        analisando = true
        estado = "Medindo…"
        let abertos = NSWorkspace.shared.runningApplications
        let rodando = Set(abertos.compactMap { $0.bundleIdentifier?.lowercased() })
        // o primeiro nome de cada app aberto: pastas de fabricante como
        // "BraveSoftware" (Brave) e "Google" (Google Chrome) também são dele
        let nomes = Set(abertos.compactMap { $0.localizedName?.split(separator: " ").first.map { $0.lowercased() } }
            .filter { $0.count >= 4 })
        Task.detached(priority: .userInitiated) {
            func lista(_ pasta: String, marcar: (URL) -> Bool) -> [ItemParaLimpar] {
                Arquivos.conteudo(pasta).map { u in
                    ItemParaLimpar(url: u, titulo: u.lastPathComponent, detalhe: (pasta as NSString).lastPathComponent,
                                   tamanho: Arquivos.tamanho(u), marcado: marcar(u))
                }
                .filter { $0.tamanho > 0 }
                .sorted { $0.tamanho > $1.tamanho }
            }
            // desmarcados: o cache de um app aberto (ele está usando) e os do
            // macOS (serviços rodando que nem aparecem como app)
            let caches = lista("~/Library/Caches") { u in
                let nome = u.lastPathComponent.lowercased()
                return !rodando.contains(nome) && !nome.hasPrefix("com.apple.") && !nomes.contains { nome.hasPrefix($0) }
            }
            let registros = lista("~/Library/Logs") { _ in true }
            // os identificadores dos apps instalados: o que começa com um deles
            // (um auxiliar, "id.ShipIt") é do app, não resto
            let instalados = Set(Arquivos.apps().compactMap { (Arquivos.info($0)["CFBundleIdentifier"] as? String)?.lowercased() })
                .union(rodando)
            var restos: [ItemParaLimpar] = []
            for pasta in ["~/Library/Application Support", "~/Library/Preferences", "~/Library/Saved Application State",
                          "~/Library/Caches", "~/Library/HTTPStorages", "~/Library/WebKit"] {
                for u in Arquivos.conteudo(pasta) {
                    var id = u.lastPathComponent
                    for ext in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(ext) { id.removeLast(ext.count) }
                    // só o que tem cara de identificador de app, e de app que não existe mais
                    let minusculo = id.lowercased()
                    guard id.split(separator: ".").count >= 3, !id.contains(" "), !Manutencao.protegido(id),
                          !instalados.contains(where: { Manutencao.mesmoFabricante(minusculo, $0) }),
                          NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil else { continue }
                    let t = Arquivos.tamanho(u)
                    guard t > 0 else { continue }
                    restos.append(ItemParaLimpar(url: u, titulo: u.lastPathComponent,
                                                 detalhe: (pasta as NSString).lastPathComponent, tamanho: t, marcado: false))
                }
            }
            restos.sort { $0.tamanho > $1.tamanho }
            await MainActor.run { [restos] in
                self.itens = [.caches: caches, .registros: registros, .restos: restos]
                self.analisando = false
                self.estado = "Marcados: \(Manutencao.tamanho(self.marcados.reduce(0) { $0 + $1.tamanho }))"
            }
        }
    }

    func alternar(_ grupo: Grupo, _ id: UUID) {
        guard let i = itens[grupo]?.firstIndex(where: { $0.id == id }) else { return }
        itens[grupo]?[i].marcado.toggle()
        estado = "Marcados: \(Manutencao.tamanho(marcados.reduce(0) { $0 + $1.tamanho }))"
    }

    func limpar() {
        let alvo = marcados
        let total = alvo.reduce(0) { $0 + $1.tamanho }
        let falhas = Arquivos.paraOLixo(alvo.map(\.url))
        estado = falhas.isEmpty ? "\(Manutencao.tamanho(total)) foram para o Lixo."
                                : "Foram para o Lixo; \(falhas.count) não puderam (em uso ou protegidos)."
        analisar()
    }
}

// MARK: - Downloads dos mensageiros

final class MensageirosModelo: ObservableObject {
    struct Fonte: Identifiable {
        var id: String { nome }
        let nome: String
        let pasta: String
    }

    static let conhecidas: [Fonte] = [
        Fonte(nome: "WhatsApp", pasta: "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media"),
        Fonte(nome: "Telegram", pasta: "~/Downloads/Telegram Desktop"),
        Fonte(nome: "Telegram (app da loja)", pasta: "~/Downloads/Telegram"),
    ]

    @Published var dias = 30
    @Published var achados: [ItemParaLimpar] = []
    /// Pastas que existem mas o macOS não deixa ler (dados de outro app).
    @Published var semAcesso: [String] = []
    @Published var estado = ""
    @Published var analisando = false

    var fontes: [Fonte] {
        Self.conhecidas + DockaStore.shared.pastasDeMensageiros.map { Fonte(nome: ($0 as NSString).lastPathComponent, pasta: $0) }
    }

    func analisar() {
        guard !analisando else { return }
        analisando = true
        let fontes = self.fontes, dias = self.dias
        Task.detached(priority: .userInitiated) {
            var lista: [ItemParaLimpar] = []
            var existentes = 0
            var bloqueadas: [String] = []
            for f in fontes {
                let raiz = URL(fileURLWithPath: (f.pasta as NSString).expandingTildeInPath)
                guard FileManager.default.fileExists(atPath: raiz.path) else { continue }
                existentes += 1
                // existe mas não abre: o macOS protege os dados de outros apps
                guard (try? FileManager.default.contentsOfDirectory(atPath: raiz.path)) != nil else {
                    bloqueadas.append(f.nome)
                    continue
                }
                let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
                                                       options: [.skipsHiddenFiles])
                var arquivos: [(caminho: String, data: Date)] = []
                while let u = e?.nextObject() as? URL {
                    let v = try? u.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
                    guard v?.isRegularFile == true else { continue }
                    arquivos.append((u.path, v?.creationDate ?? .distantPast))
                }
                for c in Manutencao.paraLimpar(arquivos, dias: dias, agora: Date()) {
                    let u = URL(fileURLWithPath: c)
                    lista.append(ItemParaLimpar(url: u, titulo: u.lastPathComponent, detalhe: f.nome,
                                                tamanho: Arquivos.tamanho(u), marcado: true))
                }
            }
            lista.sort { $0.tamanho > $1.tamanho }
            await MainActor.run { [lista, existentes, bloqueadas] in
                self.achados = lista
                self.semAcesso = bloqueadas
                self.analisando = false
                self.estado = existentes == 0 ? "Nenhuma pasta de mensageiro encontrada neste Mac."
                    : "\(lista.count) arquivos com mais de \(dias) dias — \(Manutencao.tamanho(lista.reduce(0) { $0 + $1.tamanho }))."
            }
        }
    }

    func alternar(_ id: UUID) {
        if let i = achados.firstIndex(where: { $0.id == id }) { achados[i].marcado.toggle() }
    }

    func paraOLixo() {
        let falhas = Arquivos.paraOLixo(achados.filter(\.marcado).map(\.url))
        estado = falhas.isEmpty ? "Foram para o Lixo." : "\(falhas.count) não puderam ir para o Lixo."
        analisar()
    }

    /// Junta numa pasta só, por mensageiro e mês: ~/Downloads/Mensageiros/WhatsApp/2026-09.
    func organizar() {
        let fm = FileManager.default
        let mes = DateFormatter()
        mes.dateFormat = "yyyy-MM"
        var movidos = 0
        for i in achados where i.marcado {
            let data = (try? i.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            let destino = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Downloads/Mensageiros/\(i.detalhe)/\(mes.string(from: data))")
            try? fm.createDirectory(at: destino, withIntermediateDirectories: true)
            var alvo = destino.appendingPathComponent(i.url.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: alvo.path) {
                alvo = destino.appendingPathComponent("\(i.url.deletingPathExtension().lastPathComponent) \(n).\(i.url.pathExtension)")
                n += 1
            }
            if (try? fm.moveItem(at: i.url, to: alvo)) != nil { movidos += 1 }
        }
        estado = "\(movidos) arquivos organizados em Downloads › Mensageiros."
        analisar()
    }
}

// MARK: - Desinstalador

final class DesinstaladorModelo: ObservableObject {
    @Published var app: URL?
    @Published var itens: [ItemParaLimpar] = []
    @Published var estado = ""
    @Published var procurando = false

    static let pastas = ["Application Support", "Caches", "Preferences", "Preferences/ByHost", "Saved Application State",
                         "Containers", "Group Containers", "HTTPStorages", "WebKit", "Logs", "LaunchAgents", "Cookies",
                         "Application Scripts"]

    func escolher(_ app: URL) {
        self.app = app
        itens = []
        let info = Arquivos.info(app)
        let bundle = info["CFBundleIdentifier"] as? String ?? ""
        let nome = Arquivos.nome(app)
        guard !app.path.hasPrefix("/System/"), !Manutencao.protegido(bundle) else {
            estado = "\(nome) faz parte do macOS (ou é o próprio Docka) e não é removido por aqui."
            return
        }
        procurando = true
        estado = "Procurando os arquivos de \(nome)…"
        Task.detached(priority: .userInitiated) {
            var lista = [ItemParaLimpar(url: app, titulo: app.lastPathComponent, detalhe: "o app",
                                        tamanho: Arquivos.tamanho(app), marcado: true)]
            for pasta in Self.pastas {
                for u in Arquivos.conteudo("~/Library/\(pasta)") where Manutencao.pertence(u.lastPathComponent, bundle: bundle, nome: nome) {
                    lista.append(ItemParaLimpar(url: u, titulo: u.lastPathComponent, detalhe: pasta,
                                                tamanho: Arquivos.tamanho(u), marcado: true))
                }
            }
            await MainActor.run { [lista] in
                self.itens = lista
                self.procurando = false
                self.estado = "\(lista.count) itens — \(Manutencao.tamanho(lista.reduce(0) { $0 + $1.tamanho }))."
            }
        }
    }

    var aberto: NSRunningApplication? {
        guard let app else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == app.standardizedFileURL }
    }

    func alternar(_ id: UUID) {
        if let i = itens.firstIndex(where: { $0.id == id }) { itens[i].marcado.toggle() }
    }

    func desinstalar() {
        guard aberto == nil else { estado = "Feche o app antes."; return }
        let falhas = Arquivos.paraOLixo(itens.filter(\.marcado).map(\.url))
        estado = falhas.isEmpty ? "Foi tudo para o Lixo — dá para recuperar de lá."
                                : "\(falhas.count) itens não puderam ir para o Lixo."
        itens = itens.filter { falhas.contains($0.url) }
        if falhas.isEmpty { app = nil }
    }
}

// MARK: - Homebrew

final class HomebrewModelo: ObservableObject {
    struct Pacote: Identifiable, Hashable {
        var id: String { (cask ? "cask:" : "") + nome }
        let nome: String
        let versao: String
        let descricao: String
        let cask: Bool
    }

    @Published var instalados: [Pacote] = []
    @Published var busca = ""
    @Published var encontrados: (formulas: [String], casks: [String]) = ([], [])
    @Published var registro = ""
    @Published var trabalhando = false

    var disponivel: Bool { AtualizacoesModelo.brew != nil }
    private let ambiente = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_NO_COLOR": "1"]

    func carregar() {
        guard let brew = AtualizacoesModelo.brew else { return }
        Task { @MainActor in
            let (saida, codigo) = await Comando.rodar(brew, ["info", "--json=v2", "--installed"], ambiente: ambiente, soSaida: true)
            guard codigo == 0, let json = try? JSONSerialization.jsonObject(with: Data(saida.utf8)) as? [String: Any] else { return }
            let formulas = (json["formulae"] as? [[String: Any]] ?? []).compactMap { f -> Pacote? in
                guard let nome = f["name"] as? String else { return nil }
                let v = ((f["installed"] as? [[String: Any]])?.last?["version"] as? String) ?? ""
                return Pacote(nome: nome, versao: v, descricao: f["desc"] as? String ?? "", cask: false)
            }
            let casks = (json["casks"] as? [[String: Any]] ?? []).compactMap { c -> Pacote? in
                guard let nome = c["token"] as? String else { return nil }
                return Pacote(nome: nome, versao: c["installed"] as? String ?? "", descricao: c["desc"] as? String ?? "", cask: true)
            }
            instalados = (casks + formulas)
        }
    }

    func buscar() {
        guard let brew = AtualizacoesModelo.brew, !busca.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let termo = busca.trimmingCharacters(in: .whitespaces)
        Task { @MainActor in
            let (saida, _) = await Comando.rodar(brew, ["search", termo], ambiente: ambiente)
            encontrados = Manutencao.lerBuscaDoBrew(saida)
        }
    }

    /// Um comando do brew, com a saída aparecendo no registro.
    func executar(_ argumentos: [String], depois: (() -> Void)? = nil) {
        guard let brew = AtualizacoesModelo.brew, !trabalhando else { return }
        trabalhando = true
        registro = "$ brew \(argumentos.joined(separator: " "))\n"
        Task { @MainActor in
            let (saida, codigo) = await Comando.rodar(brew, argumentos, ambiente: ambiente)
            registro += saida + (codigo == 0 ? "\n✓ Pronto." : "\n✗ Terminou com erro (\(codigo)).")
            trabalhando = false
            carregar()
            depois?()
        }
    }

    func instalar(_ nome: String, cask: Bool) { executar(["install"] + (cask ? ["--cask"] : []) + [nome]) }
    func remover(_ p: Pacote) { executar(["uninstall"] + (p.cask ? ["--cask"] : []) + [p.nome]) }
}

// MARK: - Portas

final class PortasModelo: ObservableObject {
    @Published var portas: [Manutencao.Porta] = []
    @Published var estado = ""

    func atualizar() {
        Task { @MainActor in
            let (saida, _) = await Comando.rodar("/usr/sbin/lsof", ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP"], soSaida: true)
            portas = Manutencao.lerPortas(saida)
            let expostas = portas.filter(\.exposta).count
            estado = "\(portas.count) portas abertas pelos seus apps; \(expostas) aceitam conexões de fora do Mac."
        }
    }

    /// Pede para o processo terminar (como o Monitor de Atividade, sem forçar).
    func encerrar(_ p: Manutencao.Porta) {
        let alerta = NSAlert()
        alerta.messageText = "Encerrar \(p.processo)?"
        alerta.informativeText = "O processo \(p.pid) recebe o pedido para fechar. Trabalho não salvo nele pode se perder."
        alerta.addButton(withTitle: "Encerrar")
        alerta.addButton(withTitle: "Cancelar")
        guard alerta.runModal() == .alertFirstButtonReturn else { return }
        kill(p.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.atualizar() }
    }
}
