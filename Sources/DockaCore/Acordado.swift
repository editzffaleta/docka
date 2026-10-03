import Foundation

/// Por quanto tempo o Mac fica acordado.
///
/// Lógica pura: escolher a duração, saber quando acaba e o que mostrar. Quem
/// segura o Mac acordado de verdade é a casca, com uma asserção de energia.
public enum DuracaoAcordado: Int, CaseIterable, Identifiable, Codable, Sendable {
    case quinzeMinutos = 15
    case trintaMinutos = 30
    case umaHora = 60
    case duasHoras = 120
    case cincoHoras = 300
    /// Até desligar à mão.
    case semLimite = 0

    public var id: Int { rawValue }

    /// `nil` = sem limite.
    public var segundos: TimeInterval? {
        self == .semLimite ? nil : TimeInterval(rawValue * 60)
    }

    public var titulo: String {
        switch self {
        case .quinzeMinutos: return "15 minutos"
        case .trintaMinutos: return "30 minutos"
        case .umaHora:       return "1 hora"
        case .duasHoras:     return "2 horas"
        case .cincoHoras:    return "5 horas"
        case .semLimite:     return "Até desligar"
        }
    }

    /// Valor gravado que sumiu da lista volta para o padrão, em vez de virar
    /// "sem limite" por acidente.
    public init(persisted: Int) {
        self = DuracaoAcordado(rawValue: persisted) ?? .umaHora
    }
}

public enum Acordado {

    /// Quando a sessão acaba, ou `nil` se não tem fim.
    public static func fim(de duracao: DuracaoAcordado, desde inicio: Date) -> Date? {
        duracao.segundos.map { inicio.addingTimeInterval($0) }
    }

    /// Segundos que faltam, nunca negativos. `nil` = sem limite.
    public static func restante(ate fim: Date?, agora: Date) -> TimeInterval? {
        fim.map { max(0, $0.timeIntervalSince(agora)) }
    }

    /// A sessão já passou do fim?
    public static func expirou(ate fim: Date?, agora: Date) -> Bool {
        guard let fim else { return false }
        return agora >= fim
    }

    /// Tempo restante no formato do menu: "1h 05min", "12min", "menos de 1min".
    ///
    /// Arredonda para CIMA: com 59,5 s faltando, "1min" é a verdade que importa —
    /// "0min" pareceria que já acabou.
    public static func rotulo(restante: TimeInterval?) -> String {
        guard let restante else { return "sem limite" }
        let minutos = Int((restante / 60).rounded(.up))
        if minutos < 1 { return "menos de 1min" }
        let h = minutos / 60
        let m = minutos % 60
        if h == 0 { return "\(m)min" }
        return m == 0 ? "\(h)h" : String(format: "%dh %02dmin", h, m)
    }
}
