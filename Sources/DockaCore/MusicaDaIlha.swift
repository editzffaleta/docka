import Foundation

/// O que está tocando agora, como a ilha mostra: lido do sistema (qualquer
/// app ou aba do navegador que anuncie o que toca).
public struct TocandoAgora: Equatable, Sendable {
    public var pid: Int32
    public var titulo: String?
    public var artista: String?
    public var album: String?
    public var duracao: TimeInterval?
    /// A posição no instante `carimbo`.
    public var decorrido: TimeInterval
    public var taxa: Double
    public var carimbo: Date?
    public var tocando: Bool
    public var capaId: String?

    public init(pid: Int32 = 0, titulo: String? = nil, artista: String? = nil, album: String? = nil,
                duracao: TimeInterval? = nil, decorrido: TimeInterval = 0, taxa: Double = 0,
                carimbo: Date? = nil, tocando: Bool = false, capaId: String? = nil) {
        self.pid = pid; self.titulo = titulo; self.artista = artista; self.album = album
        self.duracao = duracao; self.decorrido = decorrido; self.taxa = taxa
        self.carimbo = carimbo; self.tocando = tocando; self.capaId = capaId
    }

    /// Uma linha do ajudante (já decodificada do JSON).
    public init(json: [String: Any]) {
        func numero(_ k: String) -> Double? { (json[k] as? NSNumber)?.doubleValue }
        pid = Int32(numero("pid") ?? 0)
        titulo = (json["titulo"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        artista = (json["artista"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        album = (json["album"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        duracao = numero("duracao").flatMap { $0 > 0 ? $0 : nil }
        decorrido = numero("decorrido") ?? 0
        taxa = numero("taxa") ?? 0
        carimbo = numero("carimbo").map { Date(timeIntervalSince1970: $0) }
        tocando = (numero("tocando") ?? 0) != 0
        capaId = json["capaId"] as? String
    }

    /// Tem alguma coisa para mostrar.
    public var temFaixa: Bool { titulo != nil }

    /// Mesma música (para buscar a letra e a capa só uma vez).
    public func mesmaFaixa(_ o: TocandoAgora) -> Bool {
        titulo == o.titulo && artista == o.artista && album == o.album
    }

    /// A posição agora: a do carimbo, mais o tempo que passou tocando.
    public func posicao(em agora: Date) -> TimeInterval {
        var p = decorrido
        if tocando, let c = carimbo { p += agora.timeIntervalSince(c) * (taxa > 0 ? taxa : 1) }
        p = max(0, p)
        if let d = duracao { p = min(d, p) }
        return p
    }
}

/// Letra sincronizada no formato LRC: "[01:23.45] verso".
public enum Letra {
    public struct Linha: Equatable, Sendable {
        public let tempo: TimeInterval
        public let texto: String
        public init(tempo: TimeInterval, texto: String) { self.tempo = tempo; self.texto = texto }
    }

    /// Linhas em ordem de tempo. Uma linha com vários tempos ("[00:10][01:20] refrão")
    /// vira várias; linhas de cabeçalho ("[ar: …]") e sem tempo ficam de fora.
    public static func ler(_ lrc: String) -> [Linha] {
        var r: [Linha] = []
        for bruta in lrc.split(whereSeparator: \.isNewline) {
            var resto = Substring(bruta)
            var tempos: [TimeInterval] = []
            while resto.hasPrefix("["), let fim = resto.firstIndex(of: "]") {
                let marca = resto[resto.index(after: resto.startIndex)..<fim]
                if let t = tempo(String(marca)) { tempos.append(t) } else { break }
                resto = resto[resto.index(after: fim)...]
            }
            guard !tempos.isEmpty else { continue }
            let texto = resto.trimmingCharacters(in: .whitespaces)
            for t in tempos { r.append(Linha(tempo: t, texto: texto)) }
        }
        return r.sorted { $0.tempo < $1.tempo }
    }

    /// "01:23.45" ou "1:23" → segundos.
    static func tempo(_ s: String) -> TimeInterval? {
        let partes = s.split(separator: ":")
        guard partes.count == 2, let m = Double(partes[0]),
              let seg = Double(partes[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
        return m * 60 + seg
    }

    /// O índice da linha que está sendo cantada em `posicao` (nil antes da primeira).
    public static func atual(_ linhas: [Linha], em posicao: TimeInterval) -> Int? {
        var r: Int?
        for (i, l) in linhas.enumerated() {
            if l.tempo <= posicao + 0.15 { r = i } else { break }
        }
        return r
    }
}

/// As barras do equalizador.
public enum Equalizador {

    /// Junta as magnitudes de um espectro (do grave ao agudo) em `quantas`
    /// faixas de largura crescente — o ouvido percebe a frequência em escala
    /// logarítmica, e faixas iguais deixariam quase tudo nas duas primeiras.
    /// Cada faixa sai entre 0 e 1.
    public static func faixas(_ magnitudes: [Float], quantas: Int, piso: Float = -60) -> [Float] {
        guard magnitudes.count > quantas, quantas > 0 else { return Array(repeating: 0, count: max(quantas, 0)) }
        let n = Float(magnitudes.count - 1)
        var r: [Float] = []
        for i in 0..<quantas {
            let a = Int(pow(n, Float(i) / Float(quantas)))
            let b = max(a + 1, Int(pow(n, Float(i + 1) / Float(quantas))))
            let fatia = magnitudes[min(a, magnitudes.count - 1)..<min(b, magnitudes.count)]
            // o pico da faixa, e não a média: numa faixa larga, a média dilui a
            // nota que está tocando entre dezenas de frequências caladas
            let pico = fatia.max() ?? 0
            let db = 20 * log10(max(pico, 1e-9))
            r.append(min(1, max(0, (db - piso) / -piso)))
        }
        return r
    }

    /// Ganho automático: escala pelo maior valor recente (que vai caindo
    /// devagar), para as barras usarem a altura toda com som baixo ou alto.
    /// Devolve as faixas escaladas e o novo maior valor.
    public static func ganho(_ faixas: [Float], maior: Float, piso: Float = 0.35, queda: Float = 0.995) -> (faixas: [Float], maior: Float) {
        let novo = max(faixas.max() ?? 0, maior * queda, piso)
        return (faixas.map { min(1, $0 / novo) }, novo)
    }

    /// Sobe rápido e desce devagar, como o ponteiro de um VU.
    public static func suavizar(_ anterior: [Float], _ novo: [Float], subida: Float = 0.6, descida: Float = 0.15) -> [Float] {
        guard anterior.count == novo.count else { return novo }
        return zip(anterior, novo).map { a, n in a + (n - a) * (n > a ? subida : descida) }
    }

    /// Barras de enfeite quando não há o áudio de verdade: ondas lentas
    /// defasadas, para cada barra ter o seu ritmo.
    public static func enfeite(quantas: Int, em t: TimeInterval) -> [Float] {
        (0..<quantas).map { i in
            let f = Double(i)
            let v = 0.55 + 0.25 * sin(t * (5.1 + f * 1.7) + f) + 0.2 * sin(t * (8.3 - f) + f * 2.3)
            return Float(min(1, max(0.12, v)))
        }
    }
}
