import Foundation

/// O Timer da ilha: temporizador, Pomodoro e cronômetro.
///
/// Tudo guardado como datas, nunca como contagem de segundos: o Mac pode
/// dormir no meio, e a conta tem que estar certa ao acordar.
public struct TimerDaIlha: Equatable, Sendable {

    public enum Modo: String, CaseIterable, Identifiable, Sendable, Codable {
        case temporizador, pomodoro, cronometro
        public var id: String { rawValue }
        public var titulo: String {
            switch self {
            case .temporizador: return "Timer"
            case .pomodoro:     return "Pomodoro"
            case .cronometro:   return "Cronômetro"
            }
        }
    }

    public enum FaseDoPomodoro: String, Sendable, Codable {
        case foco, pausa, pausaLonga
        public var titulo: String {
            switch self {
            case .foco:       return "Foco"
            case .pausa:      return "Pausa"
            case .pausaLonga: return "Pausa longa"
            }
        }
    }

    /// Rodando até `fim`, pausado com `restante`, ou parado.
    public enum Corrida: Equatable, Sendable {
        case parado
        case rodando(fim: Date)
        case pausado(restante: TimeInterval)
    }

    public var modo: Modo = .temporizador
    /// Minutos escolhidos na régua do temporizador.
    public var minutos: Int = 15
    public var corrida: Corrida = .parado

    // Pomodoro
    public var minutosDeFoco = 25
    public var minutosDePausa = 5
    public var minutosDePausaLonga = 15
    public var focosAntesDaLonga = 4
    public private(set) var fase: FaseDoPomodoro = .foco
    /// Focos já completados no ciclo atual.
    public private(set) var focosFeitos = 0

    // Cronômetro
    public private(set) var cronometroDesde: Date?
    public private(set) var cronometroAcumulado: TimeInterval = 0
    public private(set) var voltas: [TimeInterval] = []

    public static let limiteDaRegua = 60

    public init() {}

    // MARK: temporizador e Pomodoro

    /// A duração da contagem atual, em segundos.
    public var duracao: TimeInterval {
        switch modo {
        case .temporizador: return TimeInterval(max(1, minutos) * 60)
        case .pomodoro:
            switch fase {
            case .foco:       return TimeInterval(minutosDeFoco * 60)
            case .pausa:      return TimeInterval(minutosDePausa * 60)
            case .pausaLonga: return TimeInterval(minutosDePausaLonga * 60)
            }
        case .cronometro: return 0
        }
    }

    public var rodando: Bool {
        if modo == .cronometro { return cronometroDesde != nil }
        if case .rodando = corrida { return true }
        return false
    }

    public var ativo: Bool {
        if modo == .cronometro { return cronometroDesde != nil || cronometroAcumulado > 0 }
        return corrida != .parado
    }

    public func restante(em agora: Date) -> TimeInterval {
        switch corrida {
        case .parado:              return duracao
        case .rodando(let fim):    return max(0, fim.timeIntervalSince(agora))
        case .pausado(let r):      return r
        }
    }

    /// 0 no começo, 1 no fim.
    public func progresso(em agora: Date) -> Double {
        guard duracao > 0 else { return 0 }
        return min(1, max(0, 1 - restante(em: agora) / duracao))
    }

    public mutating func iniciar(em agora: Date) {
        switch corrida {
        case .parado:           corrida = .rodando(fim: agora.addingTimeInterval(duracao))
        case .pausado(let r):   corrida = .rodando(fim: agora.addingTimeInterval(r))
        case .rodando:          break
        }
    }

    public mutating func pausar(em agora: Date) {
        if case .rodando(let fim) = corrida { corrida = .pausado(restante: max(0, fim.timeIntervalSince(agora))) }
    }

    public mutating func parar() {
        corrida = .parado
        if modo == .pomodoro { fase = .foco; focosFeitos = 0 }
    }

    /// Chamado a cada tique. Devolve a fase que terminou agora, se terminou
    /// (o temporizador termina como "foco"). No Pomodoro, a próxima fase já
    /// começa sozinha; o temporizador simples para.
    public mutating func conferir(em agora: Date) -> FaseDoPomodoro? {
        guard case .rodando(let fim) = corrida, agora >= fim else { return nil }
        switch modo {
        case .temporizador:
            corrida = .parado
            return .foco
        case .pomodoro:
            let terminou = fase
            if fase == .foco {
                focosFeitos += 1
                fase = focosFeitos >= focosAntesDaLonga ? .pausaLonga : .pausa
                if fase == .pausaLonga { focosFeitos = 0 }
            } else {
                fase = .foco
            }
            // a próxima conta a partir do fim da anterior, não de agora:
            // um tique atrasado não come segundos da fase seguinte
            corrida = .rodando(fim: fim.addingTimeInterval(duracao))
            return terminou
        case .cronometro:
            return nil
        }
    }

    // MARK: cronômetro

    public func decorrido(em agora: Date) -> TimeInterval {
        cronometroAcumulado + (cronometroDesde.map { agora.timeIntervalSince($0) } ?? 0)
    }

    public mutating func alternarCronometro(em agora: Date) {
        if let d = cronometroDesde {
            cronometroAcumulado += agora.timeIntervalSince(d)
            cronometroDesde = nil
        } else {
            cronometroDesde = agora
        }
    }

    public mutating func volta(em agora: Date) {
        guard cronometroDesde != nil else { return }
        voltas.insert(decorrido(em: agora), at: 0)
    }

    public mutating func zerarCronometro() {
        cronometroDesde = nil
        cronometroAcumulado = 0
        voltas = []
    }

    // MARK: textos

    /// "15:00", "1:02:03".
    public static func relogio(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, seg = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, seg) : String(format: "%d:%02d", m, seg)
    }

    /// Cronômetro com décimos: "1:05,3".
    public static func cronometro(_ t: TimeInterval) -> String {
        let d = Int((t * 10).rounded(.down))
        let s = d / 10, decimo = d % 10
        let h = s / 3600, m = (s % 3600) / 60, seg = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d,%d", h, m, seg, decimo)
                     : String(format: "%d:%02d,%d", m, seg, decimo)
    }

    /// Curto, para a asa da ilha: "14m", "45s", "1h 05".
    public static func curto(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        if s < 60 { return "\(s)s" }
        let m = Int((Double(s) / 60).rounded(.up))
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02d", m / 60, m % 60)
    }

    /// A atividade ao vivo, quando há algo correndo.
    public func atividade(em agora: Date) -> Ilha.Atividade? {
        switch modo {
        case .cronometro:
            guard ativo else { return nil }
            return Ilha.Atividade(id: "timer", tipo: .cronometro, simbolo: "stopwatch",
                                  valor: Self.curto(decorrido(em: agora)), prioridade: 50)
        case .temporizador, .pomodoro:
            guard ativo else { return nil }
            let simbolo = modo == .pomodoro ? (fase == .foco ? "brain.head.profile" : "cup.and.saucer") : "timer"
            return Ilha.Atividade(id: "timer", tipo: modo == .pomodoro ? .pomodoro : .timer, simbolo: simbolo,
                                  valor: Self.curto(restante(em: agora)), prioridade: 60,
                                  progresso: progresso(em: agora))
        }
    }
}
