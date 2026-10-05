import Foundation
import CoreGraphics

/// Mouse e teclado: as regras do foco que segue o mouse, dos filtros de
/// repique e das ações dos botões — sem tocar em evento nenhum.
public enum MouseETeclado {

    // MARK: foco segue o mouse

    /// Parado sobre a janela de outro app por um instante, o foco vai para
    /// ele. Botão apertado (arrastando) ou modificador seguro cancelam — quem
    /// arrasta algo para outra janela não quer que ela pule para a frente
    /// no meio do caminho.
    public struct Vigia: Sendable {
        private var candidato: Int32?
        private var desde: Date?

        public init() {}

        /// Devolve o pid a trazer para a frente, uma vez, quando o cursor
        /// fica `atraso` segundos sobre a janela de um app que não é o da frente.
        public mutating func leu(sob pid: Int32?, frente: Int32?, em agora: Date, atraso: TimeInterval,
                                 botaoApertado: Bool, modificador: Bool) -> Int32? {
            guard let pid, pid != frente, !botaoApertado, !modificador else {
                candidato = nil; desde = nil
                return nil
            }
            if pid != candidato { candidato = pid; desde = agora; return atraso <= 0 ? disparar() : nil }
            if let d = desde, agora.timeIntervalSince(d) >= atraso - 0.001 { return disparar() }
            return nil
        }

        private mutating func disparar() -> Int32? {
            let p = candidato
            desde = .distantFuture        // não dispara de novo até mudar de app
            return p
        }
    }

    // MARK: repique (clique duplo acidental e teclas que repetem)

    /// Um botão ou tecla gasto "repica": solta e volta a apertar sozinho em
    /// poucos milissegundos. Quem aperta de novo de propósito leva bem mais
    /// (um clique duplo de verdade tem 100 ms ou mais entre os cliques).
    public struct Repique: Sendable {
        private var soltou: [Int64: (quando: Date, onde: CGPoint)] = [:]
        private var engolindo: Set<Int64> = []

        public init() {}

        /// Um "apertar": devolve se deve ser engolido.
        public mutating func apertou(_ id: Int64, em agora: Date, onde: CGPoint = .zero,
                                     limiar: TimeInterval, distanciaMaxima: CGFloat = 4) -> Bool {
            guard let s = soltou[id], agora.timeIntervalSince(s.quando) < limiar,
                  hypot(onde.x - s.onde.x, onde.y - s.onde.y) <= distanciaMaxima else { return false }
            engolindo.insert(id)
            return true
        }

        /// Um "soltar": devolve se deve ser engolido (o par de um "apertar" engolido).
        public mutating func soltou(_ id: Int64, em agora: Date, onde: CGPoint = .zero) -> Bool {
            if engolindo.remove(id) != nil { return true }
            soltou[id] = (agora, onde)
            return false
        }
    }

    // MARK: ações dos botões do mouse

    public enum AcaoDoBotao: String, CaseIterable, Identifiable, Sendable {
        case nada, voltar, avancar, missionControl, apps, copiar, colar, desfazer, novaAba, fecharAba, cliqueDoMeio

        public var id: String { rawValue }

        public var titulo: String {
            switch self {
            case .nada:           return "O de sempre"
            case .voltar:         return "Voltar (⌘[)"
            case .avancar:        return "Avançar (⌘])"
            case .missionControl: return "Mission Control"
            case .apps:           return "Apps"
            case .copiar:         return "Copiar (⌘C)"
            case .colar:          return "Colar (⌘V)"
            case .desfazer:       return "Desfazer (⌘Z)"
            case .novaAba:        return "Nova aba (⌘T)"
            case .fecharAba:      return "Fechar aba (⌘W)"
            case .cliqueDoMeio:   return "Clique do meio"
            }
        }

        /// A tecla que o ⌘ acompanha, para as ações que são atalho.
        public var tecla: String? {
            switch self {
            case .voltar: return "["
            case .avancar: return "]"
            case .copiar: return "c"
            case .colar: return "v"
            case .desfazer: return "z"
            case .novaAba: return "t"
            case .fecharAba: return "w"
            default: return nil
            }
        }
    }

    /// O botão 2 (o do meio, contando do zero) e os laterais 3 e 4 — os que
    /// costumam existir. Até o 7, para mouses com mais botões.
    public static let botoesConfiguraveis = Array(2...7)

    public static func nomeDoBotao(_ n: Int) -> String {
        switch n {
        case 2: return "Botão do meio"
        case 3: return "Botão lateral de trás"
        case 4: return "Botão lateral da frente"
        default: return "Botão \(n + 1)"
        }
    }

    /// A ação gravada de um botão, ou nil para deixar o comportamento de antes.
    public static func acao(botao: Int, gravadas: [String: String]) -> AcaoDoBotao? {
        gravadas[String(botao)].flatMap(AcaoDoBotao.init(rawValue:)).flatMap { $0 == .nada ? nil : $0 }
    }

    // MARK: tecla super (Caps Lock → ⌃⌥⇧⌘)

    /// O código HID do Caps Lock e o do F18 (para onde ele é remapeado — uma
    /// tecla que nenhum teclado tem, então nada mais a usa).
    public static let hidCapsLock: UInt64 = 0x7_0000_0039
    public static let hidF18: UInt64 = 0x7_0000_006D

    /// Junta o remapeamento do Docka aos que já existiam (de outro app ou do
    /// usuário), sem duplicar; `remover` tira só o do Docka.
    public static func mapeamentos(_ atuais: [[String: UInt64]], remover: Bool) -> [[String: UInt64]] {
        let semODocka = atuais.filter { $0["HIDKeyboardModifierMappingSrc"] != hidCapsLock }
        if remover { return semODocka }
        return semODocka + [["HIDKeyboardModifierMappingSrc": hidCapsLock, "HIDKeyboardModifierMappingDst": hidF18]]
    }
}
