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

    @Test("O controle escolhe entre os dois materiais de vibrância")
    func escolheMaterial() {
        // Não é mais .glassEffect: medido em captura, ele só refrata conteúdo
        // dentro da própria janela, e a bandeja é um painel transparente sobre a
        // área de trabalho. Quem amostra atrás da janela é o NSVisualEffectView
        // com blendingMode .behindWindow.
        #expect(GlassTint.material(for: 0) == .translucido)
        #expect(GlassTint.material(for: 0.2) == .translucido)
        #expect(GlassTint.material(for: GlassTint.systemNeutral) == .fosco)
        #expect(GlassTint.material(for: 1) == .fosco)
    }

    @Test("O padrão é o escuro translúcido, como a barra do Dock")
    func padraoEFosco() {
        #expect(GlassTint.material(for: GlassTint.systemNeutral) == .fosco)
        #expect(GlassTint.overlayOpacity(GlassTint.systemNeutral) == 0)
        #expect(GlassTint.isSystemNeutral(GlassTint.systemNeutral))
    }

    @Test("Dois terços do controle não põem NADA por cima do vidro")
    func doisTercosSemTint() {
        // .glassEffect já obedece ao slider Liquid Glass do usuário. Somar tint
        // por cima aplicava a tonalização duas vezes, fechava o vidro e matava
        // o brilho de borda — verificado em captura, com e sem tint.
        #expect(GlassTint.overlayOpacity(GlassTint.systemNeutral) == 0)
        #expect(GlassTint.overlayOpacity(0.3) == 0)
        #expect(GlassTint.overlayOpacity(0.5) == 0)
        #expect(GlassTint.overlayOpacity(GlassTint.tintStart) == 0)
        #expect(GlassTint.isSystemNeutral(GlassTint.systemNeutral))
    }

    @Test("A tonalização só começa no terço final, e cresce até o teto")
    func cresceDepoisDoMeio() {
        let valores = [0.7, 0.8, 0.9, 1.0].map { GlassTint.overlayOpacity($0) }
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
