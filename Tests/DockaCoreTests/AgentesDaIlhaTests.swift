import Testing
import Foundation
@testable import DockaCore

@Suite("Agentes de IA na ilha")
struct AgentesDaIlhaTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)   // um instante qualquer
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func r(_ s: Double, _ sessao: String = "s", fim: Bool = false, modelo: String = "claude-sonnet-4-5",
                   uso: AgentesDaIlha.Uso = .init(entrada: 1000, saida: 100)) -> AgentesDaIlha.Resposta {
        .init(sessao: sessao, projeto: "docka", modelo: modelo, momento: t0.addingTimeInterval(s), uso: uso, fimDaVez: fim)
    }

    @Test("Linha do Claude Code: tokens, cache de 5 min e de 1 h, fim de vez")
    func claude() {
        let o: [String: Any] = [
            "type": "assistant", "timestamp": "2026-10-03T21:03:25.882Z", "sessionId": "abc", "cwd": "/Users/x/Docka",
            "message": ["model": "claude-opus-5-5", "stop_reason": "end_turn",
                        "usage": ["input_tokens": 2, "cache_read_input_tokens": 40752, "output_tokens": 222,
                                  "cache_creation_input_tokens": 18398,
                                  "cache_creation": ["ephemeral_1h_input_tokens": 18398, "ephemeral_5m_input_tokens": 0]]]]
        let x = AgentesDaIlha.respostaDoClaude(o)
        #expect(x?.projeto == "Docka" && x?.modelo == "claude-opus-5-5" && x?.fimDaVez == true)
        #expect(x?.uso == .init(entrada: 2, cacheEscrita5m: 0, cacheEscrita1h: 18398, cacheLeitura: 40752, saida: 222))
        #expect(AgentesDaIlha.respostaDoClaude(["type": "user"]) == nil)
    }

    @Test("Limite do plano do Codex")
    func codex() {
        let o: [String: Any] = ["type": "event_msg", "timestamp": "2026-07-15T15:53:35.799Z",
                                "payload": ["type": "token_count",
                                            "rate_limits": ["plan_type": "plus",
                                                            "primary": ["used_percent": 7.0, "window_minutes": 10080, "resets_at": 1784686653]]]]
        let l = AgentesDaIlha.limiteDoCodex(o)
        #expect(l?.primario?.usado == 7 && l?.primario?.janelaMinutos == 10080 && l?.primario?.plano == "plus")
        #expect(l?.secundario == nil)
    }

    @Test("Janelas de 5 h: começam na hora cheia, abrem outra depois do fim")
    func janelas() {
        let base = cal.dateInterval(of: .hour, for: t0)!.start
        let lista = [r(base.timeIntervalSince(t0) + 600), r(base.timeIntervalSince(t0) + 3600),
                     r(base.timeIntervalSince(t0) + 5 * 3600 + 60)]   // depois do fim → outra janela
        let j = AgentesDaIlha.janelas(lista, calendario: cal)
        #expect(j.count == 2)
        #expect(j[0].inicio == base && j[0].fim == base.addingTimeInterval(5 * 3600))
        #expect(j[0].uso.entrada == 2000)
        #expect(AgentesDaIlha.atual(j, agora: base.addingTimeInterval(5 * 3600 + 120))?.inicio == j[1].inicio)
    }

    @Test("Valor estimado só para preço conhecido")
    func valor() {
        let u = AgentesDaIlha.Uso(entrada: 1_000_000, saida: 1_000_000)
        #expect(AgentesDaIlha.valor(modelo: "claude-sonnet-4-5", uso: u) == 18)
        #expect(AgentesDaIlha.valor(modelo: "claude-opus-4-5-20251101", uso: u) == 30)
        #expect(AgentesDaIlha.valor(modelo: "modelo-desconhecido", uso: u) == nil)
        let cache = AgentesDaIlha.Uso(cacheEscrita1h: 1_000_000, cacheLeitura: 1_000_000)
        #expect(abs(AgentesDaIlha.valor(modelo: "claude-sonnet-4", uso: cache)! - 6.3) < 1e-9)
    }

    @Test("Trabalhando: desde o começo da vez; parado depois do fim ou sem novidade")
    func trabalhando() {
        let l = [r(0), r(60, fim: true), r(300), r(400), r(500)]
        #expect(AgentesDaIlha.trabalhando(l, agora: t0.addingTimeInterval(520)) == 220)
        #expect(AgentesDaIlha.trabalhando(l, agora: t0.addingTimeInterval(700)) == nil)     // parado há 200 s
        #expect(AgentesDaIlha.trabalhando([r(0), r(30, fim: true)], agora: t0.addingTimeInterval(40)) == nil)
    }

    @Test("Vez longa terminada")
    func vezLonga() {
        let longa = [r(0), r(60, fim: true), r(300), r(500), r(700, fim: true)]
        #expect(AgentesDaIlha.vezLongaTerminada(longa, minimo: 180)?.duracao == 400)
        #expect(AgentesDaIlha.vezLongaTerminada(longa, minimo: 600) == nil)
        #expect(AgentesDaIlha.vezLongaTerminada([r(0), r(10)], minimo: 1) == nil)          // ainda trabalhando
    }

    @Test("Sem repetidas: a mesma mensagem em várias linhas conta uma vez")
    func repetidas() {
        var a = r(0); a.chave = "m1|q1"
        var b = r(1, fim: true); b.chave = "m1|q1"
        var c = r(2); c.chave = "m2|q2"
        let l = AgentesDaIlha.semRepetidas([a, b, c])
        #expect(l.count == 2)
        #expect(l[0].fimDaVez)          // ficou a última das repetidas
    }

    @Test("Limite renovado volta a zero")
    func renovado() {
        let l = AgentesDaIlha.Limite(usado: 7, janelaMinutos: 10080, renova: t0, plano: "plus")
        #expect(AgentesDaIlha.usadoAgora(l, agora: t0.addingTimeInterval(-10)) == 7)
        #expect(AgentesDaIlha.usadoAgora(l, agora: t0.addingTimeInterval(10)) == 0)
    }

    @Test("Datas com frações longas")
    func datas() {
        #expect(AgentesDaIlha.data("2026-10-05T12:10:05.123Z") != nil)
        #expect(AgentesDaIlha.data("2026-10-05T12:10:05.123456Z") == AgentesDaIlha.data("2026-10-05T12:10:05.123Z"))
        #expect(AgentesDaIlha.data("2026-10-05T12:10:05Z") != nil)
        #expect(AgentesDaIlha.data("ontem") == nil)
    }

        @Test("Textos")
    func textos() {
        #expect(AgentesDaIlha.tokens(1_234_567) == "1,2 mi")
        #expect(AgentesDaIlha.tokens(350_900) == "350 mil")
        #expect(AgentesDaIlha.dolares(3.456) == "US$ 3,46")
        #expect(AgentesDaIlha.duracao(185) == "3 min")
        #expect(AgentesDaIlha.duracao(3900) == "1 h 05")
    }
}
