import Foundation
import CoreGraphics

/// A matemática do monitor do sistema: transformar contadores do kernel em
/// porcentagens e taxas, e números em texto. A leitura dos contadores mora na
/// casca; aqui só entram números, para os testes alcançarem.
public enum Metricas {

    // MARK: CPU

    /// Tiques de um núcleo (ou da soma deles) num instante.
    public struct TiquesDeCPU: Equatable, Sendable {
        public var usuario: UInt64
        public var sistema: UInt64
        public var ocioso: UInt64
        public var nice: UInt64

        public init(usuario: UInt64, sistema: UInt64, ocioso: UInt64, nice: UInt64) {
            self.usuario = usuario
            self.sistema = sistema
            self.ocioso = ocioso
            self.nice = nice
        }

        var ocupado: UInt64 { usuario &+ sistema &+ nice }
        var total: UInt64 { ocupado &+ ocioso }
    }

    /// Uso da CPU entre duas leituras, de 0 a 1.
    ///
    /// Os contadores só crescem desde o boot: o uso de AGORA é a fração
    /// ocupada do que passou entre as duas leituras, não a do total — essa
    /// seria a média desde que o Mac ligou, quase parada.
    public static func usoDeCPU(de antes: TiquesDeCPU, para depois: TiquesDeCPU) -> Double {
        guard depois.total > antes.total else { return 0 }
        let total = Double(depois.total - antes.total)
        let ocupado = Double(depois.ocupado &- antes.ocupado)
        return min(max(ocupado / total, 0), 1)
    }

    // MARK: memória

    /// Memória em uso como o Monitor de Atividade conta: memória de apps
    /// (internas menos as descartáveis), mais a fixa (wired), mais a
    /// comprimida. Cache de arquivos não entra — o sistema solta na hora.
    public static func memoriaEmUso(internas: UInt64, descartaveis: UInt64,
                                    fixas: UInt64, comprimidas: UInt64,
                                    tamanhoDaPagina: UInt64) -> UInt64 {
        let apps = internas > descartaveis ? internas - descartaveis : 0
        return (apps + fixas + comprimidas) * tamanhoDaPagina
    }

    // MARK: rede

    /// Bytes que passaram entre duas leituras de um contador de 32 bits.
    ///
    /// O `if_data` do macOS conta em 32 bits: passados 4 GB, o contador volta
    /// a zero. Sem tratar a virada, a taxa daria um salto negativo uma vez a
    /// cada 4 GB baixados.
    public static func delta32(de antes: UInt64, para depois: UInt64) -> UInt64 {
        if depois >= antes { return depois - antes }
        return (UInt64(UInt32.max) + 1) - antes + depois
    }

    /// Interfaces que contam no tráfego: as físicas (Wi-Fi, Ethernet).
    ///
    /// A VPN (`utun`) passa o mesmo tráfego de novo por cima da física, e o
    /// loopback é o Mac falando com ele mesmo — somar qualquer um dos dois
    /// mostraria o dobro do que de fato entrou.
    public static func contaNoTrafego(_ interface: String) -> Bool {
        interface.hasPrefix("en")
    }

    // MARK: texto

    /// "512 MB", "1,4 GB", "238 GB" — uma casa decimal só abaixo de 10.
    ///
    /// `binario` para memória: o Monitor de Atividade conta RAM em 1024, e um
    /// Mac de 16 GB apareceria como "17 GB" em base 1000. Disco fica em 1000,
    /// que é como o Finder e a etiqueta do próprio SSD contam.
    public static func bytes(_ b: UInt64, binario: Bool = false) -> String {
        let unidades = ["B", "KB", "MB", "GB", "TB"]
        let base: Double = binario ? 1024 : 1000
        var v = Double(b)
        var i = 0
        while v >= base && i < unidades.count - 1 { v /= base; i += 1 }
        if i == 0 { return "\(b) B" }
        return v < 10 ? "\(decimal(v)) \(unidades[i])" : "\(Int(v.rounded())) \(unidades[i])"
    }

    /// Taxa por segundo: "0 KB/s", "850 KB/s", "2,3 MB/s".
    ///
    /// Nunca em bytes: "143 B/s" num indicador da barra de menus muda de
    /// largura a cada leitura e não diz nada que "0 KB/s" não diga.
    public static func taxa(_ bytesPorSegundo: Double) -> String {
        let kb = max(0, bytesPorSegundo) / 1000
        if kb < 1000 { return "\(Int(kb.rounded())) KB/s" }
        let mb = kb / 1000
        return mb < 10 ? "\(decimal(mb)) MB/s" : "\(Int(mb.rounded())) MB/s"
    }

    public static func porcentagem(_ fracao: Double) -> String {
        "\(Int((min(max(fracao, 0), 1) * 100).rounded()))%"
    }

    /// Tempo de bateria: "2h 15min", "45min". `nil` ou negativo = o sistema
    /// ainda está calculando.
    public static func tempo(minutos: Int?) -> String? {
        guard let m = minutos, m > 0 else { return nil }
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r)min" }
        return r == 0 ? "\(h)h" : "\(h)h \(r)min"
    }

    private static func decimal(_ v: Double) -> String {
        String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

/// Os últimos N valores, do mais antigo ao mais recente — o desenho do
/// gráfico de linha de cada métrica.
public struct Historico: Equatable, Sendable {
    public let capacidade: Int
    public private(set) var valores: [Double] = []

    public init(capacidade: Int = 60) {
        self.capacidade = max(1, capacidade)
    }

    public mutating func adicionar(_ v: Double) {
        valores.append(v)
        if valores.count > capacidade { valores.removeFirst(valores.count - capacidade) }
    }

    public var ultimo: Double? { valores.last }

    /// Pontos do gráfico num retângulo, com y para baixo. `teto` fixa a
    /// escala (1 para porcentagens); `nil` escala pelo maior valor visto —
    /// o que a rede precisa, já que não tem máximo.
    public func pontos(largura: CGFloat, altura: CGFloat, teto: Double? = nil) -> [CGPoint] {
        guard !valores.isEmpty else { return [] }
        let maximo = max(teto ?? (valores.max() ?? 1), .ulpOfOne)
        // o gráfico ocupa sempre a largura toda da capacidade: com poucas
        // leituras ele nasce na direita e cresce para a esquerda, como o do
        // Monitor de Atividade
        let passo = largura / CGFloat(max(1, capacidade - 1))
        let inicio = largura - passo * CGFloat(valores.count - 1)
        return valores.enumerated().map { i, v in
            CGPoint(x: inicio + passo * CGFloat(i),
                    y: altura - altura * CGFloat(min(max(v / maximo, 0), 1)))
        }
    }
}

/// O que aparece na barra de menus ao lado do ícone.
public enum LeituraDaBarra: String, CaseIterable, Identifiable, Codable, Sendable {
    case nenhuma, cpu, memoria, rede, bateria

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .nenhuma: return "Nada — só o ícone"
        case .cpu:     return "Uso da CPU"
        case .memoria: return "Memória em uso"
        case .rede:    return "Download da rede"
        case .bateria: return "Bateria"
        }
    }

    public init(persisted: String) {
        self = LeituraDaBarra(rawValue: persisted) ?? .nenhuma
    }
}
