import Testing
import Foundation
@testable import DockaCore

@Suite("Calendário da ilha")
struct CalendarioDaIlhaTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        c.firstWeekday = 1
        return c
    }
    private func data(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = cal.timeZone
        return f.date(from: s)!
    }
    private func ev(_ id: String, _ ini: String, _ fim: String, todo: Bool = false) -> CalendarioDaIlha.Evento {
        .init(id: id, titulo: id, inicio: data(ini), fim: data(fim), diaInteiro: todo)
    }

    @Test("Link de reunião no local, nas notas ou no endereço")
    func link() {
        #expect(CalendarioDaIlha.linkDeReuniao([nil, "Sala 3", "Entre: https://us02web.zoom.us/j/123456?pwd=abc obrigado"])?.host
                == "us02web.zoom.us")
        #expect(CalendarioDaIlha.linkDeReuniao(["https://meet.google.com/abc-defg-hij"])?.absoluteString
                == "https://meet.google.com/abc-defg-hij")
        #expect(CalendarioDaIlha.linkDeReuniao(["<https://teams.microsoft.com/l/meetup-join/19%3a>"]) != nil)
        #expect(CalendarioDaIlha.linkDeReuniao(["https://exemplo.com/reuniao", nil]) == nil)
    }

    @Test("Grade do mês: outubro de 2026 começa numa quinta, com domingo primeiro")
    func grade() {
        let g = CalendarioDaIlha.grade(do: data("2026-10-15T12:00:00-03:00"), calendario: cal)
        #expect(g.count % 7 == 0)
        #expect(g.prefix(4).allSatisfy { $0 == nil })          // dom, seg, ter, qua vazios
        #expect(g[4].map { cal.component(.day, from: $0) } == 1)
        #expect(g.compactMap { $0 }.count == 31)
    }

    @Test("Dia: dia inteiro primeiro, depois pela hora; evento que atravessa a meia-noite entra")
    func doDia() {
        let lista = [ev("tarde", "2026-10-05T15:00:00-03:00", "2026-10-05T16:00:00-03:00"),
                     ev("feriado", "2026-10-05T00:00:00-03:00", "2026-10-06T00:00:00-03:00", todo: true),
                     ev("manha", "2026-10-05T09:00:00-03:00", "2026-10-05T10:00:00-03:00"),
                     ev("virada", "2026-10-04T23:00:00-03:00", "2026-10-05T01:00:00-03:00"),
                     ev("amanha", "2026-10-06T09:00:00-03:00", "2026-10-06T10:00:00-03:00")]
        #expect(CalendarioDaIlha.doDia(lista, data("2026-10-05T12:00:00-03:00"), calendario: cal).map(\.id)
                == ["feriado", "virada", "manha", "tarde"])
    }

    @Test("Quando: agora, em minutos, em horas, ou a hora")
    func quando() {
        let agora = data("2026-10-05T14:00:00-03:00")
        #expect(CalendarioDaIlha.quando(ev("a", "2026-10-05T13:30:00-03:00", "2026-10-05T14:30:00-03:00"), agora: agora, calendario: cal) == "agora")
        #expect(CalendarioDaIlha.quando(ev("b", "2026-10-05T14:09:30-03:00", "2026-10-05T15:00:00-03:00"), agora: agora, calendario: cal) == "em 10 min")
        #expect(CalendarioDaIlha.quando(ev("c", "2026-10-05T16:30:00-03:00", "2026-10-05T17:00:00-03:00"), agora: agora, calendario: cal) == "em 2 h")
        #expect(CalendarioDaIlha.quando(ev("d", "2026-10-05T20:15:00-03:00", "2026-10-05T21:00:00-03:00"), agora: agora, calendario: cal) == "20:15")
    }

    @Test("Próximo: só o que começa em até 15 min ou começou há pouco")
    func proximo() {
        let agora = data("2026-10-05T14:00:00-03:00")
        let lista = [ev("longe", "2026-10-05T15:00:00-03:00", "2026-10-05T16:00:00-03:00"),
                     ev("perto", "2026-10-05T14:10:00-03:00", "2026-10-05T15:00:00-03:00"),
                     ev("todo", "2026-10-05T00:00:00-03:00", "2026-10-06T00:00:00-03:00", todo: true)]
        #expect(CalendarioDaIlha.proximo(lista, agora: agora)?.id == "perto")
        #expect(CalendarioDaIlha.proximo([lista[0]], agora: agora) == nil)
    }
}
