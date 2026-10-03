import Foundation

/// Ações de um toque: coisas do sistema que hoje exigem atalho decorado,
/// ícone escondido ou Terminal.
///
/// Todas funcionam sem permissão. Ficaram de fora as que exigiriam alguma —
/// esvaziar o Lixo (Automação do Finder ou Acesso Total ao Disco) e trocar
/// claro/escuro (Automação dos Eventos do Sistema).
public enum AcaoRapida: String, CaseIterable, Identifiable, Codable, Sendable {
    case travarTela
    case apagarTelas
    case protecaoDeTela
    case repouso
    case ejetarDiscos
    case iconesDaMesa

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .travarTela:     return "Travar a tela"
        case .apagarTelas:    return "Apagar as telas"
        case .protecaoDeTela: return "Proteção de tela"
        case .repouso:        return "Repouso"
        case .ejetarDiscos:   return "Ejetar todos os discos"
        case .iconesDaMesa:   return "Ocultar ícones da mesa"
        }
    }

    public var descricao: String {
        switch self {
        case .travarTela:     return "Vai direto para a tela de login, como ⌃⌘Q."
        case .apagarTelas:    return "Desliga as telas e deixa o Mac trabalhando."
        case .protecaoDeTela: return "Liga a proteção de tela escolhida nos Ajustes."
        case .repouso:        return "Põe o Mac para dormir."
        case .ejetarDiscos:   return "Ejeta discos externos, imagens de disco e volumes de rede."
        case .iconesDaMesa:   return "Esconde ou mostra os arquivos da mesa. O Finder reinicia para aplicar."
        }
    }

    public var simbolo: String {
        switch self {
        case .travarTela:     return "lock.fill"
        case .apagarTelas:    return "display"
        case .protecaoDeTela: return "sparkles.tv"
        case .repouso:        return "moon.fill"
        case .ejetarDiscos:   return "eject.fill"
        case .iconesDaMesa:   return "eye.slash"
        }
    }
}

/// Um volume montado, só com o que a decisão de ejetar precisa.
public struct VolumeMontado: Equatable, Sendable {
    public var caminho: String
    public var nome: String
    public var raiz: Bool
    public var interno: Bool
    public var ejetavel: Bool
    public var removivel: Bool

    public init(caminho: String, nome: String, raiz: Bool, interno: Bool,
                ejetavel: Bool, removivel: Bool) {
        self.caminho = caminho
        self.nome = nome
        self.raiz = raiz
        self.interno = interno
        self.ejetavel = ejetavel
        self.removivel = removivel
    }
}

public enum Ejecao {

    /// Os volumes que o "Ejetar todos" deve levar.
    ///
    /// Não dá para confiar só em `ejetavel`: um SSD externo pela USB-C costuma
    /// se declarar nem ejetável nem removível — e é justamente o disco que a
    /// pessoa quer ejetar antes de puxar o cabo. O critério é o do Finder: tudo
    /// o que não é o disco interno.
    public static func alvos(_ volumes: [VolumeMontado]) -> [VolumeMontado] {
        volumes.filter { v in
            guard !v.raiz else { return false }
            // o sistema monta pedaços do disco interno em /System/Volumes
            guard !v.caminho.hasPrefix("/System/") else { return false }
            return !v.interno || v.ejetavel || v.removivel
        }
    }

    /// Resumo para o aviso depois de ejetar.
    public static func resumo(ejetados: [String], falhas: [String]) -> String {
        if ejetados.isEmpty && falhas.isEmpty { return "Nenhum disco para ejetar." }
        var partes: [String] = []
        if !ejetados.isEmpty {
            partes.append(ejetados.count == 1
                          ? "\(ejetados[0]) foi ejetado."
                          : "\(ejetados.count) discos ejetados.")
        }
        if !falhas.isEmpty {
            let lista = falhas.joined(separator: ", ")
            partes.append(falhas.count == 1
                          ? "\(lista) está em uso e não foi ejetado."
                          : "Em uso, não ejetados: \(lista).")
        }
        return partes.joined(separator: " ")
    }
}

public enum IconesDaMesa {

    /// Os ícones estão visíveis? Lê o `CreateDesktop` do Finder.
    ///
    /// A chave só existe depois que alguém a grava: ausente quer dizer o padrão
    /// do Finder, que é mostrar. O `defaults` devolve "0"/"1" ou "false"/"true"
    /// dependendo de como foi gravada.
    public static func visiveis(valorGravado: String?) -> Bool {
        guard let v = valorGravado?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !v.isEmpty else { return true }
        return !(v == "0" || v == "false" || v == "no")
    }
}
