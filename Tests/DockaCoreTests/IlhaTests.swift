import Testing
import Foundation
import CoreGraphics
@testable import DockaCore

@Suite("Ilha Dinâmica")
struct IlhaTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    /// A tela do MacBook Air de 15": as medidas reais do recorte.
    private let tela = CGRect(x: 0, y: 0, width: 1710, height: 1112)
    private var geo: Ilha.Geometria {
        Ilha.Geometria(tela: tela,
                       areaEsquerda: CGRect(x: 0, y: 1074.5, width: 751, height: 37.5),
                       areaDireita: CGRect(x: 959, y: 1074.5, width: 751, height: 37.5),
                       alturaDaBarra: 38)
    }

    @Test("Recorte tirado das áreas da barra de menus")
    func recorte() {
        #expect(geo.temRecorte)
        #expect(geo.recorte == CGRect(x: 751, y: 1074.5, width: 208, height: 37.5))
        // cresce para baixo e para os lados, sem sair do topo
        #expect(geo.pairando.maxY == tela.maxY)
        #expect(geo.pairando.width == 236, "largura \(geo.pairando.width)")
        #expect(geo.compacta.midX == geo.recorte.midX)
    }

    @Test("Sem recorte: ilha simulada no meio, da altura da barra")
    func simulada() {
        let g = Ilha.Geometria(tela: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                               areaEsquerda: nil, areaDireita: nil, alturaDaBarra: 25)
        #expect(!g.temRecorte)
        #expect(g.recorte == CGRect(x: 865, y: 1055, width: 190, height: 25))
    }

    @Test("Aberta: centrada no recorte, colada no topo; botões fora dela")
    func aberta() {
        let a = geo.aberta(altura: 300)
        #expect(a.maxY == tela.maxY)
        #expect(a.midX == geo.recorte.midX)
        #expect(a.height == 337.5)
        let b0 = geo.botao(0, esquerda: true, aberta: a)
        #expect(b0.maxX < a.minX)
        let d1 = geo.botao(1, esquerda: false, aberta: a)
        #expect(d1.minX > a.maxX)
        #expect(d1.maxY < geo.botao(0, esquerda: false, aberta: a).minY)
    }

    @Test("Vigia: cresce ao passar, abre parado, recolhe ao sair")
    func vigia() {
        var v = Ilha.Vigia()
        #expect(v.leu(sobreAIlha: true, em: t(0), abrirAoPairar: 0.4) == .pairar)
        #expect(v.leu(sobreAIlha: true, em: t(0.2), abrirAoPairar: 0.4) == .nada)
        #expect(v.leu(sobreAIlha: true, em: t(0.4), abrirAoPairar: 0.4) == .abrir)
        // aberta: sair conta a folga
        #expect(v.leu(sobreAIlha: false, em: t(1), abrirAoPairar: 0.4) == .nada)
        #expect(v.leu(sobreAIlha: false, em: t(1.6), abrirAoPairar: 0.4) == .fechar)

        // só passando: cresce e recolhe sem abrir
        var p = Ilha.Vigia()
        _ = p.leu(sobreAIlha: true, em: t(0), abrirAoPairar: 0.4)
        #expect(p.leu(sobreAIlha: false, em: t(0.1), abrirAoPairar: 0.4) == .recolher)
        #expect(p.estado == .fechada)
    }

    @Test("Vigia: sem abrir ao pairar, só o clique abre; fixada não fecha")
    func vigiaClique() {
        var v = Ilha.Vigia()
        _ = v.leu(sobreAIlha: true, em: t(0), abrirAoPairar: nil)
        #expect(v.leu(sobreAIlha: true, em: t(5), abrirAoPairar: nil) == .nada)
        #expect(v.clicou() == .abrir)
        #expect(v.leu(sobreAIlha: false, em: t(6), abrirAoPairar: nil, fixada: true) == .nada)
        #expect(v.leu(sobreAIlha: false, em: t(9), abrirAoPairar: nil, fixada: true) == .nada)
        #expect(v.clicou() == .fechar)
    }

    @Test("Atividades: a de maior prioridade; combinadas, as duas; a escolhida na frente")
    func atividades() {
        let timer = Ilha.Atividade(id: "timer", tipo: .timer, simbolo: "timer", valor: "14m", prioridade: 60)
        let musica = Ilha.Atividade(id: "musica", tipo: .musica, simbolo: "music.note", valor: "", prioridade: 40)
        let baixando = Ilha.Atividade(id: "dl", tipo: .download, simbolo: "arrow.down", valor: "40%", prioridade: 30)
        #expect(Ilha.visiveis([musica, timer, baixando], combinar: false).map(\.id) == ["timer"])
        #expect(Ilha.visiveis([musica, timer, baixando], combinar: true).map(\.id) == ["timer", "musica"])
        #expect(Ilha.visiveis([musica, timer], combinar: false, escolhida: "musica").map(\.id) == ["musica"])
    }

    @Test("Ordem gravada: sem repetidas nem desconhecidas, novas no fim")
    func ordem() {
        let o = Ilha.ordem(gravada: ["timer", "lixo", "timer", "musica"])
        #expect(Array(o.prefix(2)) == [.timer, .musica])
        #expect(o.count == Ilha.Secao.allCases.count)
    }
}

@Suite("Timer da ilha")
struct TimerDaIlhaTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test("Temporizador: corre, pausa, retoma e termina uma vez")
    func temporizador() {
        var x = TimerDaIlha()
        x.minutos = 15
        x.iniciar(em: t(0))
        #expect(x.restante(em: t(60)) == 840)
        x.pausar(em: t(60))
        #expect(x.restante(em: t(500)) == 840)          // pausado não anda
        x.iniciar(em: t(500))
        #expect(x.restante(em: t(560)) == 780)
        #expect(x.conferir(em: t(1000)) == nil)
        #expect(x.conferir(em: t(1340)) == .foco)       // 500 + 840
        #expect(x.corrida == .parado)
        #expect(x.conferir(em: t(1400)) == nil)
    }

    @Test("Pomodoro: foco, pausa, e a pausa longa depois de quatro focos")
    func pomodoro() {
        var x = TimerDaIlha()
        x.modo = .pomodoro
        x.iniciar(em: t(0))
        var tempo: Double = 0
        var fases: [TimerDaIlha.FaseDoPomodoro] = []
        for _ in 0..<8 {
            tempo += x.duracao
            if let f = x.conferir(em: t(tempo)) { fases.append(f) }
            fases.append(x.fase)
        }
        // terminou foco → começou pausa, …, o 4º foco leva à pausa longa
        #expect(fases == [.foco, .pausa, .pausa, .foco, .foco, .pausa, .pausa, .foco,
                          .foco, .pausa, .pausa, .foco, .foco, .pausaLonga, .pausaLonga, .foco])
    }

    @Test("Tique atrasado não come tempo da fase seguinte")
    func tiqueAtrasado() {
        var x = TimerDaIlha()
        x.modo = .pomodoro
        x.iniciar(em: t(0))
        _ = x.conferir(em: t(25 * 60 + 30))            // conferiu 30 s depois do fim
        #expect(x.restante(em: t(25 * 60 + 30)) == 5 * 60 - 30)
    }

    @Test("Cronômetro: soma os trechos, guarda voltas")
    func cronometro() {
        var x = TimerDaIlha()
        x.modo = .cronometro
        x.alternarCronometro(em: t(0))
        x.volta(em: t(10))
        x.alternarCronometro(em: t(15))                 // pausa com 15 s
        #expect(x.decorrido(em: t(100)) == 15)
        x.alternarCronometro(em: t(100))
        #expect(x.decorrido(em: t(105)) == 20)
        #expect(x.voltas == [10])
        x.zerarCronometro()
        #expect(!x.ativo)
    }

    @Test("Textos: relógio, cronômetro e curto")
    func textos() {
        #expect(TimerDaIlha.relogio(900) == "15:00")
        #expect(TimerDaIlha.relogio(3723) == "1:02:03")
        #expect(TimerDaIlha.relogio(0.2) == "0:01")     // arredonda para cima: nunca mostra 0:00 correndo
        #expect(TimerDaIlha.cronometro(65.37) == "1:05,3")
        #expect(TimerDaIlha.curto(45) == "45s")
        #expect(TimerDaIlha.curto(13 * 60 + 10) == "14m")
        #expect(TimerDaIlha.curto(65 * 60) == "1h 05")
    }

    @Test("Atividade ao vivo só com algo correndo")
    func atividade() {
        var x = TimerDaIlha()
        #expect(x.atividade(em: t(0)) == nil)
        x.iniciar(em: t(0))
        let a = x.atividade(em: t(60))
        #expect(a?.valor == "14m")
        #expect(a?.tipo == .timer)
    }
}
