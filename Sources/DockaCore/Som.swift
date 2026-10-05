import Foundation

/// As decisões do som que não dependem do Core Audio: para onde vai o som de
/// cada app, qual a próxima saída, qual microfone usar e o que fazer quando o
/// fone sai.
public enum Som {

    // MARK: saída por app

    /// A saída que o app deve usar: a da regra, se está conectada; senão a
    /// padrão do sistema — o fone desligado não deixa o app mudo.
    public static func saidaEfetiva(regra: String?, conectadas: [String], padrao: String?) -> String? {
        if let regra, conectadas.contains(regra) { return regra }
        return padrao
    }

    /// O som do app só passa pelo Docka quando precisa: volume fora de 100%
    /// ou uma saída diferente da padrão.
    public static func precisaDesviar(controle: Double, saida: String?, padrao: String?) -> Bool {
        MixerDaIlha.precisaDesviar(controle) || (saida != nil && saida != padrao)
    }

    // MARK: trocar de saída

    /// A próxima da lista, dando a volta; a primeira se a atual não está nela.
    public static func proxima(atual: String?, lista: [String]) -> String? {
        guard !lista.isEmpty else { return nil }
        guard let atual, let i = lista.firstIndex(of: atual) else { return lista[0] }
        return lista[(i + 1) % lista.count]
    }

    // MARK: fones

    /// Os códigos do Core Audio: transporte Bluetooth ('blue', 'blea') e a
    /// fonte de dados "fones" da saída embutida ('hdpn').
    public static let transporteBluetooth: Set<UInt32> = [0x626C7565, 0x626C6561]
    public static let fonteFones: UInt32 = 0x6864706E

    public static func ehFone(transporte: UInt32, fonteDeDados: UInt32?) -> Bool {
        transporteBluetooth.contains(transporte) || fonteDeDados == fonteFones
    }

    /// Ao tirar o fone, o som cai no alto-falante: baixa até o limite, nunca
    /// sobe. `nil` quando não há o que mudar.
    public static func volumeAoTirarFone(antes: Bool, agora: Bool, volume: Float, limite: Float) -> Float? {
        guard antes, !agora, volume > limite + 0.001 else { return nil }
        return max(0, limite)
    }

    // MARK: microfone

    /// A entrada para pôr como padrão: a preferida, se está conectada e ainda
    /// não é a atual. `nil` é deixar como está — inclusive quando a preferida
    /// sumiu (o sistema escolhe outra, e volta para ela quando reconectar).
    public static func entradaParaUsar(preferida: String?, conectadas: [String], atual: String?) -> String? {
        guard let preferida, conectadas.contains(preferida), preferida != atual else { return nil }
        return preferida
    }

    /// Silenciar todos: guarda como cada microfone estava, para devolver
    /// exatamente isso — um que já estava mudo continua mudo ao religar.
    public struct Mudo: Equatable, Sendable {
        public private(set) var antes: [String: Bool] = [:]
        public var ativo: Bool { !antes.isEmpty }

        public init() {}

        /// Os microfones a silenciar agora (os que chegaram depois também).
        public mutating func silenciar(_ estados: [String: Bool]) -> [String] {
            var novos: [String] = []
            for (uid, mudo) in estados where antes[uid] == nil {
                antes[uid] = mudo
                novos.append(uid)
            }
            return novos.sorted()
        }

        /// Os que voltam a ter som: só os que tinham antes.
        public mutating func religar() -> [String] {
            defer { antes = [:] }
            return antes.filter { !$0.value }.map(\.key).sorted()
        }
    }

    /// "35%".
    public static func porcentagem(_ v: Float) -> String { "\(Int((min(1, max(0, v)) * 100).rounded()))%" }
}
