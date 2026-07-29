import Testing
@testable import DockaCore

@Suite("Aparência da bandeja")
struct TrayAppearanceTests {

    @Test("Um valor persistido desconhecido cai no automático")
    func valorDesconhecidoCaiNoAutomatico() {
        // a preferência é gravada como string livre
        #expect(TrayAppearance(persisted: "sepia") == .automatico)
        #expect(TrayAppearance(persisted: "") == .automatico)
        #expect(TrayAppearance(persisted: "escuro") == .escuro)
        #expect(TrayAppearance(persisted: "claro") == .claro)
    }

    @Test("Os três modos do sistema estão cobertos")
    func tresModos() {
        #expect(TrayAppearance.allCases.count == 3)
        #expect(TrayAppearance.allCases.allSatisfy { !$0.titulo.isEmpty })
    }
}

@Suite("Tonalização do vidro")
struct GlassTintTests {

    @Test("A ponta esquerda do controle usa o vidro transparente")
    func pontaEsquerdaEClear() {
        #expect(GlassTint.usesClearGlass(0))
        #expect(GlassTint.usesClearGlass(0.05))
        #expect(!GlassTint.usesClearGlass(0.5))
        #expect(!GlassTint.usesClearGlass(1))
    }

    @Test("O meio do controle não põe NADA por cima do vidro do sistema")
    func meioNaoTonaliza() {
        // Este é o conserto: .glassEffect(.regular) já obedece ao slider Liquid
        // Glass do usuário. Somar tint por cima aplicava a tonalização duas
        // vezes, fechava o vidro e matava o brilho de borda.
        #expect(GlassTint.overlayOpacity(GlassTint.systemNeutral) == 0)
        #expect(GlassTint.overlayOpacity(0.3) == 0)
        #expect(GlassTint.overlayOpacity(0.5) == 0)
        #expect(GlassTint.isSystemNeutral(0.5))
        #expect(GlassTint.isSystemNeutral(0.3))
    }

    @Test("A tonalização só começa depois do meio, e cresce até o teto")
    func cresceDepoisDoMeio() {
        let valores = [0.6, 0.7, 0.8, 0.9, 1.0].map { GlassTint.overlayOpacity($0) }
        for (a, b) in zip(valores, valores.dropFirst()) {
            #expect(a < b)
        }
        #expect(abs(GlassTint.overlayOpacity(1) - GlassTint.maxOverlay) < 0.0001)
    }

    @Test("O teto do tint é baixo o bastante para a borda sobreviver")
    func tetoPreservaABorda() {
        // acima de ~0,25 o brilho especular da borda desaparece — foi medido
        // em captura, comparando com e sem tint
        #expect(GlassTint.maxOverlay <= 0.25)
    }

    @Test("O vidro nunca fecha a ponto de virar um retângulo sólido")
    func nuncaFechaTotalmente() {
        // passar disso deixa de ser vidro e vira fundo
        for v in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(GlassTint.overlayOpacity(v) <= GlassTint.maxOverlay)
        }
        #expect(GlassTint.maxOverlay < 0.5)
    }

    @Test("Valores fora da faixa não quebram a conta")
    func foraDaFaixa() {
        // o slider é 0…1, mas o valor vem do UserDefaults e pode estar corrompido
        #expect(GlassTint.overlayOpacity(-3) == 0)
        #expect(abs(GlassTint.overlayOpacity(9) - GlassTint.maxOverlay) < 0.0001)
        #expect(GlassTint.usesClearGlass(-1))
    }
}
