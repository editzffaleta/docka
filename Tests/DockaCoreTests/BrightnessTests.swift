import Testing
@testable import DockaCore

@Suite("Controle de brilho")
struct BrightnessTests {

    @Test("O nível anda na grade de 1/16 do sistema")
    func grade() {
        // guardar um valor fora da grade faria o modelo divergir do sistema
        // já no primeiro toque de tecla
        #expect(Brightness.quantize(0.5) == 0.5)
        #expect(Brightness.quantize(0.51) == 0.5)
        #expect(Brightness.quantize(0.5625) == 0.5625)   // já é um passo
        #expect(Brightness.quantize(0.55) == 0.5625)      // arredonda para o mais próximo
        #expect(Brightness.quantize(-1) == 0)
        #expect(Brightness.quantize(9) == 1)
    }

    @Test("A distância entre dois níveis vira a contagem de teclas")
    func passos() {
        #expect(Brightness.stepsBetween(from: 0.5, to: 0.5625) == 1)
        #expect(Brightness.stepsBetween(from: 0.5, to: 0.25) == -4)
        #expect(Brightness.stepsBetween(from: 0.5, to: 0.5) == 0)
        // do mínimo ao máximo são exatamente os 16 passos do sistema
        #expect(Brightness.stepsBetween(from: 0, to: 1) == Brightness.steps)
    }

    @Test("Aplicar passos é o inverso de contá-los")
    func idaEVolta() {
        for inicio in stride(from: 0.0, through: 1.0, by: 0.0625) {
            for alvo in stride(from: 0.0, through: 1.0, by: 0.0625) {
                let n = Brightness.stepsBetween(from: inicio, to: alvo)
                #expect(abs(Brightness.applying(n, to: inicio) - alvo) < 0.0001)
            }
        }
    }

    @Test("O nível nunca escapa de 0…1")
    func limites() {
        #expect(Brightness.applying(99, to: 0.5) == 1)
        #expect(Brightness.applying(-99, to: 0.5) == 0)
    }

    @Test("Cada toque de tecla cai sobre um traço da régua")
    func reguaAlinhada() {
        // 33 traços para 16 passos: o passo cai exatamente de 2 em 2 traços
        #expect((Brightness.tickCount - 1) % Brightness.steps == 0)
        #expect(Brightness.tickLevel(0) == 0)
        #expect(Brightness.tickLevel(Brightness.tickCount - 1) == 1)
    }

    @Test("A faixa acesa segue o nível e some longe dele")
    func faixaAcesa() {
        let meio = (Brightness.tickCount - 1) / 2
        let nivel = Brightness.tickLevel(meio)
        #expect(Brightness.tickHighlight(meio, level: nivel) == 1)
        #expect(Brightness.tickHighlight(meio + 1, level: nivel) > 0)
        #expect(Brightness.tickHighlight(0, level: nivel) == 0)
        #expect(Brightness.tickHighlight(Brightness.tickCount - 1, level: nivel) == 0)
    }

    @Test("O controle só aceita as laterais")
    func sóLaterais() {
        // a régua é vertical: deitada na borda inferior viraria outra coisa
        #expect(Brightness.bordasPermitidas == [.left, .right])
        #expect(Brightness.edge(persisted: "left") == .left)
        #expect(Brightness.edge(persisted: "right") == .right)
        #expect(Brightness.edge(persisted: "bottom") == .right)   // recai no padrão
        #expect(Brightness.edge(persisted: "xxx") == .right)
    }

    @Test("O arrasto fora da faixa não escapa de 0…1")
    func arrasto() {
        #expect(Brightness.clamp(-2) == 0)
        #expect(Brightness.clamp(2) == 1)
        #expect(Brightness.clamp(0.37) == 0.37)   // contínuo: o sistema aceita
    }
}
