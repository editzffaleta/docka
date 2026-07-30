import Foundation
import CoreGraphics

/// Canto da tela que abre a órbita.
public enum CantoDaTela: String, CaseIterable, Sendable {
    case superiorEsquerdo, superiorDireito, inferiorEsquerdo, inferiorDireito

    public var titulo: String {
        switch self {
        case .superiorEsquerdo: return "Superior esquerdo"
        case .superiorDireito:  return "Superior direito"
        case .inferiorEsquerdo: return "Inferior esquerdo"
        case .inferiorDireito:  return "Inferior direito"
        }
    }
}

/// A órbita: os apps em volta do cursor, num anel.
///
/// **Sobre o gatilho.** A referência abre o anel com um gesto de mouse em
/// qualquer lugar da tela. Capturar gesto global exige a permissão de
/// Monitoramento de Entrada, e a regra do projeto é não pedir permissão
/// nenhuma. Os dois gatilhos aqui vivem dentro dessa regra: o atalho global
/// (Carbon, sem permissão) e o canto da tela, que sai da mesma leitura de
/// posição do cursor que já revela a bandeja.
public enum Orbita {

    /// Lado do ícone no anel.
    public static let tamanhoItem: CGFloat = 52
    /// Quanto o ícone sob o cursor cresce.
    public static let ampliacao: CGFloat = 1.35
    /// Buraco no meio: é a zona morta, onde nada é selecionado.
    ///
    /// Sem ela, o anel escolheria alguma coisa já no instante em que aparece,
    /// com o cursor parado no centro — e um clique sem querer lançaria um app.
    public static let raioInterno: CGFloat = 74

    /// Raio onde os ícones ficam.
    ///
    /// Cresce com a quantidade para os ícones não encostarem uns nos outros: o
    /// perímetro precisa comportar todos com folga.
    public static func raio(total: Int) -> CGFloat {
        let n = max(1, total)
        let passoMinimo = tamanhoItem * 1.45
        let porPerimetro = CGFloat(n) * passoMinimo / (2 * .pi)
        return max(raioInterno + tamanhoItem * 0.75, porPerimetro)
    }

    /// Lado do painel que comporta o anel inteiro, já com a ampliação.
    public static func tamanhoDoPainel(total: Int) -> CGFloat {
        2 * (raio(total: total) + tamanhoItem * ampliacao / 2) + 24
    }

    /// Ângulo do item `i`, em radianos, medido a partir do topo e no sentido
    /// horário — a leitura natural de um mostrador.
    public static func angulo(indice i: Int, total: Int) -> CGFloat {
        let n = max(1, total)
        return -.pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(n)
    }

    /// Posição do item em relação ao centro, no eixo do SwiftUI (y para baixo).
    public static func posicao(indice i: Int, total: Int) -> CGPoint {
        let a = angulo(indice: i, total: total)
        let r = raio(total: total)
        return CGPoint(x: cos(a) * r, y: sin(a) * r)
    }

    /// Qual item o cursor está apontando, se algum.
    ///
    /// Vale a DIREÇÃO, não a distância: basta apontar para fora da zona morta
    /// que o item daquele setor acende, esteja o cursor no anel ou além dele.
    /// É o que torna a órbita rápida — não é preciso acertar o ícone.
    public static func indiceSob(_ ponto: CGPoint, total: Int) -> Int? {
        let n = max(1, total)
        let d = sqrt(ponto.x * ponto.x + ponto.y * ponto.y)
        guard d >= raioInterno else { return nil }

        // ângulo do cursor na mesma referência dos itens
        var a = atan2(ponto.y, ponto.x) + .pi / 2
        let volta = 2 * CGFloat.pi
        a = a.truncatingRemainder(dividingBy: volta)
        if a < 0 { a += volta }

        let setor = volta / CGFloat(n)
        let i = Int((a / setor).rounded()) % n
        return i
    }

    /// Escala do item, para o apontado crescer como no Dock.
    public static func escala(indice i: Int, apontado: Int?) -> CGFloat {
        i == apontado ? ampliacao : 1
    }

    // MARK: gatilho de canto

    /// Quão perto da quina o cursor precisa chegar.
    ///
    /// Poucos pontos, de propósito: o canto também é território das Hot Corners
    /// do próprio macOS, e uma zona larga roubaria o gesto de quem as usa.
    public static let alcanceDoCanto: CGFloat = 4

    /// O cursor está cravado neste canto? `tela` em coordenadas do AppKit.
    public static func noCanto(_ canto: CantoDaTela, cursor: CGPoint,
                              tela: CGRect) -> Bool {
        let f = alcanceDoCanto
        switch canto {
        case .superiorEsquerdo:
            return cursor.x <= tela.minX + f && cursor.y >= tela.maxY - f
        case .superiorDireito:
            return cursor.x >= tela.maxX - f && cursor.y >= tela.maxY - f
        case .inferiorEsquerdo:
            return cursor.x <= tela.minX + f && cursor.y <= tela.minY + f
        case .inferiorDireito:
            return cursor.x >= tela.maxX - f && cursor.y <= tela.minY + f
        }
    }

    /// Onde o painel da órbita deve ficar para o centro cair no cursor.
    ///
    /// Preso à tela: aberto num canto, o anel sairia pela borda e metade dos
    /// itens ficaria fora do alcance do mouse.
    public static func quadro(centro: CGPoint, total: Int, tela: CGRect) -> CGRect {
        let lado = tamanhoDoPainel(total: total)
        var x = centro.x - lado / 2
        var y = centro.y - lado / 2
        x = min(max(x, tela.minX), tela.maxX - lado)
        y = min(max(y, tela.minY), tela.maxY - lado)
        return CGRect(x: x, y: y, width: lado, height: lado)
    }
}
