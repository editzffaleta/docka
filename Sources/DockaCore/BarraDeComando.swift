import Foundation

/// A barra de comando: um campo só para achar apps, janelas, arquivos, o
/// histórico, snippets, comandos de menu, ações do Docka, emoji e scripts — e
/// para fazer contas e converter unidades.
///
/// Aqui fica só a decisão (o que combina com o que foi digitado e em que
/// ordem); quem lê as fontes e executa é o app.
public enum BarraDeComando {

    public enum Tipo: String, CaseIterable, Sendable {
        case resultado, app, janela, acao, menu, arquivo, historico, snippet, script, emoji

        /// A etiqueta à direita de cada linha.
        public var titulo: String {
            switch self {
            case .resultado: return "Resultado"
            case .app:       return "App"
            case .janela:    return "Janela"
            case .acao:      return "Docka"
            case .menu:      return "Menu"
            case .arquivo:   return "Arquivo"
            case .historico: return "Copiado"
            case .snippet:   return "Snippet"
            case .script:    return "Script"
            case .emoji:     return "Emoji"
            }
        }

        /// Desempate entre pontuações iguais: o que se procura mais vem antes.
        var peso: Int { Self.allCases.firstIndex(of: self) ?? 0 }

        /// Arquivos e copiados são muitos: sem este desconto, qualquer
        /// "fonte.ts" perdido passaria na frente do comando "Mostrar Fontes".
        var ajuste: Int {
            switch self {
            case .app:       return 50
            case .arquivo:   return -250
            case .historico: return -150
            default:                   return 0
            }
        }
    }

    public struct Candidato: Identifiable, Equatable, Sendable {
        public let id: String
        public let tipo: Tipo
        public let titulo: String
        public let detalhe: String
        /// Texto a mais que também vale na busca, sem aparecer (apelidos,
        /// o conteúdo do snippet, o caminho do menu).
        public let palavras: String

        public init(id: String, tipo: Tipo, titulo: String, detalhe: String = "", palavras: String = "") {
            self.id = id; self.tipo = tipo; self.titulo = titulo
            self.detalhe = detalhe; self.palavras = palavras
        }
    }

    /// Sem maiúsculas e sem acento: "Música" acha com "musica".
    public static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    /// Quanto o texto combina com o termo; `nil` é não combina.
    ///
    /// Igual > começo > começo de palavra > iniciais ("vsc" → Visual Studio
    /// Code) > em qualquer lugar > as letras em ordem, com pena pelos saltos.
    public static func pontuar(_ termo: String, _ texto: String) -> Int? {
        let t = normalizar(termo.trimmingCharacters(in: .whitespaces))
        let x = normalizar(texto)
        guard !t.isEmpty, !x.isEmpty else { return nil }
        if x == t { return 1000 }
        if x.hasPrefix(t) { return 900 - min(100, x.count - t.count) }
        let palavras = x.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if palavras.contains(where: { $0.hasPrefix(t) }) { return 700 - min(100, x.count - t.count) }
        if t.count >= 2, String(palavras.compactMap(\.first)).hasPrefix(t) { return 600 }
        if x.contains(t) { return 500 - min(100, x.count - t.count) }
        // as letras em ordem, com saltos
        var saltos = 0
        var i = x.startIndex
        for c in t where c != " " {
            guard let achou = x[i...].firstIndex(of: c) else { return nil }
            saltos += x.distance(from: i, to: achou)
            i = x.index(after: achou)
        }
        return max(1, 300 - saltos * 10)
    }

    /// Os candidatos que combinam, melhores primeiro, com no máximo `porTipo`
    /// de cada tipo — senão cem arquivos afogariam o único app.
    public static func ordenar(_ candidatos: [Candidato], termo: String,
                               porTipo: Int = 6, total: Int = 40) -> [Candidato] {
        let pontuados: [(Candidato, Int)] = candidatos.compactMap { c in
            if c.tipo == .resultado { return (c, 2000) }
            let p = [pontuar(termo, c.titulo), pontuar(termo, c.palavras).map { $0 - 150 }]
                .compactMap { $0 }.max()
            return p.map { (c, $0 + c.tipo.ajuste) }
        }
        var contagem: [Tipo: Int] = [:]
        return pontuados
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.tipo.peso != $1.0.tipo.peso
                                                    ? $0.0.tipo.peso < $1.0.tipo.peso
                                                    : $0.0.titulo.count < $1.0.titulo.count) }
            .filter { c, _ in
                contagem[c.tipo, default: 0] += 1
                return contagem[c.tipo]! <= porTipo
            }
            .prefix(total)
            .map(\.0)
    }

    // MARK: menus

    /// "Arquivo › Exportar › PDF".
    public static func caminhoDoMenu(_ titulos: [String]) -> String {
        titulos.filter { !$0.isEmpty }.joined(separator: " › ")
    }

    /// O atalho de um item de menu, do jeito que a Acessibilidade descreve:
    /// a tecla e uma máscara (1 ⇧, 2 ⌥, 4 ⌃, 8 sem ⌘).
    public static func atalhoDoMenu(tecla: String?, modificadores: Int) -> String? {
        guard let tecla, !tecla.isEmpty else { return nil }
        var s = ""
        if modificadores & 4 != 0 { s += "⌃" }
        if modificadores & 2 != 0 { s += "⌥" }
        if modificadores & 1 != 0 { s += "⇧" }
        if modificadores & 8 == 0 { s += "⌘" }
        return s + tecla.uppercased()
    }

    /// Caminhos que não interessam numa busca de arquivo: dependências de
    /// projeto, pastas ocultas e a Biblioteca.
    public static func arquivoRelevante(_ caminho: String, casa: String) -> Bool {
        let resto = caminho.hasPrefix(casa) ? String(caminho.dropFirst(casa.count)) : caminho
        let ruido = ["/node_modules/", "/Pods/", "/.build/", "/DerivedData/", "/vendor/", "/Library/"]
        if ruido.contains(where: { resto.contains($0) }) { return false }
        return !resto.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    // MARK: scripts

    /// O que mostrar depois de rodar um script: a primeira linha da saída,
    /// curta, ou se terminou bem.
    public static func resumoDoScript(saida: String, codigo: Int32) -> String {
        let linha = saida.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if codigo != 0 { return "Falhou (código \(codigo))" + (linha.map { ": \(corte($0))" } ?? "") }
        return linha.map { corte($0) } ?? "Terminou"
    }

    private static func corte(_ s: String) -> String {
        s.count > 70 ? String(s.prefix(69)) + "…" : s
    }
}

/// Um comando de terminal com nome, para rodar pela barra.
public struct ScriptSalvo: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var nome: String
    public var comando: String

    public init(id: UUID = UUID(), nome: String, comando: String) {
        self.id = id; self.nome = nome; self.comando = comando
    }
}

// MARK: - Contas

/// As contas da barra: "2+2", "15% de 80", "raiz(2)*3", "2^10".
public enum Calculadora {

    public struct Conta: Equatable, Sendable {
        public let valor: Double
        /// Para mostrar: "1.234,5".
        public let texto: String
        /// Para copiar: "1234,5", sem separador de milhar.
        public let copia: String
    }

    /// Só tenta o que parece conta — "2026" sozinho é busca, não resultado.
    public static func avaliar(_ entrada: String) -> Conta? {
        var s = entrada.trimmingCharacters(in: .whitespaces)
        let forcada = s.hasPrefix("=")
        if forcada { s.removeFirst() }
        guard s.contains(where: \.isNumber) || s.lowercased().contains("pi") || s.contains("π") else { return nil }
        let operadores = "+-*/^%×÷x("
        let temOperacao = s.dropFirst().contains(where: { operadores.contains($0) })
            || funcoes.keys.contains { s.lowercased().contains($0 + "(") }
        guard forcada || temOperacao else { return nil }
        var p = Leitor(normalizarNumeros(s))
        guard let v = p.expressao(), p.fim, v.isFinite else { return nil }
        return Conta(valor: v, texto: formatar(v, milhar: true), copia: formatar(v, milhar: false))
    }

    /// "1.234,5" → "1234.5"; "2,5" → "2.5"; "2.5" fica.
    static func normalizarNumeros(_ s: String) -> String {
        let r = s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
        if r.contains(",") {
            return r.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return r
    }

    public static func formatar(_ v: Double, milhar: Bool) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = milhar
        f.maximumFractionDigits = abs(v) >= 1e12 ? 0 : 10
        f.maximumSignificantDigits = 15
        f.usesSignificantDigits = true
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    static let funcoes: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "raiz": { $0.squareRoot() },
        "sin": sin, "sen": sin, "cos": cos, "tan": tan,
        "log": log10, "ln": log, "abs": abs,
        "round": { $0.rounded() }, "arred": { $0.rounded() },
    ]

    /// Descida recursiva: soma > produto > potência > unário > primário.
    struct Leitor {
        let c: [Character]
        var i = 0
        init(_ s: String) { c = Array(s.lowercased().filter { !$0.isWhitespace }) }

        var fim: Bool { i == c.count }
        private var atual: Character? { i < c.count ? c[i] : nil }

        private mutating func pegar(_ ch: Character) -> Bool {
            if atual == ch { i += 1; return true }
            return false
        }

        mutating func expressao() -> Double? {
            guard var v = termo() else { return nil }
            while true {
                if pegar("+") { guard let d = termoComPorcentagem(de: v) else { return nil }; v += d }
                else if pegar("-") { guard let d = termoComPorcentagem(de: v) else { return nil }; v -= d }
                else { return v }
            }
        }

        /// "200 + 10%" é 220: na soma, a porcentagem é do que veio antes.
        private mutating func termoComPorcentagem(de base: Double) -> Double? {
            let inicio = i
            if let n = numero(), pegar("%"), atual == nil || "+-)".contains(atual!) { return base * n / 100 }
            i = inicio
            return termo()
        }

        mutating func termo() -> Double? {
            guard var v = potencia() else { return nil }
            while true {
                if pegar("*") || pegar("x") { guard let d = potencia() else { return nil }; v *= d }
                else if pegar("/") { guard let d = potencia(), d != 0 else { return nil }; v /= d }
                else if atual == "d", i + 1 < c.count, c[i + 1] == "e" {
                    // "15% de 80"
                    i += 2
                    guard let d = potencia() else { return nil }; v *= d
                }
                else { return v }
            }
        }

        mutating func potencia() -> Double? {
            guard let b = unario() else { return nil }
            if pegar("^") { guard let e = potencia() else { return nil }; return pow(b, e) }
            return b
        }

        mutating func unario() -> Double? {
            if pegar("-") { return unario().map { -$0 } }
            if pegar("+") { return unario() }
            guard var v = primario() else { return nil }
            if pegar("%") { v /= 100 }
            return v
        }

        mutating func primario() -> Double? {
            if pegar("(") {
                guard let v = expressao(), pegar(")") else { return nil }
                return v
            }
            if pegar("π") { return .pi }
            if let n = numero() { return n }
            // nome: função ou constante
            let inicio = i
            while let ch = atual, ch.isLetter { i += 1 }
            let nome = String(c[inicio..<i])
            if nome == "pi" { return .pi }
            if nome == "e" { return M_E }
            if let f = funcoes[nome], pegar("(") {
                guard let v = expressao(), pegar(")") else { return nil }
                return f(v)
            }
            i = inicio
            return nil
        }

        mutating func numero() -> Double? {
            let inicio = i
            while let ch = atual, ch.isNumber || ch == "." { i += 1 }
            guard i > inicio, let v = Double(String(c[inicio..<i])) else { i = inicio; return nil }
            return v
        }
    }
}

// MARK: - Conversões

/// "10 km em mi", "100 f para c", "2 gb em mb", "90 min em h".
public enum Conversao {

    public struct Resultado: Equatable, Sendable {
        public let texto: String
        public let copia: String
    }

    private struct Unidade {
        let categoria: String
        let unidade: Dimension
        let simbolo: String
    }

    private static let tabela: [String: Unidade] = {
        var t: [String: Unidade] = [:]
        func add(_ cat: String, _ u: Dimension, _ simbolo: String, _ nomes: [String]) {
            for n in nomes { t[n] = Unidade(categoria: cat, unidade: u, simbolo: simbolo) }
        }
        add("comprimento", UnitLength.kilometers, "km", ["km", "quilometro", "quilometros", "kilometer", "kilometers"])
        add("comprimento", UnitLength.meters, "m", ["m", "metro", "metros", "meter", "meters"])
        add("comprimento", UnitLength.centimeters, "cm", ["cm", "centimetro", "centimetros"])
        add("comprimento", UnitLength.millimeters, "mm", ["mm", "milimetro", "milimetros"])
        add("comprimento", UnitLength.miles, "mi", ["mi", "milha", "milhas", "mile", "miles"])
        add("comprimento", UnitLength.feet, "pés", ["ft", "pe", "pes", "foot", "feet"])
        add("comprimento", UnitLength.inches, "pol", ["in", "pol", "polegada", "polegadas", "inch", "inches"])
        add("comprimento", UnitLength.yards, "jd", ["yd", "jarda", "jardas", "yard", "yards"])
        add("massa", UnitMass.kilograms, "kg", ["kg", "quilo", "quilos", "quilograma", "quilogramas"])
        add("massa", UnitMass.grams, "g", ["g", "grama", "gramas", "gram", "grams"])
        add("massa", UnitMass.milligrams, "mg", ["mg", "miligrama", "miligramas"])
        add("massa", UnitMass.metricTons, "t", ["t", "ton", "tonelada", "toneladas"])
        add("massa", UnitMass.pounds, "lb", ["lb", "lbs", "libra", "libras", "pound", "pounds"])
        add("massa", UnitMass.ounces, "oz", ["oz", "onca", "oncas", "ounce", "ounces"])
        add("temperatura", UnitTemperature.celsius, "°C", ["c", "°c", "celsius"])
        add("temperatura", UnitTemperature.fahrenheit, "°F", ["f", "°f", "fahrenheit"])
        add("temperatura", UnitTemperature.kelvin, "K", ["k", "kelvin"])
        add("volume", UnitVolume.liters, "L", ["l", "litro", "litros", "liter", "liters"])
        add("volume", UnitVolume.milliliters, "mL", ["ml", "mililitro", "mililitros"])
        add("volume", UnitVolume.gallons, "gal", ["gal", "galao", "galoes", "gallon", "gallons"])
        add("volume", UnitVolume.cubicMeters, "m³", ["m3", "m³"])
        add("volume", UnitVolume.fluidOunces, "fl oz", ["floz"])
        add("velocidade", UnitSpeed.kilometersPerHour, "km/h", ["km/h", "kmh", "kph"])
        add("velocidade", UnitSpeed.milesPerHour, "mph", ["mph", "mi/h"])
        add("velocidade", UnitSpeed.metersPerSecond, "m/s", ["m/s", "mps"])
        add("velocidade", UnitSpeed.knots, "nós", ["kn", "no", "nos", "knot", "knots"])
        add("dados", UnitInformationStorage.bytes, "B", ["b", "byte", "bytes"])
        add("dados", UnitInformationStorage.kilobytes, "KB", ["kb"])
        add("dados", UnitInformationStorage.megabytes, "MB", ["mb"])
        add("dados", UnitInformationStorage.gigabytes, "GB", ["gb"])
        add("dados", UnitInformationStorage.terabytes, "TB", ["tb"])
        add("dados", UnitInformationStorage.kibibytes, "KiB", ["kib"])
        add("dados", UnitInformationStorage.mebibytes, "MiB", ["mib"])
        add("dados", UnitInformationStorage.gibibytes, "GiB", ["gib"])
        add("tempo", UnitDuration.milliseconds, "ms", ["ms"])
        add("tempo", UnitDuration.seconds, "s", ["s", "seg", "segundo", "segundos", "sec", "seconds"])
        add("tempo", UnitDuration.minutes, "min", ["min", "minuto", "minutos", "minutes"])
        add("tempo", UnitDuration.hours, "h", ["h", "hora", "horas", "hour", "hours"])
        add("tempo", UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400)), "dias",
            ["d", "dia", "dias", "day", "days"])
        add("tempo", UnitDuration(symbol: "sem", converter: UnitConverterLinear(coefficient: 604_800)), "semanas",
            ["semana", "semanas", "week", "weeks"])
        add("area", UnitArea.squareMeters, "m²", ["m2", "m²"])
        add("area", UnitArea.squareKilometers, "km²", ["km2", "km²"])
        add("area", UnitArea.hectares, "ha", ["ha", "hectare", "hectares"])
        add("area", UnitArea.acres, "acres", ["acre", "acres"])
        return t
    }()

    private static let separadores = [" em ", " para ", " pra ", "->", "→", " to ", " in "]

    public static func converter(_ entrada: String) -> Resultado? {
        let s = " " + BarraDeComando.normalizar(entrada).trimmingCharacters(in: .whitespaces) + " "
        // na ordem da lista, e do fim para o começo: em "5 in to cm" o "in" é
        // a polegada, e o separador é o "to"
        guard let sep = separadores.lazy.compactMap({ s.range(of: $0, options: .backwards) }).first else { return nil }
        let esquerda = s[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
        let direita = s[sep.upperBound...].trimmingCharacters(in: .whitespaces)

        // número e unidade, colados ("10km") ou não ("10 km")
        guard let fimDoNumero = esquerda.firstIndex(where: { !($0.isNumber || $0 == "." || $0 == "," || $0 == "-") }),
              fimDoNumero > esquerda.startIndex else { return nil }
        let numero = Calculadora.normalizarNumeros(String(esquerda[..<fimDoNumero]))
        let nomeDe = esquerda[fimDoNumero...].trimmingCharacters(in: .whitespaces)
        guard let valor = Double(numero),
              let de = tabela[nomeDe], let para = tabela[direita],
              de.categoria == para.categoria else { return nil }

        let r = Measurement(value: valor, unit: de.unidade).converted(to: para.unidade).value
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = abs(r) < 1 ? 6 : 2
        let texto = f.string(from: NSNumber(value: r)) ?? String(r)
        f.usesGroupingSeparator = false
        let copia = f.string(from: NSNumber(value: r)) ?? String(r)
        return Resultado(texto: "\(texto) \(para.simbolo)", copia: copia)
    }
}

// MARK: - Emoji

public enum Emojis {

    public struct Emoji: Equatable, Sendable {
        public let caractere: String
        /// O nome do Unicode, em minúsculas ("grinning face"), com os
        /// apelidos em português na frente quando há.
        public let nome: String
    }

    /// Apelidos em português dos mais usados — o nome do Unicode é em inglês.
    static let apelidos: [String: String] = [
        "😀": "sorriso feliz", "😂": "risada chorando de rir kkk", "🤣": "rolando de rir kkk",
        "😊": "sorriso timido", "😍": "apaixonado olhos de coracao", "😘": "beijo",
        "😉": "piscadinha", "😎": "oculos escuros legal", "🤔": "pensando hmm",
        "😢": "chorando triste", "😭": "chorando muito", "😡": "bravo raiva",
        "😱": "susto grito", "😴": "dormindo sono", "🙄": "revirando os olhos",
        "😅": "sorriso sem graca suor", "🥲": "sorriso com lagrima", "🥰": "carinho amor",
        "🤯": "cabeca explodindo", "🥳": "festa comemoracao", "😬": "careta",
        "👍": "joinha positivo legal", "👎": "negativo", "👏": "palmas aplausos",
        "🙏": "por favor obrigado oracao maos juntas", "👋": "tchau ola aceno", "💪": "forca braco",
        "👀": "olhos olhando", "🤝": "aperto de maos acordo", "✌️": "paz",
        "❤️": "coracao vermelho amor", "💔": "coracao partido", "🔥": "fogo",
        "✨": "brilho", "⭐": "estrela", "🎉": "festa confete", "💯": "cem",
        "✅": "certo feito ok", "❌": "errado x", "⚠️": "aviso atencao", "💡": "ideia lampada",
        "🚀": "foguete", "☕": "cafe", "🍕": "pizza", "🍺": "cerveja", "🎂": "bolo aniversario",
        "🎁": "presente", "📌": "alfinete fixar", "📎": "clipe", "📝": "nota anotacao",
        "📅": "calendario data", "⏰": "despertador", "💻": "computador notebook", "📱": "celular",
        "🐶": "cachorro", "🐱": "gato", "☀️": "sol", "🌧️": "chuva", "⚽": "futebol bola",
        "🇧🇷": "brasil bandeira", "💰": "dinheiro", "🤷": "sei la dar de ombros", "🙈": "macaco nao vejo",
        "😇": "anjo", "🤡": "palhaco", "💀": "caveira morri", "👌": "ok perfeito",
    ]

    /// Os emoji que aparecem como figura por padrão, com nome. Calculado uma vez.
    public static let todos: [Emoji] = {
        let faixas: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF,
                                             0x1F900...0x1F9FF, 0x1FA70...0x1FAFF, 0x2600...0x27BF]
        var lista: [Emoji] = []
        var vistos = Set<String>()
        for faixa in faixas {
            for v in faixa {
                guard let s = Unicode.Scalar(v), s.properties.isEmojiPresentation,
                      let nome = s.properties.name else { continue }
                let c = String(Character(s))
                vistos.insert(c)
                lista.append(Emoji(caractere: c, nome: ((apelidos[c].map { $0 + " · " }) ?? "") + nome.lowercased()))
            }
        }
        // apelidos que não estão nas faixas (os com seletor de variação, a bandeira)
        for (c, a) in apelidos where !vistos.contains(c) {
            lista.append(Emoji(caractere: c, nome: a))
        }
        return lista
    }()

    public static func buscar(_ termo: String, limite: Int = 8) -> [Emoji] {
        let t = BarraDeComando.normalizar(termo.trimmingCharacters(in: .whitespaces))
        guard t.count >= 2 else { return [] }
        return todos
            .compactMap { e -> (Emoji, Int)? in
                let palavras = e.nome.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                if palavras.contains(where: { $0 == t }) { return (e, 3) }
                // só no começo da palavra: "term" no meio de "watermelon"
                // poria a melancia na frente do Terminal
                return palavras.contains(where: { $0.hasPrefix(t) }) ? (e, 2) : nil
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.nome.count < $1.0.nome.count }
            .prefix(limite)
            .map(\.0)
    }
}
