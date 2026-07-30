import Testing
import CoreGraphics
@testable import DockaCore

@Suite("Controle de volume")
struct VolumeTests {

    @Test("O ícone acompanha o nível, como no menu de som do macOS")
    func iconePorNivel() {
        // é o que diferencia o botão do volume do sol do brilho: aqui o ícone
        // informa, porque volume zero e volume baixo se confundem
        #expect(Volume.simbolo(level: 0) == "speaker.slash.fill")
        #expect(Volume.simbolo(level: 0.2) == "speaker.wave.1.fill")
        #expect(Volume.simbolo(level: 0.5) == "speaker.wave.2.fill")
        #expect(Volume.simbolo(level: 1) == "speaker.wave.3.fill")
    }

    @Test("Só o zero exato conta como mudo")
    func mudoSoNoZero() {
        #expect(Volume.mudo(level: 0))
        #expect(!Volume.mudo(level: 0.01))
        #expect(Volume.mudo(level: -1))     // fora da faixa, o clamp resolve
    }

    @Test("O volume nasce na lateral oposta à do brilho")
    func bordaPadraoOposta() {
        // sem isso, ligar o segundo controle sem mexer em posição colocaria os
        // dois exatamente um sobre o outro
        #expect(Volume.edge(persisted: "") == .left)
        #expect(Brightness.edge(persisted: "") == .right)
        // e a borda inferior nunca é aceita: a régua é vertical
        #expect(Volume.edge(persisted: "bottom") == .left)
        #expect(Volume.edge(persisted: "right") == .right)
    }

    @Test("A matemática é a mesma do brilho — é a mesma peça")
    func mesmaCurvaDoBrilho() {
        #expect(Volume.knobOffset(level: 0.75, rulerLength: 280)
                == Brightness.knobOffset(level: 0.75, rulerLength: 280))
        #expect(Volume.dragStep(inicio: 0.5, translation: -40, atual: 0.5, span: 280)
                == Brightness.dragStep(inicio: 0.5, translation: -40, atual: 0.5, span: 280))
        #expect(Volume.quantize(0.53) == Brightness.quantize(0.53))
    }
}

@Suite("Convivência de dois controles na mesma lateral")
struct DesvioTests {
    private let tela = CGRect(x: 0, y: 0, width: 1710, height: 1112)
    private func painel(y: CGFloat) -> CGRect {
        CGRect(x: 1592, y: y, width: 118, height: 350)
    }

    @Test("Sem colisão, o quadro fica exatamente onde foi pedido")
    func semColisaoNaoMexe() {
        let q = painel(y: 100)
        #expect(Deslizante.desviar(q, de: nil, dentro: tela) == q)
        #expect(Deslizante.desviar(q, de: painel(y: 600), dentro: tela) == q)
    }

    @Test("Colidindo, o segundo desce para logo abaixo do primeiro")
    func desceQuandoColide() {
        let ocupado = painel(y: 381)
        let r = Deslizante.desviar(painel(y: 381), de: ocupado, dentro: tela)
        #expect(!r.intersects(ocupado))
        #expect(r.maxY == ocupado.minY - Deslizante.folgaEntreControles)
        #expect(r.minY >= tela.minY)
    }

    @Test("Se não couber embaixo, sobe para cima do primeiro")
    func sobeQuandoNaoCabeEmbaixo() {
        // primeiro painel colado na base: abaixo dele não há 350 pt livres
        let ocupado = painel(y: 10)
        let r = Deslizante.desviar(painel(y: 10), de: ocupado, dentro: tela)
        #expect(!r.intersects(ocupado))
        #expect(r.minY == ocupado.maxY + Deslizante.folgaEntreControles)
        #expect(r.maxY <= tela.maxY)
    }

    @Test("Sem espaço dos dois lados, fica onde estava")
    func semEspacoNaoInventa() {
        // encavalado é ruim; fora da tela é pior — e some sem explicação
        let telinha = CGRect(x: 0, y: 0, width: 800, height: 400)
        let ocupado = CGRect(x: 700, y: 25, width: 118, height: 350)
        let pedido = CGRect(x: 700, y: 25, width: 118, height: 350)
        #expect(Deslizante.desviar(pedido, de: ocupado, dentro: telinha) == pedido)
    }
}

@Suite("Mudo pelo toque")
struct MudoTests {

    @Test("Tocar com som guarda o nível e silencia")
    func mutaGuardando() {
        let r = Volume.alternarMudo(atual: 0.7, guardado: 0.3)
        #expect(r.novo == 0)
        #expect(r.guardar == 0.7)
    }

    @Test("Tocar no mudo volta ao nível guardado")
    func desmutaParaOGuardado() {
        let r = Volume.alternarMudo(atual: 0, guardado: 0.7)
        #expect(r.novo == 0.7)
    }

    @Test("Desmutar sem nível guardado audível vai a 50%")
    func desmutarSemGuardadoVaiAMeio() {
        // desmutar para o silêncio seria um botão que não faz nada
        #expect(Volume.alternarMudo(atual: 0, guardado: 0).novo == 0.5)
        #expect(Volume.alternarMudo(atual: 0, guardado: -1).novo == 0.5)
    }

    @Test("Ida e volta preserva o nível original")
    func idaEVolta() {
        let mutado = Volume.alternarMudo(atual: 0.65, guardado: 0)
        let devolta = Volume.alternarMudo(atual: mutado.novo, guardado: mutado.guardar)
        #expect(devolta.novo == 0.65)
    }
}
