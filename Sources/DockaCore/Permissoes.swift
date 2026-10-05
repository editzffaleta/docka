import Foundation

/// As permissões do macOS que algum módulo do Docka pode pedir.
public enum Permissao: String, CaseIterable, Identifiable, Sendable {
    case acessibilidade, gravacaoDeTela, monitoramentoDeEntrada, calendarios

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .acessibilidade:         return "Acessibilidade"
        case .gravacaoDeTela:         return "Gravação de Tela"
        case .monitoramentoDeEntrada: return "Monitoramento de Entrada"
        case .calendarios:            return "Calendários"
        }
    }

    /// O que a permissão deixa o Docka fazer — e só isso.
    public var descricao: String {
        switch self {
        case .acessibilidade:
            return "Deixa os recursos mover janelas, mandar ⌘V e atalhos, e ajustar a rolagem e os botões do mouse."
        case .gravacaoDeTela:
            return "Deixa os recursos ler o texto de uma área da tela, capturar imagens e mostrar miniaturas das janelas."
        case .monitoramentoDeEntrada:
            return "Deixa os gatilhos de snippets verem as teclas digitadas — só os últimos 32 caracteres, na memória."
        case .calendarios:
            return "Deixa a ilha mostrar os seus compromissos e avisar do próximo. Só lê; nada sai do Mac."
        }
    }

    public var simbolo: String {
        switch self {
        case .acessibilidade:         return "accessibility"
        case .gravacaoDeTela:         return "rectangle.dashed.badge.record"
        case .monitoramentoDeEntrada: return "keyboard"
        case .calendarios:            return "calendar"
        }
    }

    /// O painel certo dos Ajustes do Sistema.
    public var enderecoDosAjustes: String {
        let painel: String
        switch self {
        case .acessibilidade:         painel = "Privacy_Accessibility"
        case .gravacaoDeTela:         painel = "Privacy_ScreenCapture"
        case .monitoramentoDeEntrada: painel = "Privacy_ListenEvent"
        case .calendarios:            painel = "Privacy_Calendars"
        }
        return "x-apple.systempreferences:com.apple.preference.security?\(painel)"
    }
}

/// Um recurso que pede alguma permissão, e se está ligado agora.
public struct RecursoComPermissao: Equatable, Sendable {
    public var nome: String
    public var permissoes: Set<Permissao>
    public var ligado: Bool

    public init(nome: String, permissoes: Set<Permissao>, ligado: Bool) {
        self.nome = nome
        self.permissoes = permissoes
        self.ligado = ligado
    }
}

public enum Permissoes {

    /// O que dizer sobre uma permissão, dado o estado dela e o dos recursos.
    public enum Situacao: Equatable, Sendable {
        /// Concedida e usada: tudo certo.
        case emUso
        /// Concedida, mas nada ligado precisa dela — dá para revogar.
        case concedidaSemUso
        /// Algo ligado precisa dela, e ela falta: o recurso não funciona.
        case falta
        /// Nem concedida nem necessária.
        case desnecessaria
    }

    /// Os recursos LIGADOS que usam a permissão — o "Usada por" da lista.
    public static func usadaPor(_ p: Permissao, em recursos: [RecursoComPermissao]) -> [String] {
        recursos.filter { $0.ligado && $0.permissoes.contains(p) }.map(\.nome)
    }

    /// Todos os recursos que PODERIAM usar a permissão, ligados ou não.
    public static func podeSerUsadaPor(_ p: Permissao, em recursos: [RecursoComPermissao]) -> [String] {
        recursos.filter { $0.permissoes.contains(p) }.map(\.nome)
    }

    public static func situacao(_ p: Permissao, concedida: Bool, recursos: [RecursoComPermissao]) -> Situacao {
        let usada = !usadaPor(p, em: recursos).isEmpty
        switch (concedida, usada) {
        case (true, true):   return .emUso
        case (true, false):  return .concedidaSemUso
        case (false, true):  return .falta
        case (false, false): return .desnecessaria
        }
    }

    /// "Colar sozinho, Encaixar janelas e Ajustes do mouse".
    public static func lista(_ nomes: [String]) -> String {
        switch nomes.count {
        case 0: return ""
        case 1: return nomes[0]
        default: return nomes.dropLast().joined(separator: ", ") + " e " + nomes.last!
        }
    }
}
