import Foundation
import CoreGraphics

/// A prévia do Dock: parar o cursor num ícone de app mostra as janelas dele.
///
/// O vigia decide quando mostrar e quando esconder, leitura a leitura; a
/// posição põe o painel do lado do ícone que dá para o meio da tela.
public enum PreviaDoDock {

    /// De que lado da tela o Dock mora — tirado do próprio ícone, que fica
    /// encostado na borda dele.
    public enum Borda: Equatable, Sendable { case baixo, esquerda, direita }

    public struct Vigia: Sendable {
        public enum Acao: Equatable, Sendable {
            case nada
            case mostrar(String)
            case esconder
        }

        public private(set) var mostrando: String?
        private var alvo: String?
        private var desde: Date?
        private var foraDesde: Date?
        /// Ícone clicado: não volta a mostrar até o cursor sair dele.
        private var suprimido: String?

        public init() {}

        /// - Parameters:
        ///   - icone: o ícone de app sob o cursor (nil fora do Dock).
        ///   - sobreOPainel: o cursor está em cima da prévia aberta.
        ///   - atraso: quanto tempo parado no ícone até mostrar.
        ///   - folga: quanto tempo fora do ícone e da prévia até esconder —
        ///     dá para atravessar o vão entre os dois.
        ///   - troca: com a prévia aberta, quanto tempo parado noutro ícone
        ///     até trocar de app. Curto, mas não zero: levar o cursor em
        ///     diagonal até a prévia passa por cima dos ícones vizinhos.
        public mutating func leu(icone: String?, sobreOPainel: Bool, em agora: Date,
                                 atraso: TimeInterval, folga: TimeInterval = 0.4,
                                 troca: TimeInterval = 0.2) -> Acao {
            if sobreOPainel, mostrando != nil {
                foraDesde = nil
                return .nada
            }
            guard let icone else {
                alvo = nil; desde = nil; suprimido = nil
                guard mostrando != nil else { return .nada }
                guard let fora = foraDesde else { foraDesde = agora; return .nada }
                guard agora.timeIntervalSince(fora) >= folga else { return .nada }
                mostrando = nil; foraDesde = nil
                return .esconder
            }
            foraDesde = nil
            if icone == suprimido { return .nada }
            suprimido = nil
            if icone == mostrando { return .nada }
            // com a prévia aberta, a troca para outro app pede bem menos tempo
            let espera = mostrando != nil ? min(troca, atraso) : atraso
            if icone != alvo {
                alvo = icone; desde = agora
                return espera <= 0 ? mostrar(icone) : .nada
            }
            if let d = desde, agora.timeIntervalSince(d) >= espera { return mostrar(icone) }
            return .nada
        }

        private mutating func mostrar(_ icone: String) -> Acao {
            mostrando = icone
            return .mostrar(icone)
        }

        /// Clique no ícone (o Dock vai abrir ou trazer o app): some com a
        /// prévia e não a reabre enquanto o cursor ficar ali.
        public mutating func clicou(icone: String?) -> Acao {
            suprimido = icone ?? alvo
            alvo = nil; desde = nil; foraDesde = nil
            guard mostrando != nil else { return .nada }
            mostrando = nil
            return .esconder
        }
    }

    /// O lado da tela mais perto do ícone. Coordenadas do AppKit (origem
    /// embaixo); o Dock nunca fica em cima.
    public static func borda(icone: CGRect, tela: CGRect) -> Borda {
        let baixo = icone.minY - tela.minY
        let esquerda = icone.minX - tela.minX
        let direita = tela.maxX - icone.maxX
        if baixo <= esquerda && baixo <= direita { return .baixo }
        return esquerda <= direita ? .esquerda : .direita
    }

    /// O quadro do painel: centrado no ícone, do lado de dentro da tela, a
    /// `vao` pontos dele (o nome do app que o Dock mostra cabe no vão), e
    /// sem sair da tela.
    public static func quadro(tamanho: CGSize, icone: CGRect, tela: CGRect,
                              vao: CGFloat = 34, margem: CGFloat = 8) -> CGRect {
        var x: CGFloat, y: CGFloat
        switch borda(icone: icone, tela: tela) {
        case .baixo:
            x = icone.midX - tamanho.width / 2
            y = icone.maxY + vao
        case .esquerda:
            x = icone.maxX + vao
            y = icone.midY - tamanho.height / 2
        case .direita:
            x = icone.minX - vao - tamanho.width
            y = icone.midY - tamanho.height / 2
        }
        x = min(max(x, tela.minX + margem), tela.maxX - margem - tamanho.width)
        y = min(max(y, tela.minY + margem), tela.maxY - margem - tamanho.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: tamanho)
    }
}
