import Foundation

/// Um botão extra do mouse como gatilho.
///
/// Mouses de 5 botões trazem dois laterais além do meio. Qual número o sistema
/// dá a cada um varia com o modelo e com o driver, então nada aqui é chutado:
/// os ajustes capturam o botão que o usuário apertar e guardam o número.
public enum BotaoDoMouse {

    /// Nenhum botão configurado.
    public static let nenhum = -1

    /// O menor número aceito.
    ///
    /// 0 e 1 são o clique esquerdo e o direito. Sequestrar esses dois no
    /// sistema inteiro deixaria o Mac inutilizável, e nenhuma configuração
    /// deveria permitir isso — nem por engano, nem de propósito.
    public static let minimo = 2

    public static func valido(_ n: Int) -> Bool { n >= minimo && n <= 31 }

    /// Nome legível. O número entre parênteses é o que o mouse costuma anunciar
    /// nos utilitários, contando a partir de 1.
    public static func nome(_ n: Int) -> String {
        switch n {
        case nenhum: return "Nenhum"
        case 2:      return "Botão do meio (roda)"
        case 3:      return "Botão lateral 1 (4)"
        case 4:      return "Botão lateral 2 (5)"
        default:     return "Botão \(n + 1)"
        }
    }

    /// Explica por que o botão foi recusado, ou `nil` se está tudo bem.
    public static func recusa(_ n: Int) -> String? {
        switch n {
        case 0: return "O botão esquerdo não pode ser o gatilho — ele é o clique."
        case 1: return "O botão direito não pode ser o gatilho — ele abre os menus."
        case ..<0: return nil
        default: return valido(n) ? nil : "Esse botão não pode ser usado."
        }
    }

    // MARK: segurar para escolher

    /// A partir de quanto tempo o apertar vira "segurar".
    ///
    /// Abaixo disso é um toque: o anel fica aberto e o usuário escolhe com
    /// calma. Acima, o botão vira menu radial — solta apontando e lança. Os
    /// dois convivem sem o usuário precisar decidir antes qual vai usar.
    public static let limiarDeSegurar: TimeInterval = 0.25

    /// Soltar o botão deve lançar o que está apontado?
    public static func soltouEscolhendo(duracao: TimeInterval, temSelecao: Bool) -> Bool {
        duracao >= limiarDeSegurar && temSelecao
    }
}
