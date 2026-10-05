import AppKit
import IOKit
import DockaCore

/// Brilho do painel de monitores externos pelo DDC/CI, em Apple Silicon.
///
/// O macOS não tem API pública para isso. O caminho é o do MonitorControl e
/// do BetterDisplay: as funções `IOAVService*` do IOKit (privadas, resolvidas
/// em runtime) falam I²C com o monitor pelo cabo de vídeo.
///
/// Regras, porque isto escreve no hardware de outra pessoa:
/// - só o código de brilho (`DDC.brilho`); nada de entrada, cor ou padrões;
/// - nenhuma escrita sem uma leitura bem-sucedida antes — monitor que não
///   responde (ou adaptador que não repassa DDC) fica no escurecimento por
///   software;
/// - todo valor fica entre 0 e o máximo que o próprio monitor informou;
/// - tudo numa fila própria: cada conversa leva dezenas de milissegundos e
///   não pode travar a interface.
final class DDCBackend {
    static let shared = DDCBackend()

    struct Monitor {
        let servico: CFTypeRef
        var atual: UInt16
        let maximo: UInt16
        let nome: String
    }

    /// Monitores com DDC funcionando, por tela do CoreGraphics.
    private(set) var monitores: [CGDirectDisplayID: Monitor] = [:]
    private let fila = DispatchQueue(label: "docka.ddc", qos: .userInitiated)
    /// O último valor pedido por tela, enquanto a régua é arrastada — só ele
    /// vai para o cabo.
    private var pendente: [CGDirectDisplayID: UInt16] = [:]
    private var escrevendo: Set<CGDirectDisplayID> = []
    private let trava = NSLock()

    // MARK: funções privadas do IOKit

    private typealias CriarFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let criar: CriarFn? = simbolo("IOAVServiceCreateWithService")
    private static let lerI2C: I2CFn? = simbolo("IOAVServiceReadI2C")
    private static let escreverI2C: I2CFn? = simbolo("IOAVServiceWriteI2C")

    private static func simbolo<T>(_ nome: String) -> T? {
        guard let s = dlsym(UnsafeMutableRawPointer(bitPattern: -2), nome) else { return nil }   // RTLD_DEFAULT
        return unsafeBitCast(s, to: T.self)
    }

    static var disponivel: Bool { criar != nil && lerI2C != nil && escreverI2C != nil }

    // MARK: descoberta

    /// Um canal de vídeo de porta externa, com o que o sistema diz da tela
    /// ligada a ele.
    struct Canal {
        let servico: CFTypeRef
        let fabricante: UInt32?
        let produto: UInt64?
        let serie: UInt64?
        let nome: String
    }

    /// Percorre o registro como o MonitorControl: cada framebuffer com tela
    /// ligada traz "DisplayAttributes"; o próximo "DCPAVServiceProxy" externo
    /// é o canal dessa tela. Portas vazias não têm atributos e ficam de fora.
    static func canais() -> [Canal] {
        guard let criar else { return [] }
        var it: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(IORegistryGetRootEntry(kIOMainPortDefault), kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively), &it) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(it) }

        var resultado: [Canal] = []
        var atributos: [String: Any]?
        while case let e = IOIteratorNext(it), e != 0 {
            defer { IOObjectRelease(e) }
            var nome = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(e, &nome)
            let classe = String(cString: nome)
            if classe == "IOMobileFramebufferShim" || classe == "AppleCLCD2" {
                if let a = IORegistryEntryCreateCFProperty(e, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                   let p = a["ProductAttributes"] as? [String: Any] {
                    atributos = p
                }
            } else if classe == "DCPAVServiceProxy", let p = atributos,
                      (IORegistryEntryCreateCFProperty(e, "Location" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? String) == "External",
                      let servico = criar(kCFAllocatorDefault, e)?.takeRetainedValue() {
                // o fabricante vem como número legado ou como as três letras do EDID
                let fab = (p["LegacyManufacturerID"] as? NSNumber)?.uint32Value
                    ?? (p["ManufacturerID"] as? String).flatMap(DDC.fabricante)
                resultado.append(Canal(servico: servico, fabricante: fab,
                                       produto: (p["ProductID"] as? NSNumber)?.uint64Value,
                                       serie: (p["SerialNumber"] as? NSNumber)?.uint64Value,
                                       nome: p["ProductName"] as? String ?? "Monitor externo"))
                atributos = nil
            }
        }
        return resultado
    }

    /// Liga canais a telas externas do CoreGraphics. Com um só de cada lado
    /// (o caso comum), é ele; com vários, por fabricante, modelo e série.
    static func casar(_ canais: [Canal], telas: [CGDirectDisplayID]) -> [CGDirectDisplayID: Canal] {
        let externas = telas.filter { CGDisplayIsBuiltin($0) == 0 }
        if externas.count == 1, canais.count == 1 { return [externas[0]: canais[0]] }
        var livres = canais
        var r: [CGDirectDisplayID: Canal] = [:]
        for t in externas {
            func pontos(_ c: Canal) -> Int {
                var p = 0
                if c.fabricante == CGDisplayVendorNumber(t) { p += 1 } else { return -1 }
                if let pr = c.produto, pr == UInt64(CGDisplayModelNumber(t)) { p += 2 }
                if let s = c.serie, s != 0, s == UInt64(CGDisplaySerialNumber(t)) { p += 4 }
                return p
            }
            guard let i = livres.indices.max(by: { pontos(livres[$0]) < pontos(livres[$1]) }),
                  pontos(livres[i]) >= 0 else { continue }
            r[t] = livres.remove(at: i)
        }
        return r
    }

    /// Descobre os monitores e LÊ o brilho de cada um. Só entra na lista o
    /// que respondeu — é a garantia de que nunca se escreve às cegas.
    func atualizar(_ telas: [CGDirectDisplayID], pronto: @escaping () -> Void) {
        guard Self.disponivel else { pronto(); return }
        fila.async { [weak self] in
            guard let self else { return }
            var achados: [CGDirectDisplayID: Monitor] = [:]
            for (tela, canal) in Self.casar(Self.canais(), telas: telas) {
                if let r = Self.lerBrilho(canal.servico) {
                    achados[tela] = Monitor(servico: canal.servico, atual: r.atual, maximo: r.maximo, nome: canal.nome)
                }
            }
            DispatchQueue.main.async {
                self.monitores = achados
                pronto()
            }
        }
    }

    // MARK: ler e escrever

    func nivel(_ tela: CGDirectDisplayID) -> Double? {
        monitores[tela].map { DDC.nivel(valor: $0.atual, maximo: $0.maximo) }
    }

    /// Pede um brilho. Arrastando a régua chegam dezenas por segundo: guarda
    /// só o último e manda um por vez, na fila.
    func escrever(_ nivel: Double, em tela: CGDirectDisplayID) {
        guard var m = monitores[tela] else { return }
        let valor = DDC.valor(nivel: nivel, maximo: m.maximo)
        m.atual = valor
        monitores[tela] = m
        trava.lock()
        pendente[tela] = valor
        let jaIndo = escrevendo.contains(tela)
        escrevendo.insert(tela)
        trava.unlock()
        guard !jaIndo else { return }
        fila.async { [weak self] in self?.esvaziar(tela, servico: m.servico) }
    }

    private func esvaziar(_ tela: CGDirectDisplayID, servico: CFTypeRef) {
        while true {
            trava.lock()
            guard let v = pendente.removeValue(forKey: tela) else {
                escrevendo.remove(tela)
                trava.unlock()
                return
            }
            trava.unlock()
            Self.enviar(DDC.escrever(DDC.brilho, valor: v), servico)
            usleep(50_000)   // o monitor precisa de um respiro entre comandos
        }
    }

    // MARK: I²C

    private static func enviar(_ pacote: [UInt8], _ servico: CFTypeRef) {
        guard let escreverI2C else { return }
        var p = pacote
        // duas vezes, como o MonitorControl: alguns monitores perdem a primeira
        for _ in 0..<2 {
            _ = escreverI2C(servico, UInt32(DDC.enderecoDoMonitor), UInt32(DDC.origem), &p, UInt32(p.count))
            usleep(10_000)
        }
    }

    /// Pede o brilho e lê a resposta, com algumas tentativas — o barramento
    /// às vezes devolve lixo na primeira.
    static func lerBrilho(_ servico: CFTypeRef) -> (atual: UInt16, maximo: UInt16)? {
        guard let lerI2C else { return nil }
        for _ in 0..<4 {
            enviar(DDC.pedir(DDC.brilho), servico)
            usleep(50_000)
            var r = [UInt8](repeating: 0, count: DDC.tamanhoDaResposta)
            if lerI2C(servico, UInt32(DDC.enderecoDoMonitor), 0, &r, UInt32(r.count)) == kIOReturnSuccess,
               let v = DDC.ler(r, codigo: DDC.brilho) {
                return v
            }
            usleep(30_000)
        }
        return nil
    }

    /// Uma tentativa só de LEITURA, sem conferir nada: o código da escrita
    /// do pedido e os bytes que voltaram — a matéria-prima do diagnóstico.
    static func tentativaCrua(_ servico: CFTypeRef) -> (escrita: Int32, lido: [UInt8]) {
        guard let escreverI2C, let lerI2C else { return (-1, []) }
        var p = DDC.pedir(DDC.brilho)
        let w = escreverI2C(servico, UInt32(DDC.enderecoDoMonitor), UInt32(DDC.origem), &p, UInt32(p.count))
        usleep(60_000)
        var r = [UInt8](repeating: 0, count: DDC.tamanhoDaResposta)
        _ = lerI2C(servico, UInt32(DDC.enderecoDoMonitor), 0, &r, UInt32(r.count))
        return (w, r)
    }

    // MARK: autoteste

    /// Só LÊ: mostra os canais encontrados, a que tela cada um casou e o
    /// brilho informado. Não escreve nada no monitor.
    static func autoteste() -> String {
        var r = ["funções do IOKit: \(disponivel ? "encontradas" : "AUSENTES")"]
        let canais = canais()
        r.append("canais de vídeo externos com tela ligada: \(canais.count)")
        for c in canais {
            r.append("  • \(c.nome): fabricante \(c.fabricante.map(String.init) ?? "?"), produto \(c.produto.map(String.init) ?? "?"), série \(c.serie.map(String.init) ?? "?")")
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        let telas = Array(ids.prefix(Int(n)))
        for t in telas where CGDisplayIsBuiltin(t) == 0 {
            r.append("tela externa \(t): fabricante \(CGDisplayVendorNumber(t)), modelo \(CGDisplayModelNumber(t)), série \(CGDisplaySerialNumber(t))")
        }
        let pares = casar(canais, telas: telas)
        for (t, c) in pares {
            if let v = lerBrilho(c.servico) {
                r.append("OK — \(c.nome) (tela \(t)) respondeu: brilho \(v.atual) de \(v.maximo)")
            } else {
                let (escrita, lido) = tentativaCrua(c.servico)
                let d = DDC.diagnostico(escrita: escrita, resposta: lido)
                r.append("SEM RESPOSTA — \(c.nome) (tela \(t)): \(d.explicacao)")
                r.append(String(format: "  detalhes: escrita 0x%08X, lido %@", UInt32(bitPattern: escrita),
                                lido.map { String(format: "%02X", $0) }.joined(separator: " ")))
                r.append("  fica o escurecimento por software, que funciona com qualquer monitor")
            }
        }
        if !canais.isEmpty, pares.isEmpty {
            r.append("os canais encontrados não casaram com nenhuma tela externa ativa")
        }
        if telas.allSatisfy({ CGDisplayIsBuiltin($0) != 0 }) {
            r.append("nenhum monitor externo conectado — conecte um e rode de novo")
        }
        return r.joined(separator: "\n")
    }
}
