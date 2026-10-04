import Foundation

/// Os ajustes do mouse.
public struct AjustesDeRolagem: Equatable, Sendable {
    public var inverterVertical: Bool
    public var inverterHorizontal: Bool
    /// Linhas por dente da roda; `nil` = a aceleração do sistema.
    public var linhasPorDente: Int?
    /// Modificador que transforma rolagem vertical em horizontal.
    public var deLado: Shortcut.Modifiers?

    public init(inverterVertical: Bool = false, inverterHorizontal: Bool = false,
                linhasPorDente: Int? = nil, deLado: Shortcut.Modifiers? = nil) {
        self.inverterVertical = inverterVertical
        self.inverterHorizontal = inverterHorizontal
        self.linhasPorDente = linhasPorDente
        self.deLado = deLado
    }
}

/// Um evento de rolagem, só com o que a transformação precisa.
public struct Rolada: Equatable, Sendable {
    /// Em linhas (o que a roda manda) — positivo = para cima/esquerda.
    public var linhasY: Int64
    public var linhasX: Int64
    /// Em pontos: o que os apps de fato usam para rolar.
    public var pontosY: Double
    public var pontosX: Double

    public init(linhasY: Int64, linhasX: Int64, pontosY: Double, pontosX: Double) {
        self.linhasY = linhasY
        self.linhasX = linhasX
        self.pontosY = pontosY
        self.pontosX = pontosX
    }
}

public enum Rolagem {

    /// Pontos por linha, para a rolagem linear: o que o macOS usa na roda
    /// sem aceleração.
    public static let pontosPorLinha: Double = 10

    /// Aplica os ajustes a uma rolada da RODA do mouse.
    ///
    /// O trackpad nunca passa por aqui: quem chama separa pelo campo
    /// "contínuo" do evento. Inverter o trackpad junto seria justamente o que
    /// o ajuste do sistema já faz — e o que a pessoa quer evitar.
    public static func transformar(_ r: Rolada, com a: AjustesDeRolagem,
                                   modificadores: Shortcut.Modifiers) -> Rolada {
        var s = r
        if let n = a.linhasPorDente, n > 0 {
            // um dente vale sempre n linhas, por mais rápido que se gire
            s.linhasY = Int64(sinal(r.linhasY)) * Int64(n)
            s.linhasX = Int64(sinal(r.linhasX)) * Int64(n)
            s.pontosY = Double(s.linhasY) * pontosPorLinha
            s.pontosX = Double(s.linhasX) * pontosPorLinha
        }
        if a.inverterVertical { s.linhasY.negate(); s.pontosY.negate() }
        if a.inverterHorizontal { s.linhasX.negate(); s.pontosX.negate() }
        if let tecla = a.deLado, !tecla.isEmpty, modificadores.isSuperset(of: tecla), s.linhasX == 0 {
            // vertical vira horizontal, e o vertical zera — senão rola em diagonal
            s.linhasX = s.linhasY; s.pontosX = s.pontosY
            s.linhasY = 0; s.pontosY = 0
        }
        return s
    }

    private static func sinal(_ v: Int64) -> Int { v > 0 ? 1 : (v < 0 ? -1 : 0) }

    // MARK: rolagem suave

    /// Quanto dura o deslize de um dente.
    public static let duracaoSuave: Double = 0.18
    /// Quadros por segundo do deslize.
    public static let quadrosPorSegundo: Double = 120

    /// Reparte uma distância em passos com desaceleração (começa rápido e
    /// assenta), como a inércia do trackpad. A soma dá a distância exata —
    /// arredondar quadro a quadro faria a página andar a menos.
    public static func passosSuaves(distancia: Double, quadros: Int) -> [Double] {
        guard quadros > 0 else { return [distancia] }
        // ease-out cúbico: posição(t) = 1 - (1 - t)³
        func posicao(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
        var passos: [Double] = []
        var andado = 0.0
        for i in 1...quadros {
            let alvo = distancia * posicao(Double(i) / Double(quadros))
            passos.append(alvo - andado)
            andado = alvo
        }
        return passos
    }

    // MARK: botões laterais

    /// O que um botão lateral faz: voltar ou avançar. O número costuma ser 3
    /// para voltar e 4 para avançar. Botão já usado pela Órbita fica com ela.
    public enum Navegacao: Equatable, Sendable { case voltar, avancar }

    public static func navegacao(botao: Int, botaoDaOrbita: Int) -> Navegacao? {
        guard botao != botaoDaOrbita else { return nil }
        switch botao {
        case 3: return .voltar
        case 4: return .avancar
        default: return nil
        }
    }
}
