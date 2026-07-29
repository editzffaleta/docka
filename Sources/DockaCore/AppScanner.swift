import Foundation

/// Varredura das pastas de aplicativos.
///
/// As raízes entram por parâmetro para que os testes possam apontar para uma
/// árvore temporária em vez do `/Applications` da máquina.
public enum AppScanner {

    /// Um nível abaixo de cada raiz, para pegar `Utilities` e as pastas que
    /// Adobe/Microsoft criam, sem sair varrendo o disco inteiro.
    public static let defaultDepth = 2

    public static var defaultRoots: [URL] {
        ["/Applications",
         "/System/Applications",
         (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
            .map { URL(fileURLWithPath: $0) }
    }

    /// Caminhos dos `.app` encontrados, sem duplicatas e em ordem estável.
    /// - Parameter depth: `1` varre só a própria raiz; `2` desce uma subpasta.
    public static func scan(roots: [URL],
                            depth: Int = defaultDepth,
                            fileManager: FileManager = .default) -> [String] {
        var found: Set<String> = []
        for root in roots {
            collect(root, depth: depth, fileManager: fileManager, into: &found)
        }
        return found.sorted()
    }

    private static func collect(_ dir: URL,
                                depth: Int,
                                fileManager: FileManager,
                                into found: inout Set<String>) {
        guard depth > 0,
              let entries = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return }

        for url in entries {
            if url.pathExtension == "app" {
                // um .app é um diretório: registra e NÃO entra nele
                found.insert(url.path)
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collect(url, depth: depth - 1, fileManager: fileManager, into: &found)
            }
        }
    }
}

/// Regras de nome de aplicativo.
public enum AppNaming {
    /// Tira o `.app` apenas quando ele está mesmo no fim.
    /// `replacingOccurrences(of: ".app")` mutilava nomes que contêm ".app" no meio.
    public static func trimmingAppSuffix(_ displayName: String) -> String {
        displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }
}

/// Reordenação da lista de apps fixados.
public enum Reorder {
    /// Move o item do índice `from` para a posição de `to`.
    ///
    /// Quando o alvo vinha **depois** do arrastado, a própria remoção já desloca
    /// tudo uma casa para trás — daí o `to - 1`.
    public static func move<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard from != to,
              items.indices.contains(from),
              items.indices.contains(to) else { return items }
        var out = items
        let item = out.remove(at: from)
        out.insert(item, at: from < to ? to - 1 : to)
        return out
    }
}
