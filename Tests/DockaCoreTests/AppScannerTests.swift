import Testing
import Foundation
@testable import DockaCore

@Suite("Varredura de aplicativos")
struct AppScannerTests {

    /// Monta uma árvore temporária parecida com /Applications e devolve a raiz.
    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("docka-scan-\(UUID().uuidString)")

        let dirs = [
            "Safari.app/Contents/MacOS",          // app na raiz, com miolo dentro
            "Utilities/Terminal.app/Contents",    // app numa subpasta
            "Adobe/Creative Cloud/Photoshop.app", // fundo demais: fora do alcance
            "Documentos",                          // pasta comum, sem app
            "Leia-me.app.txt"                      // não é um bundle
        ]
        for d in dirs {
            try fm.createDirectory(at: root.appendingPathComponent(d),
                                   withIntermediateDirectories: true)
        }
        return root
    }

    @Test("Encontra apps na raiz e um nível abaixo")
    func findsRootAndOneLevelDown() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let names = AppScanner.scan(roots: [root]).map { ($0 as NSString).lastPathComponent }
        #expect(names.contains("Safari.app"))
        #expect(names.contains("Terminal.app"))   // era o que o app não achava antes
    }

    @Test("Não desce mais fundo que o alcance configurado")
    func respectsDepth() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let names = AppScanner.scan(roots: [root]).map { ($0 as NSString).lastPathComponent }
        // dois níveis abaixo da raiz: fora do alcance padrão, senão a varredura
        // vira um passeio pelo disco inteiro
        #expect(!names.contains("Photoshop.app"))
    }

    @Test("Não entra dentro dos bundles")
    func doesNotDescendIntoBundles() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        // Safari.app/Contents/MacOS existe; nada de dentro do bundle pode vazar
        let found = AppScanner.scan(roots: [root])
        #expect(found.allSatisfy { !$0.contains("Contents") })
        #expect(found.count == 2)
    }

    @Test("Profundidade 1 varre só a raiz")
    func depthOneIsRootOnly() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let names = AppScanner.scan(roots: [root], depth: 1)
            .map { ($0 as NSString).lastPathComponent }
        #expect(names == ["Safari.app"])
    }

    @Test("Ignora pastas comuns e arquivos que só parecem bundle")
    func ignoresNonBundles() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = AppScanner.scan(roots: [root])
        #expect(!found.contains { $0.hasSuffix("Documentos") })
        #expect(!found.contains { $0.hasSuffix(".txt") })
    }

    @Test("O mesmo app em duas raízes aparece uma vez só")
    func deduplicates() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(AppScanner.scan(roots: [root, root]) == AppScanner.scan(roots: [root]))
    }

    @Test("Uma raiz inexistente não derruba a varredura")
    func missingRootIsHarmless() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        // ~/Applications não existe em toda máquina
        let ausente = URL(fileURLWithPath: "/caminho/que/nao/existe")
        #expect(AppScanner.scan(roots: [root, ausente]).count == 2)
    }

    @Test("A ordem do resultado é estável")
    func stableOrder() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        // vem de um Set: sem ordenação, a grade do seletor embaralharia a cada varredura
        #expect(AppScanner.scan(roots: [root]) == AppScanner.scan(roots: [root]))
        #expect(AppScanner.scan(roots: [root]) == AppScanner.scan(roots: [root]).sorted())
    }
}

@Suite("Nome do aplicativo")
struct AppNamingTests {

    @Test("Tira o .app do fim")
    func trimsSuffix() {
        #expect(AppNaming.trimmingAppSuffix("Safari.app") == "Safari")
    }

    @Test("Preserva um .app no meio do nome")
    func keepsInnerOccurrence() {
        // era o defeito do replacingOccurrences: virava "Meu Ficador"
        #expect(AppNaming.trimmingAppSuffix("Meu .appFicador.app") == "Meu .appFicador")
        #expect(AppNaming.trimmingAppSuffix("Snap.apple") == "Snap.apple")
    }

    @Test("Nome já sem extensão passa intacto")
    func passesThroughCleanName() {
        // com "mostrar todas as extensões" desligado, o Finder já entrega sem .app
        #expect(AppNaming.trimmingAppSuffix("Ajustes do Sistema") == "Ajustes do Sistema")
        #expect(AppNaming.trimmingAppSuffix("") == "")
    }
}

@Suite("Reordenação da bandeja")
struct ReorderTests {

    private let apps = ["A", "B", "C", "D"]

    @Test("Arrastar para a frente compensa o deslocamento da remoção")
    func moveForward() {
        // A soltado sobre C: A sai, e C já andou uma casa para trás
        #expect(Reorder.move(apps, from: 0, to: 2) == ["B", "A", "C", "D"])
    }

    @Test("Arrastar para trás insere na posição do alvo")
    func moveBackward() {
        #expect(Reorder.move(apps, from: 3, to: 1) == ["A", "D", "B", "C"])
    }

    @Test("Soltar no mesmo lugar não muda nada")
    func moveOntoItself() {
        #expect(Reorder.move(apps, from: 2, to: 2) == apps)
    }

    @Test("Mover para o fim mantém todos os itens")
    func moveToEnd() {
        let out = Reorder.move(apps, from: 0, to: 3)
        #expect(out.count == apps.count)
        #expect(Set(out) == Set(apps))
        #expect(out == ["B", "C", "A", "D"])
    }

    @Test("Índices inválidos devolvem a lista intacta")
    func invalidIndices() {
        #expect(Reorder.move(apps, from: 9, to: 1) == apps)
        #expect(Reorder.move(apps, from: 1, to: 9) == apps)
        #expect(Reorder.move([String](), from: 0, to: 0).isEmpty)
    }
}
