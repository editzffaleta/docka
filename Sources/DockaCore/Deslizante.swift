import Foundation
import CoreGraphics

/// A matemática comum dos controles deslizantes de borda — brilho e volume.
///
/// Os dois são o mesmo objeto: régua vertical numa lateral, botão que corre
/// junto com o valor, arrasto suavizado, tique a cada degrau. Só mudam o que
/// leem e escrevem no sistema e o ícone. Tudo o que é geometria e curva mora
/// aqui, uma vez só; `Brightness` e `Volume` são as fachadas com os nomes de
/// cada um.
public enum Deslizante {

    /// O macOS move brilho e volume em 1/16 por toque de tecla.
    public static let steps = 16
    public static var stepSize: Double { 1.0 / Double(steps) }

    public static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    /// Encaixa no passo mais próximo: o sistema só assume múltiplos de 1/16,
    /// então guardar um valor fora da grade faria o modelo divergir na hora.
    public static func quantize(_ level: Double) -> Double {
        let n = (clamp(level) / stepSize).rounded()
        return clamp(n * stepSize)
    }

    /// Quantos passos (com sinal) levam de um nível a outro.
    public static func stepsBetween(from: Double, to: Double) -> Int {
        Int((clamp(to) - clamp(from)) / stepSize * 1.0000001)
    }

    /// Nível resultante depois de `n` passos.
    public static func applying(_ n: Int, to level: Double) -> Double {
        quantize(level + Double(n) * stepSize)
    }

    /// Estes controles só existem nas laterais: a régua é vertical por
    /// natureza, e deitada na borda inferior ela viraria outra coisa.
    public static let bordasPermitidas: [TrayEdge] = [.left, .right]

    public static func edge(persisted: String, padrao: TrayEdge) -> TrayEdge {
        let e = TrayEdge(persisted: persisted)
        return bordasPermitidas.contains(e) ? e : padrao
    }

    // MARK: geometria

    // Proporções medidas no controle de referência do usuário: a régua tem
    // ~13% da própria altura de espessura, e o botão é um pouco mais estreito
    // que ela.

    /// Comprimento da régua.
    public static let rulerLength: CGFloat = 280
    /// Espessura da régua — 13,5% do comprimento, como na referência.
    public static let rulerThickness: CGFloat = 38
    /// Diâmetro do botão.
    public static let knobSize: CGFloat = 34

    /// Tamanho do painel do controle: régua + botão ao lado.
    public static var panelExtent: CGFloat { rulerLength + 70 }
    public static var panelThickness: CGFloat { rulerThickness + knobSize + 46 }

    /// Folga entre dois controles que dividem a mesma lateral.
    public static let folgaEntreControles: CGFloat = 12

    /// Deslocamento do botão ao longo da régua para um nível.
    /// 0 no meio; negativo sobe (o eixo do SwiftUI cresce para baixo).
    public static func knobOffset(level: Double, rulerLength: CGFloat) -> CGFloat {
        (0.5 - clamp(level)) * rulerLength
    }

    /// Nível a partir da posição do botão — o inverso do de cima.
    public static func levelFromKnob(offset: CGFloat, rulerLength: CGFloat) -> Double {
        guard rulerLength > 0 else { return 0.5 }
        return clamp(0.5 - Double(offset / rulerLength))
    }

    // MARK: gesto

    /// Quantos pontos de arrasto cobrem a faixa inteira.
    public static let dragSpan: CGFloat = 250
    /// Distância a partir da qual um toque vira arrasto, e não clique.
    public static let dragThreshold: CGFloat = 3

    /// Nível ao esfregar: para CIMA aumenta (translation.height é negativo).
    public static func scrub(from inicio: Double, translation: CGFloat) -> Double {
        clamp(inicio - Double(translation / dragSpan))
    }

    /// O gesto foi um toque, e não um arrasto?
    ///
    /// O botão acumula dois papéis, e é isto que os separa. Ficou de fora numa
    /// reescrita e o clique parou de funcionar — por isso mora aqui, com teste,
    /// em vez de ser um `if` solto na view.
    public static func isTap(translation: CGFloat) -> Bool {
        abs(translation) <= dragThreshold
    }

    /// Suavização do arrasto: o nível caminha esta fração da distância até o
    /// alvo em cada evento, em vez de saltar direto.
    ///
    /// Sem isso o controle fica nervoso — cada micro-movimento do mouse vira um
    /// degrau. Com 0,35 o valor persegue o cursor em ~3 quadros, o que some
    /// para o olho e tira o solavanco.
    public static let dragSmoothing: Double = 0.35

    /// Um passo do arrasto suavizado, a partir do nível do INÍCIO do gesto.
    ///
    /// A referência é o início, não o valor corrente: calcular a partir do
    /// corrente realimenta a conta — o botão se move, o cursor passa a estar
    /// noutra posição relativa a ele, e o valor dispara.
    public static func dragStep(inicio: Double, translation: CGFloat,
                                atual: Double, span: CGFloat) -> Double {
        let alvo = clamp(inicio - Double(translation / max(span, 1)))
        return clamp(atual + (alvo - atual) * dragSmoothing)
    }

    /// O que o botão mostra enquanto arrasta.
    public static func knobLabel(level: Double) -> String {
        "\(Int((clamp(level) * 100).rounded()))"
    }

    /// Passou de um degrau de 1/16 para outro?
    ///
    /// É o que decide o tique: um som por evento de arrasto viraria metralhadora
    /// (são dezenas por segundo), e um som por gesto não daria a sensação de
    /// escala. Um por degrau é o que o próprio macOS faz no volume.
    public static func crossedStep(from: Double, to: Double) -> Bool {
        let a = (clamp(from) / stepSize).rounded(.down)
        let b = (clamp(to) / stepSize).rounded(.down)
        return a != b
    }

    // MARK: régua

    /// Quantidade de traços. Múltiplo dos passos para cada toque de tecla cair
    /// exatamente sobre um traço.
    public static let tickCount = 33

    /// Nível (0…1) representado pelo traço `i`, de baixo para cima.
    public static func tickLevel(_ i: Int) -> Double {
        Double(i) / Double(tickCount - 1)
    }

    /// Traços destacados perto do nível — é o que forma a faixa acesa.
    /// Devolve 0…1: 1 no traço do nível, caindo até sumir.
    public static func tickHighlight(_ i: Int, level: Double) -> Double {
        let d = abs(tickLevel(i) - clamp(level))
        let alcance = 2.5 * (1.0 / Double(tickCount - 1))
        return max(0, 1 - d / alcance)
    }

    /// Traço longo a cada 4 — a marcação graúda da régua da referência.
    public static func isMajorTick(_ i: Int) -> Bool { i % 4 == 0 }

    /// Nível a partir da posição do arrasto na régua (0 na base, 1 no topo).
    public static func levelFromDrag(fraction: Double) -> Double {
        quantize(clamp(fraction))
    }

    // MARK: convivência entre dois controles

    /// Afasta `quadro` de `ocupado` quando os dois cairiam um sobre o outro.
    ///
    /// Brilho e volume podem ser postos na mesma lateral e na mesma posição —
    /// e aí um cobriria o outro, sem nenhum aviso ao usuário. Em vez de proibir
    /// a combinação nos ajustes, o segundo painel se acomoda: desce para logo
    /// abaixo do primeiro e, se não couber, sobe para logo acima. Se não couber
    /// de nenhum lado, fica onde estava — encavalado é ruim, fora da tela é pior.
    public static func desviar(_ quadro: CGRect, de ocupado: CGRect?,
                               dentro tela: CGRect) -> CGRect {
        guard let ocupado, quadro.intersects(ocupado) else { return quadro }

        var abaixo = quadro
        abaixo.origin.y = ocupado.minY - quadro.height - folgaEntreControles
        if abaixo.minY >= tela.minY { return abaixo }

        var acima = quadro
        acima.origin.y = ocupado.maxY + folgaEntreControles
        if acima.maxY <= tela.maxY { return acima }

        return quadro
    }
}
