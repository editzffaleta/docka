import Foundation

/// Os agentes de IA na ilha (Claude Code, Codex): uso, janelas do plano,
/// trabalho ao vivo e o aviso de tarefa longa terminada — tudo tirado dos
/// registros que eles mesmos gravam no Mac. Só números e horários: o texto
/// das conversas nunca é guardado.
public enum AgentesDaIlha {

    // MARK: uso

    public struct Uso: Equatable, Sendable {
        public var entrada: Int = 0
        public var cacheEscrita5m: Int = 0
        public var cacheEscrita1h: Int = 0
        public var cacheLeitura: Int = 0
        public var saida: Int = 0

        public init(entrada: Int = 0, cacheEscrita5m: Int = 0, cacheEscrita1h: Int = 0, cacheLeitura: Int = 0, saida: Int = 0) {
            self.entrada = entrada; self.cacheEscrita5m = cacheEscrita5m; self.cacheEscrita1h = cacheEscrita1h
            self.cacheLeitura = cacheLeitura; self.saida = saida
        }

        public var total: Int { entrada + cacheEscrita5m + cacheEscrita1h + cacheLeitura + saida }

        public static func + (a: Uso, b: Uso) -> Uso {
            Uso(entrada: a.entrada + b.entrada, cacheEscrita5m: a.cacheEscrita5m + b.cacheEscrita5m,
                cacheEscrita1h: a.cacheEscrita1h + b.cacheEscrita1h, cacheLeitura: a.cacheLeitura + b.cacheLeitura,
                saida: a.saida + b.saida)
        }
    }

    /// Uma resposta do Claude Code.
    public struct Resposta: Equatable, Sendable {
        public let sessao: String
        public let projeto: String
        public let modelo: String
        public let momento: Date
        public let uso: Uso
        /// A resposta encerrou a vez do agente (e não parou para usar uma ferramenta).
        public let fimDaVez: Bool
        /// Identifica a mensagem: o Claude Code grava a mesma resposta em
        /// várias linhas (uma por parte), todas com o mesmo uso — somar todas
        /// contaria o uso duas, três vezes.
        public var chave: String? = nil
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func data(_ s: String?) -> Date? {
        guard let s else { return nil }
        if let d = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return d }
        // frações com mais de 3 casas ("…05.123456Z"): o leitor só aceita
        // milissegundos — corta o excesso e tenta de novo
        guard let ponto = s.firstIndex(of: "."), let fim = s[ponto...].firstIndex(where: { !$0.isNumber && $0 != "." })
        else { return nil }
        let frac = s[s.index(after: ponto)..<fim]
        guard frac.count > 3 else { return nil }
        return iso.date(from: String(s[..<ponto]) + "." + frac.prefix(3) + s[fim...])
    }

    /// Uma linha do registro do Claude Code (já decodificada). Só as
    /// respostas com uso contam; as outras dão nil.
    public static func respostaDoClaude(_ o: [String: Any]) -> Resposta? {
        guard o["type"] as? String == "assistant", let m = o["message"] as? [String: Any],
              let u = m["usage"] as? [String: Any], let quando = data(o["timestamp"] as? String) else { return nil }
        func n(_ d: [String: Any]?, _ k: String) -> Int { (d?[k] as? NSNumber)?.intValue ?? 0 }
        let criacao = u["cache_creation"] as? [String: Any]
        var uso = Uso(entrada: n(u, "input_tokens"), cacheLeitura: n(u, "cache_read_input_tokens"), saida: n(u, "output_tokens"))
        if criacao != nil {
            uso.cacheEscrita5m = n(criacao, "ephemeral_5m_input_tokens")
            uso.cacheEscrita1h = n(criacao, "ephemeral_1h_input_tokens")
        } else {
            uso.cacheEscrita5m = n(u, "cache_creation_input_tokens")
        }
        let cwd = o["cwd"] as? String ?? ""
        let chave = (m["id"] as? String).map { "\($0)|\(o["requestId"] as? String ?? "")" }
        return Resposta(sessao: o["sessionId"] as? String ?? "", projeto: (cwd as NSString).lastPathComponent,
                        modelo: m["model"] as? String ?? "", momento: quando, uso: uso,
                        fimDaVez: m["stop_reason"] as? String == "end_turn", chave: chave)
    }

    /// Uma resposta por mensagem: das repetidas, fica a última (a que tem o
    /// motivo da parada de verdade).
    public static func semRepetidas(_ l: [Resposta]) -> [Resposta] {
        var ultima: [String: Int] = [:]
        for (i, x) in l.enumerated() { if let k = x.chave { ultima[k] = i } }
        return l.enumerated().filter { i, x in x.chave.map { ultima[$0] == i } ?? true }.map(\.element)
    }

    /// O uso de verdade de um limite: depois de renovar, a janela começa do zero.
    public static func usadoAgora(_ l: Limite, agora: Date) -> Double {
        if let r = l.renova, r <= agora { return 0 }
        return l.usado
    }

    // MARK: limite do plano (Codex)

    public struct Limite: Equatable, Sendable {
        public let usado: Double          // 0…100
        public let janelaMinutos: Int
        public let renova: Date?
        public let plano: String?
    }

    /// O limite do plano, de uma contagem de tokens do Codex.
    public static func limiteDoCodex(_ o: [String: Any]) -> (momento: Date, primario: Limite?, secundario: Limite?)? {
        guard o["type"] as? String == "event_msg", let p = o["payload"] as? [String: Any],
              p["type"] as? String == "token_count", let quando = data(o["timestamp"] as? String),
              let r = p["rate_limits"] as? [String: Any] else { return nil }
        let plano = r["plan_type"] as? String
        func lim(_ k: String) -> Limite? {
            guard let d = r[k] as? [String: Any], let u = (d["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let renova = (d["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return Limite(usado: u, janelaMinutos: (d["window_minutes"] as? NSNumber)?.intValue ?? 0, renova: renova, plano: plano)
        }
        return (quando, lim("primary"), lim("secondary"))
    }

    // MARK: janelas de 5 horas

    public struct Janela: Equatable, Sendable {
        public let inicio: Date
        public let fim: Date
        public var uso: Uso
        public var valor: Double?
        public var ultima: Date
    }

    /// As janelas de 5 horas do plano: começam na hora cheia da primeira
    /// mensagem e duram 5 h; uma mensagem depois do fim (ou após 5 h parado)
    /// abre a próxima. É a conta que o plano do Claude faz — estimada, porque
    /// o registro não traz o limite.
    public static func janelas(_ respostas: [Resposta], duracao: TimeInterval = 5 * 3600,
                               calendario: Calendar = .current) -> [Janela] {
        var r: [Janela] = []
        for x in respostas.sorted(by: { $0.momento < $1.momento }) {
            let v = valor(modelo: x.modelo, uso: x.uso)
            if var j = r.last, x.momento < j.fim, x.momento.timeIntervalSince(j.ultima) < duracao {
                j.uso = j.uso + x.uso
                j.valor = j.valor.flatMap { a in v.map { a + $0 } }
                j.ultima = x.momento
                r[r.count - 1] = j
            } else {
                let hora = calendario.dateInterval(of: .hour, for: x.momento)?.start ?? x.momento
                r.append(Janela(inicio: hora, fim: hora.addingTimeInterval(duracao), uso: x.uso, valor: v, ultima: x.momento))
            }
        }
        return r
    }

    public static func atual(_ j: [Janela], agora: Date) -> Janela? {
        guard let u = j.last, agora < u.fim else { return nil }
        return u
    }

    // MARK: valor estimado

    /// Dólares por milhão de tokens: entrada, saída. Cache: escrita de 5 min
    /// a 1,25× a entrada, de 1 h a 2×, leitura a 0,1×. Só os modelos com
    /// preço público conhecido; para os outros, nil (mostra só os tokens).
    static let precos: [(trecho: String, entrada: Double, saida: Double)] = [
        ("opus-4-5", 5, 25), ("opus-4-6", 5, 25),
        ("opus-4-1", 15, 75), ("opus-4", 15, 75), ("claude-3-opus", 15, 75),
        ("sonnet-4", 3, 15), ("sonnet-3-7", 3, 15), ("claude-3-5-sonnet", 3, 15),
        ("haiku-4-5", 1, 5), ("claude-3-5-haiku", 0.8, 4),
    ]

    public static func valor(modelo: String, uso: Uso) -> Double? {
        guard let p = precos.first(where: { modelo.contains($0.trecho) }) else { return nil }
        let m = 1_000_000.0
        return (Double(uso.entrada) * p.entrada + Double(uso.cacheEscrita5m) * p.entrada * 1.25
                + Double(uso.cacheEscrita1h) * p.entrada * 2 + Double(uso.cacheLeitura) * p.entrada * 0.1
                + Double(uso.saida) * p.saida) / m
    }

    // MARK: trabalho ao vivo e tarefa longa

    /// Quanto tempo a sessão está trabalhando sem parar: desde a primeira
    /// resposta depois do último fim de vez. nil se ela está parada (último
    /// registro é um fim de vez, ou nada há `parada` segundos).
    public static func trabalhando(_ respostasDaSessao: [Resposta], agora: Date, parada: TimeInterval = 90) -> TimeInterval? {
        let l = respostasDaSessao.sorted { $0.momento < $1.momento }
        guard let ultima = l.last, !ultima.fimDaVez, agora.timeIntervalSince(ultima.momento) < parada else { return nil }
        let inicio = l.last(where: { $0.fimDaVez }).flatMap { fim in l.first { $0.momento > fim.momento } } ?? l.first!
        return agora.timeIntervalSince(inicio.momento)
    }

    /// A vez que acabou de terminar, se foi longa: duração da primeira
    /// resposta da vez até o fim. Para o aviso de "tarefa longa terminou".
    public static func vezLongaTerminada(_ respostasDaSessao: [Resposta], minimo: TimeInterval) -> (fim: Date, duracao: TimeInterval)? {
        let l = respostasDaSessao.sorted { $0.momento < $1.momento }
        guard let fim = l.last, fim.fimDaVez else { return nil }
        let anterior = l.dropLast().last(where: { $0.fimDaVez })
        let inicio = anterior.flatMap { a in l.first { $0.momento > a.momento } } ?? l.first!
        let d = fim.momento.timeIntervalSince(inicio.momento)
        return d >= minimo ? (fim.momento, d) : nil
    }

    // MARK: textos

    /// "1,2 mi", "350 mil", "820".
    public static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f mi", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if n >= 1000 { return "\(n / 1000) mil" }
        return "\(n)"
    }

    public static func dolares(_ v: Double) -> String {
        String(format: "US$ %.2f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// "3 min", "1 h 05".
    public static func duracao(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        return m < 60 ? "\(max(1, m)) min" : String(format: "%d h %02d", m / 60, m % 60)
    }
}
