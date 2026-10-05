import Foundation

/// O modo de limpeza: o teclado para de responder por um tempo, para dar
/// para passar um pano sem digitar nada em lugar nenhum.
public struct ModoDeLimpeza: Equatable, Sendable {

    public enum Visual: String, CaseIterable, Identifiable, Sendable {
        /// Telas pretas: mostram a sujeira e seguram também os cliques.
        case telaPreta
        /// Um aviso pequeno; o mouse continua normal.
        case indicador
        public var id: String { rawValue }
        public var titulo: String {
            switch self {
            case .telaPreta: return "Telas pretas"
            case .indicador: return "Aviso pequeno"
            }
        }
    }

    /// Quanto tempo segurar o botão para sair: um pano passando pelo
    /// trackpad não termina a limpeza sem querer.
    public static let segurarParaSair: TimeInterval = 1.2
    public static let duracoes: [TimeInterval] = [30, 60, 120, 300]

    public let fim: Date

    public init(inicio: Date, duracao: TimeInterval) {
        fim = inicio.addingTimeInterval(max(10, duracao))
    }

    /// O prazo vale mesmo se a interface travar: quem decide o que engolir
    /// pergunta isto a cada tecla, então o teclado volta sozinho no fim.
    public func ativo(em agora: Date) -> Bool { agora < fim }

    public func restante(em agora: Date) -> TimeInterval { max(0, fim.timeIntervalSince(agora)) }

    /// Os tipos de evento do teclado: tecla descendo, subindo, modificadores
    /// e as teclas especiais (brilho, volume, mídia), que chegam como evento
    /// de sistema.
    public static func engole(tipo: UInt32) -> Bool {
        [10, 11, 12, 14].contains(tipo)
    }

    /// 0…1 enquanto o botão de sair está apertado.
    public static func progressoDeSaida(desde: Date?, agora: Date) -> Double {
        guard let desde else { return 0 }
        return min(1, max(0, agora.timeIntervalSince(desde) / segurarParaSair))
    }

    /// "1:05", "0:09".
    public static func relogio(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// O painel rápido: uma paleta com as ferramentas favoritas, num atalho.
///
/// Cada ferramenta é guardada pelo id da ação de atalho — o que o painel
/// executa é exatamente o que o atalho dela executaria.
public enum PainelRapido {

    public static let padrao: [String] = [
        "barraDeComando", "historico", "snippets", "capturaArea",
        "contaGotas", "textoDaTela", "notas", "acordado",
        "rapida:aparencia", "rapida:nightShift", "rapida:travarTela", "limpeza",
    ]

    /// O que foi gravado, sem repetidos e só com o que ainda existe; nada
    /// gravado é o padrão.
    public static func favoritos(gravados: [String]?, existe: (String) -> Bool) -> [String] {
        var vistos = Set<String>()
        return (gravados ?? padrao).filter { existe($0) && vistos.insert($0).inserted }
    }

    /// Põe ou tira, mantendo a ordem dos outros.
    public static func alternar(_ id: String, em lista: [String]) -> [String] {
        lista.contains(id) ? lista.filter { $0 != id } : lista + [id]
    }

    /// Até quatro por linha.
    public static func colunas(_ n: Int) -> Int { min(4, max(1, n)) }
}
