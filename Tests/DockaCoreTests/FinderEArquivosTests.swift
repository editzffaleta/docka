import Testing
@testable import DockaCore

@Suite("Finder e arquivos")
struct FinderEArquivosTests {
    @Test("Recorte: ⌘X copia e lembra; o ⌘V seguinte move")
    func recorte() {
        var r = FinderEArquivos.Recorte()
        let a1 = r.recortar(editandoTexto: false)
        r.copiou(numero: 41)
        let a2 = r.colar(editandoTexto: false, numeroAgora: 41)
        #expect(a1 == .copiarELembrar && a2 == .mover)
        #expect(!r.ativo)                                      // um recorte, uma colagem
    }

    @Test("Recorte: renomeando é texto; copiou outra coisa no meio, esquece")
    func recorteCasos() {
        var r = FinderEArquivos.Recorte()
        let texto = r.recortar(editandoTexto: true)
        #expect(texto == .deixar)
        r.copiou(numero: 10)
        let outra = r.colar(editandoTexto: false, numeroAgora: 11)   // a área mudou
        #expect(outra == .deixar && !r.ativo)
        r.copiou(numero: 12)
        let colandoTexto = r.colar(editandoTexto: true, numeroAgora: 12)
        #expect(colandoTexto == .deixar && r.ativo)            // colar num campo de nome não gasta o recorte
    }

    @Test("Imagem de disco: um app, de um .dmg")
    func dmg() {
        let info: [String: Any] = ["images": [["image-path": "/Users/x/Downloads/App-1.2.dmg",
                                               "system-entities": [["mount-point": "/Volumes/App"]]]]]
        let img = FinderEArquivos.imagem(doVolume: "/Volumes/App", info: info)
        #expect(img == "/Users/x/Downloads/App-1.2.dmg")
        #expect(FinderEArquivos.imagem(doVolume: "/Volumes/Outro", info: info) == nil)
        #expect(FinderEArquivos.oferecer(volume: "/Volumes/App", itens: ["App.app", "Applications", ".background"], imagem: img) == "App.app")
        #expect(FinderEArquivos.oferecer(volume: "/Volumes/App", itens: ["A.app", "B.app"], imagem: img) == nil)
        #expect(FinderEArquivos.oferecer(volume: "/Volumes/Pendrive", itens: ["App.app"], imagem: nil) == nil)
    }
}
