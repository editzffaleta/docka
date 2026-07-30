import Testing
@testable import DockaCore

@Suite("Atalho global")
struct ShortcutTests {

    @Test("O padrão continua sendo ⇧⌘D")
    func padrao() {
        #expect(Shortcut.padrao.display == "⇧⌘D")
        #expect(Shortcut.padrao.isValid)
    }

    @Test("Os símbolos saem na ordem da Apple: ⌃⌥⇧⌘")
    func ordemDosSimbolos() {
        // a ordem não depende de como o usuário pressionou as teclas
        let todos = Shortcut(keyCode: 2, modifiers: [.command, .shift, .option, .control])
        #expect(todos.display == "⌃⌥⇧⌘D")

        let invertido = Shortcut(keyCode: 2, modifiers: [.control, .option, .shift, .command])
        #expect(invertido.display == todos.display)
    }

    @Test("Exige ⌘, ⌥ ou ⌃ — senão o atalho engoliria a tecla no sistema inteiro")
    func exigeModificadorForte() {
        #expect(!Shortcut(keyCode: 2, modifiers: []).isValid)
        #expect(!Shortcut(keyCode: 2, modifiers: [.shift]).isValid)
        #expect(Shortcut(keyCode: 2, modifiers: [.command]).isValid)
        #expect(Shortcut(keyCode: 2, modifiers: [.option]).isValid)
        #expect(Shortcut(keyCode: 2, modifiers: [.control]).isValid)
        #expect(Shortcut(keyCode: 2, modifiers: [.shift, .option]).isValid)
    }

    @Test("Traduz teclas que não são letras")
    func teclasEspeciais() {
        #expect(Shortcut(keyCode: 49, modifiers: [.command]).display == "⌘Espaço")
        #expect(Shortcut(keyCode: 122, modifiers: [.option]).display == "⌥F1")
        #expect(Shortcut(keyCode: 126, modifiers: [.control]).display == "⌃↑")
    }

    @Test("Uma tecla desconhecida não vira string vazia")
    func teclaDesconhecida() {
        // um plist editado à mão ou um teclado exótico não podem produzir
        // um atalho que aparece em branco na tela
        let estranho = Shortcut(keyCode: 250, modifiers: [.command])
        #expect(estranho.display == "⌘Tecla 250")
        #expect(!Shortcut.keyName(250).isEmpty)
    }

    @Test("A descrição falada usa palavras, não símbolos")
    func descricaoFalada() {
        // o VoiceOver lê "⇧⌘D" como uma sequência de símbolos soltos
        #expect(Shortcut.padrao.spokenDescription == "Shift Comando D")
        #expect(!Shortcut.padrao.spokenDescription.contains("⌘"))
    }

    @Test("Os modificadores sobrevivem à ida e volta pelo rawValue")
    func rawValueIdaEVolta() {
        // é assim que o atalho é gravado no UserDefaults
        let original = Shortcut(keyCode: 15, modifiers: [.command, .option])
        let restaurado = Shortcut(keyCode: original.keyCode,
                                  modifiers: .init(rawValue: original.modifiers.rawValue))
        #expect(restaurado == original)
        #expect(restaurado.display == "⌥⌘R")
    }
}
