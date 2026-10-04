import Foundation

/// A lógica do alternador de apps: a ordem de uso e a seleção.
public enum Alternador {

    /// Ordena os processos pelo uso mais recente.
    ///
    /// `historico` é a sequência de ativações, da mais recente para a mais
    /// antiga. Quem não aparece nele (abriu antes do Docka, nunca foi
    /// ativado desde então) vai para o fim, na ordem em que veio.
    public static func porUso(_ processos: [Int32], historico: [Int32]) -> [Int32] {
        let posicao = Dictionary(historico.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return processos.enumerated().sorted { a, b in
            switch (posicao[a.element], posicao[b.element]) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Registra uma ativação: o processo vai para a frente do histórico, sem
    /// repetir, e o histórico não cresce sem fim.
    public static func registrar(_ pid: Int32, em historico: [Int32], limite: Int = 64) -> [Int32] {
        Array(([pid] + historico.filter { $0 != pid }).prefix(limite))
    }

    /// Seleção ao abrir: o SEGUNDO da lista — o primeiro é o app em que a
    /// pessoa já está, e abrir o alternador para ficar nele não faz sentido.
    /// É o que o ⌘Tab do sistema faz.
    public static func selecaoInicial(total: Int) -> Int {
        total > 1 ? 1 : 0
    }

    /// Avança (ou volta, com passo negativo) dando a volta nas pontas.
    public static func mover(_ indice: Int, passo: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return ((indice + passo) % total + total) % total
    }

    /// Os modificadores que abriram o alternador ainda estão apertados?
    /// Soltar QUALQUER um deles confirma a escolha.
    public static func aindaSegurando(gatilho: Shortcut.Modifiers, agora: Shortcut.Modifiers) -> Bool {
        let relevantes: Shortcut.Modifiers = [.command, .option, .control]
        let exigidos = gatilho.intersection(relevantes)
        return !exigidos.isEmpty && agora.isSuperset(of: exigidos)
    }
}
