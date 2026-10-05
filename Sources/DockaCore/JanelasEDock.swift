import Foundation
import CoreGraphics

// MARK: - Sair ao fechar

public enum SairAoFechar {

    /// Leituras seguidas com zero janelas antes de encerrar.
    ///
    /// Ao entrar ou sair da tela cheia, e ao trocar de Espaço, o macOS informa
    /// por um instante que o app tem ZERO janelas. Um zero isolado encerrava
    /// o app no meio da animação de tela cheia — achado testando.
    public static let zerosParaEncerrar = 3

    /// Acompanha a contagem de janelas de um app, leitura a leitura.
    public struct Vigia: Equatable, Sendable {
        /// Já teve alguma janela desde que começou a ser vigiado?
        public private(set) var teveJanela = false
        public private(set) var zerosSeguidos = 0

        public init() {}

        /// Registra uma leitura; devolve `true` quando é hora de encerrar.
        ///
        /// Só depois de ter tido janela (um app recém-aberto passa um instante
        /// sem nenhuma) e só com o zero repetido — e uma vez só.
        public mutating func leu(_ janelas: Int) -> Bool {
            if janelas > 0 {
                teveJanela = true
                zerosSeguidos = 0
                return false
            }
            guard teveJanela else { return false }
            zerosSeguidos += 1
            if zerosSeguidos >= SairAoFechar.zerosParaEncerrar {
                teveJanela = false
                return true
            }
            return false
        }
    }

    /// Quantas janelas o app tem abertas, a partir do que a Acessibilidade
    /// diz de cada uma.
    ///
    /// Conta as janelas comuns E as minimizadas: ao minimizar, o macOS troca
    /// o subpapel da janela de `AXStandardWindow` para `AXDialog`, e contar
    /// só as comuns fazia minimizar tudo parecer fechar tudo — e o app era
    /// encerrado (achado testando).
    public static func contar(_ janelas: [(subpapel: String?, minimizada: Bool)]) -> Int {
        janelas.filter { $0.minimizada || $0.subpapel == "AXStandardWindow" }.count
    }

    /// Apps que nunca entram: sem eles o Mac fica sem mesa ou sem Dock.
    public static let nuncaEncerrar: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver"]
}

// MARK: - Proteção do ⌘Q e ⌘W

public enum ModoDeProtecao: String, CaseIterable, Identifiable, Sendable {
    /// Segurar a combinação por um instante.
    case segurar
    /// Apertar duas vezes seguidas.
    case duploToque
    /// Exigir ⌥ junto (⌥⌘Q em vez de ⌘Q).
    case teclaExtra

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .segurar:    return "Segurar"
        case .duploToque: return "Apertar duas vezes"
        case .teclaExtra: return "Com ⌥ junto"
        }
    }

    public init(persisted: String) { self = ModoDeProtecao(rawValue: persisted) ?? .segurar }
}

/// A decisão sobre um ⌘Q (ou ⌘W) — lógica pura, sem relógio próprio: quem
/// chama passa o tempo de cada evento.
public struct ProtecaoDeAtalho: Sendable {
    public enum Decisao: Equatable, Sendable {
        /// Deixa o evento seguir para o app como veio.
        case deixar
        /// Engole o evento e mostra a dica (com o progresso, no "segurar").
        case segurarComDica(String, progresso: Double?)
        /// Engole e manda o atalho de verdade: confirmou.
        case confirmar
        /// Engole e some com a dica: desistiu.
        case cancelar
    }

    public var modo: ModoDeProtecao
    public static let tempoDeSegurar: TimeInterval = 0.8
    public static let janelaDoDuplo: TimeInterval = 1.0

    private var apertouEm: Date?
    private var primeiroToque: Date?

    public init(modo: ModoDeProtecao) { self.modo = modo }

    /// A tecla foi apertada (não repetição). `comOpcao` = ⌥ junto.
    public mutating func apertou(em t: Date, comOpcao: Bool, nome: String) -> Decisao {
        switch modo {
        case .teclaExtra:
            return comOpcao ? .confirmar : .segurarComDica("Use ⌥\(nome) para confirmar", progresso: nil)
        case .duploToque:
            if let p = primeiroToque, t.timeIntervalSince(p) <= Self.janelaDoDuplo {
                primeiroToque = nil
                return .confirmar
            }
            primeiroToque = t
            return .segurarComDica("Aperte \(nome) de novo para confirmar", progresso: nil)
        case .segurar:
            apertouEm = t
            return .segurarComDica("Segure \(nome) para confirmar", progresso: 0)
        }
    }

    /// Enquanto segura (repetições da tecla ou o relógio de quem chama).
    public mutating func segurando(em t: Date, nome: String) -> Decisao {
        guard modo == .segurar, let a = apertouEm else { return .segurarComDica("", progresso: nil) }
        let p = min(t.timeIntervalSince(a) / Self.tempoDeSegurar, 1)
        if p >= 1 {
            apertouEm = nil
            return .confirmar
        }
        return .segurarComDica("Segure \(nome) para confirmar", progresso: p)
    }

    /// A tecla foi solta: no "segurar", soltar antes do tempo desiste.
    public mutating func soltou() -> Decisao {
        guard modo == .segurar, apertouEm != nil else { return .deixar }
        apertouEm = nil
        return .cancelar
    }

    /// O toque duplo esqueceu o primeiro toque? Para a dica sumir.
    public func duploExpirou(em t: Date) -> Bool {
        guard modo == .duploToque, let p = primeiroToque else { return false }
        return t.timeIntervalSince(p) > Self.janelaDoDuplo
    }
}

// MARK: - Botão verde

public enum BotaoVerde {
    public enum Acao: Equatable, Sendable { case deixar, maximizar, restaurar }

    /// Com ⌥, o botão faz o de sempre (zoom do app); sem ⌥, maximiza na
    /// área útil — e, se a janela já está maximizada, volta ao de antes.
    public static func acao(comOpcao: Bool, quadro: CGRect, areaUtil: CGRect, temAnterior: Bool) -> Acao {
        if comOpcao { return .deixar }
        if Encaixe.quaseIgual(quadro, areaUtil) && temAnterior { return .restaurar }
        return .maximizar
    }
}

// MARK: - Cliques no Dock

public enum AcaoNoCliqueDoDock: String, CaseIterable, Identifiable, Sendable {
    case minimizar, ocultar, alternar

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .minimizar: return "Minimizar as janelas"
        case .ocultar:   return "Ocultar o app"
        case .alternar:  return "Passar para a próxima janela"
        }
    }

    public init(persisted: String) { self = AcaoNoCliqueDoDock(rawValue: persisted) ?? .minimizar }
}

public enum CliqueNoDock {
    /// O clique num ícone do Dock vira a ação escolhida só quando o app já
    /// está na frente com janela à vista. Fora disso, o Dock faz o de sempre
    /// — abrir, trazer para a frente, desminimizar.
    public static func assumir(appNaFrente: Bool, janelasVisiveis: Int) -> Bool {
        appNaFrente && janelasVisiveis > 0
    }

    /// Para "alternar": a próxima janela depois da que está na frente.
    public static func proxima(atual: Int, total: Int) -> Int {
        total <= 0 ? 0 : (atual + 1) % total
    }
}

// MARK: - Arrastar segurando uma tecla

/// As teclas que, seguradas, transformam o clique em qualquer ponto da
/// janela num arrasto. Só combinações com ⌃ ou ⌥ e mais uma: ⌘ sozinho já é
/// do sistema (arrastar janela de fundo sem trazê-la para a frente).
public enum TeclasDoArrasto: String, CaseIterable, Identifiable, Sendable {
    case controleOpcao, controleComando, opcaoComando, controleOpcaoComando

    public var id: String { rawValue }

    public var simbolo: String {
        switch self {
        case .controleOpcao:        return "⌃⌥"
        case .controleComando:      return "⌃⌘"
        case .opcaoComando:         return "⌥⌘"
        case .controleOpcaoComando: return "⌃⌥⌘"
        }
    }

    public init(persisted: String) { self = TeclasDoArrasto(rawValue: persisted) ?? .controleOpcao }

    /// Exatamente estas entre ⌘, ⌥ e ⌃ — ⇧ tanto faz. ⌃⌥⌘ apertado não
    /// dispara o ⌃⌥: seria tomar um atalho de outro app.
    public func confere(comando: Bool, opcao: Bool, controle: Bool) -> Bool {
        switch self {
        case .controleOpcao:        return controle && opcao && !comando
        case .controleComando:      return controle && comando && !opcao
        case .opcaoComando:         return opcao && comando && !controle
        case .controleOpcaoComando: return controle && opcao && comando
        }
    }
}

/// As contas do arrasto: tudo em coordenadas da Acessibilidade (origem no
/// topo, y crescendo para baixo), as mesmas do evento de mouse.
public enum ArrastoComTecla {
    /// O canto que acompanha o cursor ao redimensionar: o mais perto de onde
    /// o clique caiu.
    public struct Canto: Equatable, Sendable {
        public let esquerda: Bool
        public let topo: Bool
        public init(esquerda: Bool, topo: Bool) { self.esquerda = esquerda; self.topo = topo }
    }

    public static let tamanhoMinimo = CGSize(width: 160, height: 100)

    public static func canto(clique: CGPoint, quadro: CGRect) -> Canto {
        Canto(esquerda: clique.x < quadro.midX, topo: clique.y < quadro.midY)
    }

    public static func mover(_ q: CGRect, delta: CGPoint) -> CGRect {
        q.offsetBy(dx: delta.x, dy: delta.y)
    }

    /// O canto escolhido anda com o cursor; o oposto fica parado. Abaixo do
    /// mínimo, a janela para de encolher — sem atravessar o canto oposto.
    public static func redimensionar(_ q: CGRect, delta: CGPoint, canto: Canto,
                                     minimo: CGSize = tamanhoMinimo) -> CGRect {
        var x = q.minX, y = q.minY, l = q.width, a = q.height
        if canto.esquerda {
            l = max(minimo.width, q.width - delta.x)
            x = q.maxX - l
        } else {
            l = max(minimo.width, q.width + delta.x)
        }
        if canto.topo {
            a = max(minimo.height, q.height - delta.y)
            y = q.maxY - a
        } else {
            a = max(minimo.height, q.height + delta.y)
        }
        return CGRect(x: x, y: y, width: l, height: a)
    }
}
