import Foundation

/// Escurecimento por software: a tela escurece pela tabela de gama, e não
/// pelo brilho do painel.
///
/// Serve onde o brilho de hardware não chega — a maioria dos monitores
/// externos não responde ao DisplayServices — e para ir abaixo do mínimo do
/// próprio painel, à noite. A gama é API pública do CoreGraphics e não pede
/// permissão.
public enum Escurecimento {

    /// Até onde escurecer. Mais que isso e a tela fica preta — e uma tela
    /// preta não deixa a pessoa achar o controle para desfazer.
    public static let maximo = 0.8

    public static func limitar(_ v: Double) -> Double { min(max(v, 0), maximo) }

    /// Teto da curva de gama para um escurecimento: a saída vai de 0 até este
    /// valor, em vez de até 1.
    public static func teto(_ escurecimento: Double) -> Double {
        1 - limitar(escurecimento)
    }

    /// Chave estável de uma tela, para lembrar o escurecimento dela.
    ///
    /// O `CGDirectDisplayID` muda quando o monitor é religado ou trocado de
    /// porta; fabricante, modelo e número de série não. Sem série (alguns
    /// monitores informam 0), dois monitores iguais dividem a chave — melhor
    /// que perder o ajuste a cada religada.
    public static func chave(fabricante: UInt32, modelo: UInt32, serie: UInt32) -> String {
        "\(fabricante)-\(modelo)-\(serie)"
    }

    // MARK: a régua como um só controle

    /// A régua de brilho numa tela SEM brilho de hardware vira escurecimento:
    /// régua em cima = sem escurecer, régua embaixo = escurecimento máximo.
    public static func nivelDaRegua(escurecimento: Double) -> Double {
        1 - limitar(escurecimento) / maximo
    }

    public static func escurecimento(nivelDaRegua nivel: Double) -> Double {
        limitar((1 - min(max(nivel, 0), 1)) * maximo)
    }
}
