import Foundation
import CoreGraphics

/// Uma nota do bloco — uma aba.
public struct Nota: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var texto: String
    public var editadaEm: Date

    public init(id: UUID = UUID(), texto: String = "", editadaEm: Date = Date()) {
        self.id = id
        self.texto = texto
        self.editadaEm = editadaEm
    }

    /// O nome da aba: a primeira linha com conteúdo, sem a marcação de título.
    /// Não existe campo de nome — quem escreve "# Compras" já deu nome à nota.
    public var titulo: String {
        for linha in texto.split(whereSeparator: \.isNewline) {
            var t = linha.trimmingCharacters(in: .whitespaces)
            while t.hasPrefix("#") { t.removeFirst() }
            t = t.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return BlocoDeNotas.encurtar(t, ate: 24) }
        }
        return "Nota vazia"
    }

    /// Só conta o que tem letra ou número: a marcação ("#", "-", "[ ]") não é
    /// palavra, e uma lista de tarefas pareceria ter o dobro do texto.
    public var palavras: Int {
        texto.split { $0.isWhitespace || $0.isNewline }
             .filter { $0.contains { $0.isLetter || $0.isNumber } }
             .count
    }
}

public enum BlocoDeNotas {

    /// Abas demais deixam de caber na faixa e viram um depósito escondido.
    public static let maximoDeNotas = 12

    public static func encurtar(_ s: String, ate n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)) + "…"
    }

    /// Sempre sobra uma nota: o bloco vazio é uma folha em branco, não uma
    /// tela de "nenhuma nota".
    public static func garantirUma(_ notas: [Nota]) -> [Nota] {
        notas.isEmpty ? [Nota()] : notas
    }

    /// Fecha a aba e diz qual fica selecionada: a vizinha da direita, ou a da
    /// esquerda se era a última — como as abas do Safari.
    public static func remover(_ id: UUID, de notas: [Nota]) -> (notas: [Nota], selecionada: UUID) {
        guard let i = notas.firstIndex(where: { $0.id == id }) else {
            let r = garantirUma(notas)
            return (r, r[0].id)
        }
        var r = notas
        r.remove(at: i)
        r = garantirUma(r)
        return (r, r[min(i, r.count - 1)].id)
    }

    /// Marca ou desmarca a tarefa da linha `indice` ("- [ ]" ↔ "- [x]").
    /// Linha que não é tarefa volta intacta.
    public static func alternarTarefa(_ texto: String, linha indice: Int) -> String {
        var linhas = texto.components(separatedBy: "\n")
        guard linhas.indices.contains(indice) else { return texto }
        let l = linhas[indice]
        if let r = l.range(of: "[ ]"), Markdown.ehTarefa(l) {
            linhas[indice] = l.replacingCharacters(in: r, with: "[x]")
        } else if let r = l.range(of: "[x]", options: .caseInsensitive), Markdown.ehTarefa(l) {
            linhas[indice] = l.replacingCharacters(in: r, with: "[ ]")
        }
        return linhas.joined(separator: "\n")
    }

    // MARK: painel

    public static let bordasPermitidas: [TrayEdge] = [.left, .right]

    public static func edge(persisted: String) -> TrayEdge {
        let e = TrayEdge(persisted: persisted)
        return bordasPermitidas.contains(e) ? e : .left
    }

    public static let comprimento: CGFloat = 480
    public static let espessura: CGFloat = 380
}

/// Leitor de Markdown por blocos, só o que uma nota rápida usa.
///
/// O `AttributedString(markdown:)` do sistema entende negrito, itálico, código
/// e links, mas junta tudo numa linha só — títulos, listas e tarefas somem.
/// Aqui cada linha vira um bloco; o que é de dentro da linha fica com o
/// sistema.
public enum Markdown {

    public enum Bloco: Equatable, Sendable {
        case titulo(nivel: Int, texto: String)
        case item(texto: String)
        case numerado(numero: String, texto: String)
        /// `linha` é o índice no texto original, para o clique marcar a certa.
        case tarefa(feita: Bool, texto: String, linha: Int)
        case citacao(texto: String)
        case codigo(texto: String)
        case divisor
        case paragrafo(texto: String)
        case vazio
    }

    static func ehTarefa(_ linha: String) -> Bool {
        let t = linha.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("- [ ]") || t.hasPrefix("- [x]") || t.hasPrefix("- [X]")
            || t.hasPrefix("* [ ]") || t.hasPrefix("* [x]") || t.hasPrefix("* [X]")
    }

    public static func blocos(_ texto: String) -> [Bloco] {
        var r: [Bloco] = []
        var codigo: [String]? = nil

        for (i, bruta) in texto.components(separatedBy: "\n").enumerated() {
            let t = bruta.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("```") {
                if let aberto = codigo {
                    r.append(.codigo(texto: aberto.joined(separator: "\n")))
                    codigo = nil
                } else {
                    codigo = []
                }
                continue
            }
            if codigo != nil { codigo!.append(bruta); continue }

            if t.isEmpty { r.append(.vazio); continue }
            if t == "---" || t == "***" { r.append(.divisor); continue }

            if t.hasPrefix("#") {
                let nivel = t.prefix { $0 == "#" }.count
                let resto = t.dropFirst(nivel)
                if nivel <= 3, resto.first == " " {
                    r.append(.titulo(nivel: nivel, texto: resto.trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            if ehTarefa(t) {
                let feita = !t.dropFirst(2).hasPrefix("[ ]")
                r.append(.tarefa(feita: feita,
                                 texto: String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces),
                                 linha: i))
                continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                r.append(.item(texto: String(t.dropFirst(2))))
                continue
            }
            if let ponto = t.firstIndex(of: "."), ponto > t.startIndex,
               t[..<ponto].allSatisfy(\.isNumber),
               t[t.index(after: ponto)...].first == " " {
                r.append(.numerado(numero: String(t[..<ponto]),
                                   texto: t[t.index(after: ponto)...].trimmingCharacters(in: .whitespaces)))
                continue
            }
            if t.hasPrefix(">") {
                r.append(.citacao(texto: t.dropFirst().trimmingCharacters(in: .whitespaces)))
                continue
            }
            r.append(.paragrafo(texto: t))
        }
        // bloco de código sem fechamento: mostra o que tem, em vez de engolir
        if let aberto = codigo { r.append(.codigo(texto: aberto.joined(separator: "\n"))) }

        // várias linhas vazias seguidas valem um respiro só
        return r.enumerated().filter { i, b in
            !(b == .vazio && i > 0 && r[i - 1] == .vazio)
        }.map(\.element)
    }
}
