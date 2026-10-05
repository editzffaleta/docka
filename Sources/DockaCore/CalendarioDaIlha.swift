import Foundation

/// A agenda da ilha: o que mostrar de cada evento, o mês em grade e o aviso
/// do próximo compromisso. Sem EventKit aqui — os eventos chegam prontos.
public enum CalendarioDaIlha {

    public struct Evento: Equatable, Identifiable, Sendable {
        public let id: String
        public let titulo: String
        public let inicio: Date
        public let fim: Date
        public let diaInteiro: Bool
        public let local: String?
        /// Cor do calendário, como "#RRGGBB".
        public let cor: String?
        public let reuniao: URL?

        public init(id: String, titulo: String, inicio: Date, fim: Date, diaInteiro: Bool = false,
                    local: String? = nil, cor: String? = nil, reuniao: URL? = nil) {
            self.id = id; self.titulo = titulo; self.inicio = inicio; self.fim = fim
            self.diaInteiro = diaInteiro; self.local = local; self.cor = cor; self.reuniao = reuniao
        }

        public func acontecendo(em agora: Date) -> Bool { inicio <= agora && agora < fim }
    }

    /// O link da chamada de vídeo, procurado no endereço, no local e nas
    /// notas do evento — onde Zoom, Meet, Teams e companhia costumam deixar.
    public static func linkDeReuniao(_ textos: [String?]) -> URL? {
        let padroes = [
            #"https://([a-z0-9-]+\.)?zoom\.us/(j|my|w)/[^\s<>"']+"#,
            #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}[^\s<>"']*"#,
            #"https://teams\.microsoft\.com/l/meetup-join/[^\s<>"']+"#,
            #"https://teams\.live\.com/meet/[^\s<>"']+"#,
            #"https://([a-z0-9-]+\.)?webex\.com/[^\s<>"']+"#,
            #"https://facetime\.apple\.com/join[^\s<>"']+"#,
            #"https://([a-z0-9-]+\.)?whereby\.com/[^\s<>"']+"#,
        ]
        for t in textos.compactMap({ $0 }) {
            for p in padroes {
                if let r = t.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                    return URL(string: String(t[r]))
                }
            }
        }
        return nil
    }

    /// As casas do mês em grade de semanas: nil nas casas vazias antes do
    /// dia 1 e depois do último. Começa no primeiro dia da semana do
    /// calendário (domingo, no Brasil).
    public static func grade(do mes: Date, calendario: Calendar) -> [Date?] {
        guard let intervalo = calendario.dateInterval(of: .month, for: mes),
              let dias = calendario.range(of: .day, in: .month, for: mes) else { return [] }
        let primeiro = intervalo.start
        let semana = calendario.component(.weekday, from: primeiro)
        let antes = (semana - calendario.firstWeekday + 7) % 7
        var r: [Date?] = Array(repeating: nil, count: antes)
        for d in dias {
            r.append(calendario.date(byAdding: .day, value: d - 1, to: primeiro))
        }
        while r.count % 7 != 0 { r.append(nil) }
        return r
    }

    /// Os eventos de um dia, os de dia inteiro primeiro e o resto pela hora.
    public static func doDia(_ eventos: [Evento], _ dia: Date, calendario: Calendar) -> [Evento] {
        guard let i = calendario.dateInterval(of: .day, for: dia) else { return [] }
        return eventos.filter { $0.inicio < i.end && $0.fim > i.start }
            .sorted { ($0.diaInteiro ? 0 : 1, $0.inicio) < ($1.diaInteiro ? 0 : 1, $1.inicio) }
    }

    /// "agora", "em 5 min", "em 2 h" — ou a hora, se for mais longe, no
    /// formato que `hora` der (o app passa o do sistema: 24 h ou AM/PM).
    public static func quando(_ e: Evento, agora: Date, calendario: Calendar,
                              hora: ((Date) -> String)? = nil) -> String {
        if e.diaInteiro { return "o dia todo" }
        if e.acontecendo(em: agora) { return "agora" }
        let s = e.inicio.timeIntervalSince(agora)
        if s > 0 && s < 3600 { return "em \(max(1, Int((s / 60).rounded(.up)))) min" }
        if s > 0 && s < 4 * 3600 { return "em \(Int(s / 3600)) h" }
        if let hora { return hora(e.inicio) }
        let f = DateFormatter()
        f.calendar = calendario
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = calendario.timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: e.inicio)
    }

    /// O compromisso que merece aviso na ilha fechada: o próximo a começar
    /// em até `antecedencia`, ou um que começou há pouco (até 5 min).
    public static func proximo(_ eventos: [Evento], agora: Date, antecedencia: TimeInterval = 15 * 60) -> Evento? {
        eventos.filter { !$0.diaInteiro }
            .filter { let s = $0.inicio.timeIntervalSince(agora); return s <= antecedencia && s > -5 * 60 }
            .min { $0.inicio < $1.inicio }
    }
}
