import Testing
import CoreGraphics
@testable import DockaCore

@Suite("Curva de ampliação")
struct MagnificationTests {

    @Test("Sob o cursor, o ícone atinge exatamente o pico")
    func peakUnderCursor() {
        #expect(Magnification.scale(distance: 0, maxBoost: 0.75) == 1.75)
    }

    @Test("Longe do cursor, o ícone volta praticamente ao tamanho normal")
    func decaysToOne() {
        let far = Magnification.scale(distance: 400, maxBoost: 0.75)
        #expect(far > 1)                 // a gaussiana nunca chega a zero…
        #expect(far < 1.001)             // …mas some na prática
    }

    @Test("A escala cai conforme o ícone se afasta do cursor")
    func monotonicDecay() {
        let distances: [CGFloat] = [0, 20, 40, 64, 100, 160]
        let scales = distances.map { Magnification.scale(distance: $0, maxBoost: 0.75) }
        for (a, b) in zip(scales, scales.dropFirst()) {
            #expect(a > b)
        }
    }

    @Test("A curva é simétrica dos dois lados do cursor")
    func symmetric() {
        // o chamador passa abs(hoverX - frameX); um sinal trocado não pode
        // produzir ampliação diferente
        #expect(Magnification.scale(distance: 30, maxBoost: 0.75)
                == Magnification.scale(distance: -30, maxBoost: 0.75))
    }

    @Test("Ampliação zerada desliga o efeito por completo")
    func boostZeroDisables() {
        // é o valor que o slider "Ampliação: Desativada" grava
        #expect(Magnification.scale(distance: 0, maxBoost: 0) == 1)
        #expect(Magnification.scale(distance: 50, maxBoost: 0) == 1)
        #expect(!Magnification.isMagnified(scale: 1, maxBoost: 0))
    }

    @Test("O balão de nome aparece sob o cursor e não nos vizinhos distantes")
    func labelOnlyNearCursor() {
        let boost: CGFloat = 0.75
        let under = Magnification.scale(distance: 0, maxBoost: boost)
        let neighbor = Magnification.scale(distance: 90, maxBoost: boost)
        #expect(Magnification.isMagnified(scale: under, maxBoost: boost))
        #expect(!Magnification.isMagnified(scale: neighbor, maxBoost: boost))
    }

    @Test("O alcance da curva acompanha o sigma")
    func sigmaSetsReach() {
        // a um sigma de distância a gaussiana vale e^(-0.5) ≈ 0.6065
        let atSigma = Magnification.scale(distance: Magnification.sigma, maxBoost: 1)
        #expect(abs(atSigma - 1.6065) < 0.001)
    }
}
