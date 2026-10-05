import Testing
@testable import DockaCore

@Suite("DDC/CI")
struct DDCTests {

    @Test("Pedir o brilho: pacote e checksum da especificação")
    func pedir() {
        // 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
        #expect(DDC.pedir(DDC.brilho) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test("Escrever o brilho em 50")
    func escrever() {
        // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        #expect(DDC.escrever(DDC.brilho, valor: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        // valor de 16 bits vai em dois bytes
        #expect(Array(DDC.escrever(DDC.brilho, valor: 300)[3...4]) == [0x01, 0x2C])
    }

    /// Uma resposta montada como o monitor manda, com checksum certo.
    private func resposta(resultado: UInt8 = 0, codigo: UInt8 = 0x10, maximo: UInt16 = 100, atual: UInt16 = 70) -> [UInt8] {
        var r: [UInt8] = [0x6E, 0x88, 0x02, resultado, codigo, 0x00,
                          UInt8(maximo >> 8), UInt8(maximo & 0xFF), UInt8(atual >> 8), UInt8(atual & 0xFF)]
        r.append(r.reduce(0x50, ^))
        return r
    }

    @Test("Resposta válida dá o atual e o máximo")
    func respostaValida() {
        let r = DDC.ler(resposta(), codigo: 0x10)
        #expect(r?.atual == 70)
        #expect(r?.maximo == 100)
    }

    @Test("Resposta estragada, de outro código ou não suportada é recusada")
    func respostaRuim() {
        var torta = resposta(); torta[10] ^= 0xFF
        #expect(DDC.ler(torta, codigo: 0x10) == nil)                         // checksum
        #expect(DDC.ler(resposta(codigo: 0x12), codigo: 0x10) == nil)        // outro código
        #expect(DDC.ler(resposta(resultado: 1), codigo: 0x10) == nil)        // não suportado
        #expect(DDC.ler(resposta(maximo: 0, atual: 0), codigo: 0x10) == nil) // máximo zero
        #expect(DDC.ler(resposta(maximo: 50, atual: 80), codigo: 0x10) == nil) // atual > máximo
        #expect(DDC.ler([0x6E, 0x88], codigo: 0x10) == nil)                  // curta
    }

    @Test("A régua nunca passa do máximo do monitor")
    func escala() {
        #expect(DDC.valor(nivel: 0.5, maximo: 100) == 50)
        #expect(DDC.valor(nivel: 1.7, maximo: 100) == 100)
        #expect(DDC.valor(nivel: -1, maximo: 100) == 0)
        #expect(DDC.nivel(valor: 25, maximo: 50) == 0.5)
        #expect(DDC.nivel(valor: 1, maximo: 0) == 0)
    }

    @Test("Fabricante de três letras vira o número do CoreGraphics")
    func fabricante() {
        #expect(DDC.fabricante("GSM") == 0x1E6D)    // LG
        #expect(DDC.fabricante("DEL") == 0x10AC)    // Dell
        #expect(DDC.fabricante("APP") == 0x0610)    // Apple (1552)
        #expect(DDC.fabricante("ab") == nil)
        #expect(DDC.fabricante("A1C") == nil)
    }

    @Test("Diagnóstico: o que um LG atrás de um adaptador USB-C → HDMI devolveu de verdade")
    func diagnosticoReal() {
        // escrita recusada (0xE0114102) e a leitura trazendo o EDID da LG ("GSM", modelo 23518)
        let lido: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x1E, 0x6D, 0xDE, 0x5B]
        #expect(DDC.diagnostico(escrita: Int32(bitPattern: 0xE011_4102), resposta: lido) == .soEDID)
    }

    @Test("Diagnóstico: resposta boa, escrita recusada, silêncio, brilho não suportado, estranha")
    func diagnosticoCasos() {
        // uma resposta válida montada como o monitor manda
        var r: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x46]
        r.append(r.reduce(0x50, ^))
        #expect(DDC.diagnostico(escrita: 0, resposta: r) == .respondeu(atual: 70, maximo: 100))
        #expect(DDC.diagnostico(escrita: -5, resposta: [UInt8](repeating: 0, count: 11)) == .escritaRecusada(codigo: -5))
        #expect(DDC.diagnostico(escrita: 0, resposta: [UInt8](repeating: 0xFF, count: 11)) == .silencio)
        var nao = r; nao[3] = 0x01
        #expect(DDC.diagnostico(escrita: 0, resposta: nao) == .brilhoNaoSuportado)
        #expect(DDC.diagnostico(escrita: 0, resposta: [0x6E, 0x12, 0x34, 0, 0, 0, 0, 0, 0, 0, 0]) == .respostaEstranha)
        #expect(DDC.Diagnostico.escritaRecusada(codigo: Int32(bitPattern: 0xE011_4102)).explicacao.contains("0xE0114102"))
    }

    @Test("Caminho com conversor DisplayPort → HDMI vira o motivo")
    func caminho() {
        let lg = DDC.Caminho(de: "DP", para: "HDMI")      // o que o macOS registrou para o LG
        #expect(lg.conversor && lg.descricao == "DisplayPort → HDMI")
        #expect(DDC.motivo(.soEDID, caminho: lg).contains("conversor DisplayPort → HDMI"))
        #expect(DDC.motivo(nil, caminho: lg).contains("USB-C → DisplayPort"))
        // sem conversor, fica o diagnóstico de sempre
        let direto = DDC.Caminho(de: "DP", para: "DP")
        #expect(!direto.conversor && direto.descricao == "DisplayPort")
        #expect(DDC.motivo(.soEDID, caminho: direto) == DDC.Diagnostico.soEDID.explicacao)
        // monitor que respondeu: o conversor não importa
        #expect(DDC.motivo(.respondeu(atual: 50, maximo: 100), caminho: lg).hasPrefix("respondeu"))
    }
}
