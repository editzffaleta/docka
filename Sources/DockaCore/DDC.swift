import Foundation

/// O protocolo DDC/CI, que o macOS não expõe: os pacotes que vão pelo cabo
/// para o monitor ajustar o brilho do próprio painel.
///
/// Lógica pura, conferida contra a especificação (VESA DDC/CI): montar o
/// pedido, conferir a resposta. Quem fala com o hardware é a casca — e só
/// depois de uma leitura bem-sucedida.
public enum DDC {

    /// Endereço do monitor no barramento I²C (7 bits). Em 8 bits é 0x6E.
    public static let enderecoDoMonitor: UInt8 = 0x37
    /// Endereço de origem do computador; vai como "subendereço" na escrita.
    public static let origem: UInt8 = 0x51

    /// O único código que o Docka usa: luminância (brilho do painel).
    /// Nada de entrada de vídeo, modo de cor ou restaurar padrões — um
    /// comando errado nesses mexeria no monitor de um jeito que o Docka não
    /// teria como desfazer.
    public static let brilho: UInt8 = 0x10

    /// Checksum do DDC/CI: XOR de todos os bytes, começando pelo endereço de
    /// destino em 8 bits e pela origem.
    static func checksum(_ bytes: [UInt8], inicial: UInt8) -> UInt8 {
        bytes.reduce(inicial, ^)
    }

    /// Pacote "escrever valor": [0x84, 0x03, código, valor alto, valor baixo, checksum].
    public static func escrever(_ codigo: UInt8, valor: UInt16) -> [UInt8] {
        let dados: [UInt8] = [0x03, codigo, UInt8(valor >> 8), UInt8(valor & 0xFF)]
        let corpo = [0x80 | UInt8(dados.count)] + dados
        return corpo + [checksum(corpo, inicial: 0x6E ^ origem)]
    }

    /// Pacote "pedir valor": [0x82, 0x01, código, checksum].
    public static func pedir(_ codigo: UInt8) -> [UInt8] {
        let dados: [UInt8] = [0x01, codigo]
        let corpo = [0x80 | UInt8(dados.count)] + dados
        return corpo + [checksum(corpo, inicial: 0x6E ^ origem)]
    }

    /// Bytes que a resposta tem: origem, tamanho e oito de dados, mais o checksum.
    public static let tamanhoDaResposta = 11

    /// A resposta a um pedido, se for válida e do código pedido.
    ///
    /// Formato: [0x6E, 0x88, 0x02, resultado, código, tipo, máx alto, máx
    /// baixo, atual alto, atual baixo, checksum]. Resultado diferente de 0 é
    /// "código não suportado" — o monitor fala DDC, mas não deixa mexer no
    /// brilho por ele.
    public static func ler(_ r: [UInt8], codigo: UInt8) -> (atual: UInt16, maximo: UInt16)? {
        guard r.count >= tamanhoDaResposta,
              r[1] == 0x88, r[2] == 0x02, r[3] == 0x00, r[4] == codigo else { return nil }
        // a resposta vem do monitor para o "endereço 0x50" do host
        guard checksum(Array(r[0..<10]), inicial: 0x50) == r[10] else { return nil }
        let maximo = UInt16(r[6]) << 8 | UInt16(r[7])
        let atual = UInt16(r[8]) << 8 | UInt16(r[9])
        guard maximo > 0, atual <= maximo else { return nil }
        return (atual, maximo)
    }

    /// Nível da régua (0…1) → valor do monitor, dentro do máximo dele.
    public static func valor(nivel: Double, maximo: UInt16) -> UInt16 {
        UInt16((min(max(nivel, 0), 1) * Double(maximo)).rounded())
    }

    public static func nivel(valor: UInt16, maximo: UInt16) -> Double {
        maximo == 0 ? 0 : min(Double(valor) / Double(maximo), 1)
    }

    /// Código de fabricante de três letras (EDID/EISA, ex.: "GSM" da LG) no
    /// número que o CoreGraphics devolve em `CGDisplayVendorNumber` — é o que
    /// liga o canal de vídeo de uma porta à tela certa.
    public static func fabricante(_ letras: String) -> UInt32? {
        let c = Array(letras.uppercased().unicodeScalars)
        guard c.count == 3, c.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return nil }
        return (c[0].value - 64) << 10 | (c[1].value - 64) << 5 | (c[2].value - 64)
    }
}
