import Foundation

/// As decisões da manutenção — versões, feeds, portas, restos de apps e
/// downloads velhos — sem tocar no disco nem na rede.
public enum Manutencao {

    // MARK: versões

    /// "1.10" > "1.9"; "2.0" == "2"; letras e sufixos ("1.2b3", "1.2 (45)")
    /// contam pelos números que têm.
    public static func comparar(_ a: String, _ b: String) -> ComparisonResult {
        func partes(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let x = partes(a), y = partes(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    public static func maisNova(_ disponivel: String, que instalada: String) -> Bool {
        comparar(disponivel, instalada) == .orderedDescending
    }

    // MARK: feed do Sparkle

    public struct ItemDoFeed: Equatable, Sendable {
        public let versao: String
        public let versaoCurta: String?
        public let minimoDoSistema: String?
    }

    /// Os itens de um appcast do Sparkle: a versão vem em `sparkle:version`
    /// (no enclosure ou como elemento) e a mostrada em `sparkle:shortVersionString`.
    public static func lerFeed(_ dados: Data) -> [ItemDoFeed] {
        final class Leitor: NSObject, XMLParserDelegate {
            var itens: [ItemDoFeed] = []
            var dentro = false
            var versao: String?, curta: String?, minimo: String?
            var texto = ""
            func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?,
                        attributes a: [String: String] = [:]) {
                texto = ""
                if e == "item" { dentro = true; versao = nil; curta = nil; minimo = nil }
                guard dentro else { return }
                if e == "enclosure" {
                    versao = versao ?? a["sparkle:version"]
                    curta = curta ?? a["sparkle:shortVersionString"]
                }
            }
            func parser(_ p: XMLParser, foundCharacters s: String) { texto += s }
            func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
                let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
                guard dentro else { return }
                switch e {
                case "sparkle:version": if !t.isEmpty { versao = t }
                case "sparkle:shortVersionString": if !t.isEmpty { curta = t }
                case "sparkle:minimumSystemVersion": if !t.isEmpty { minimo = t }
                case "item":
                    if let v = versao ?? curta { itens.append(ItemDoFeed(versao: v, versaoCurta: curta, minimoDoSistema: minimo)) }
                    dentro = false
                default: break
                }
            }
        }
        let l = Leitor()
        let p = XMLParser(data: dados)
        p.delegate = l
        p.parse()
        return l.itens
    }

    /// A versão mais nova que roda neste sistema.
    public static func melhor(_ itens: [ItemDoFeed], sistema: String) -> ItemDoFeed? {
        itens.filter { i in i.minimoDoSistema.map { comparar($0, sistema) != .orderedDescending } ?? true }
            .max { comparar($0.versao, $1.versao) == .orderedAscending }
    }

    // MARK: portas

    public struct Porta: Equatable, Sendable, Identifiable {
        public let processo: String
        public let pid: Int32
        public let protocolo: String
        public let endereco: String
        public let porta: Int
        public var id: String { "\(pid)-\(protocolo)-\(endereco)-\(porta)" }
        /// Escutando em todas as interfaces (outros na rede alcançam), e não
        /// só no próprio Mac.
        public var exposta: Bool { !["127.0.0.1", "[::1]", "localhost"].contains(endereco) }
    }

    /// Lê a saída de `lsof -nP -iTCP -sTCP:LISTEN -iUDP -FcpPn`… — aqui, a
    /// forma de colunas do `lsof -nP` comum.
    public static func lerPortas(_ saida: String) -> [Porta] {
        var vistas = Set<String>()
        return saida.split(separator: "\n").dropFirst().compactMap { linha in
            let c = linha.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard c.count >= 9, let pid = Int32(c[1]) else { return nil }
            let proto = c[7]
            guard proto == "TCP" || proto == "UDP" else { return nil }
            var nome = c[8]
            if proto == "TCP", !linha.contains("(LISTEN)") { return nil }
            if nome.contains("->") { return nil }   // conexão, não escuta
            nome = nome.replacingOccurrences(of: "*", with: "0.0.0.0")
            guard let dois = nome.lastIndex(of: ":"), let porta = Int(nome[nome.index(after: dois)...]) else { return nil }
            let end = String(nome[..<dois])
            let p = Porta(processo: c[0].replacingOccurrences(of: "\\x20", with: " "), pid: pid,
                          protocolo: proto, endereco: end, porta: porta)
            return vistas.insert(p.id).inserted ? p : nil
        }
        .sorted { $0.porta != $1.porta ? $0.porta < $1.porta : $0.processo < $1.processo }
    }

    // MARK: restos de apps

    /// Um item da Biblioteca pertence ao app? Pelo identificador (exato,
    /// como prefixo "id." ou dentro de um grupo "TEAM.id") ou pelo nome
    /// exato da pasta. Nome curto demais não vale: "Notes" levaria pastas de
    /// outros apps junto.
    public static func pertence(_ item: String, bundle: String, nome: String) -> Bool {
        // sem tirar "extensão": num identificador, ".slackmacgap" não é uma
        let i = item.lowercased(), b = bundle.lowercased()
        if !b.isEmpty {
            // "id", "id.plist", "id.savedState", "id.ShipIt", "TEAM.id", "id_…"
            if i == b || i.hasPrefix(b + ".") || i.hasSuffix("." + b) { return true }
            if i.hasPrefix(b + "_") || i.hasPrefix(b + "-") { return true }
        }
        let n = nome.lowercased()
        return n.count >= 4 && i == n
    }

    /// O mesmo fabricante ("com.docker.install" e "com.docker.docker"): na
    /// dúvida, não é resto — melhor deixar uma pasta que levar a de um app
    /// instalado.
    public static func mesmoFabricante(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased().split(separator: "."), y = b.lowercased().split(separator: ".")
        guard x.count >= 2, y.count >= 2 else { return a.lowercased() == b.lowercased() }
        return x[0] == y[0] && x[1] == y[1]
    }

    /// Identificadores do sistema e do próprio Docka nunca entram nos restos.
    public static func protegido(_ bundle: String) -> Bool {
        let b = bundle.lowercased()
        return b.hasPrefix("com.apple.") || b.hasPrefix("com.editzffaleta.docka") || b.isEmpty
    }

    // MARK: Homebrew

    /// A saída do `brew search`: fórmulas e casks em blocos com título
    /// ("==> Formulae", "==> Casks"); sem títulos (um tipo só), tudo é fórmula.
    public static func lerBuscaDoBrew(_ saida: String) -> (formulas: [String], casks: [String]) {
        var formulas: [String] = [], casks: [String] = []
        var emCasks = false
        for linha in saida.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !linha.isEmpty {
            if linha.hasPrefix("==>") { emCasks = linha.lowercased().contains("cask"); continue }
            for nome in linha.split(separator: " ").map(String.init) where !nome.isEmpty {
                if emCasks { casks.append(nome) } else { formulas.append(nome) }
            }
        }
        return (formulas, casks)
    }

    // MARK: downloads dos mensageiros

    /// Os arquivos mais velhos que `dias` (pela data de chegada).
    public static func paraLimpar(_ arquivos: [(caminho: String, data: Date)], dias: Int, agora: Date) -> [String] {
        let limite = agora.addingTimeInterval(-Double(max(0, dias)) * 86_400)
        return arquivos.filter { $0.data < limite }.map(\.caminho)
    }

    /// "2,4 GB".
    public static func tamanho(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
