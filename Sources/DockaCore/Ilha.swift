import Foundation
import CoreGraphics

/// A Ilha Dinâmica: uma forma preta em volta do recorte da câmera (ou
/// simulada, em telas sem recorte) que cresce com o cursor, abre numa grade
/// de seções e, fechada, mostra atividades ao vivo.
///
/// Aqui mora só a parte que dá para testar sem tela: as medidas, o vigia que
/// decide crescer, abrir e fechar, e quais atividades aparecem.
public enum Ilha {

    // MARK: - Seções

    /// Cada seção da grade. `disponivel` diz se já foi feita — as outras
    /// chegam nas próximas etapas e ficam fora da grade até lá.
    public enum Secao: String, CaseIterable, Identifiable, Sendable, Codable {
        case controles, mixer, musica, capturas, arquivos
        case sistema, calendario, notificacoes, timer, camera
        case downloads, rascunho, agentes

        public var id: String { rawValue }

        public var titulo: String {
            switch self {
            case .controles:    return "Controles"
            case .mixer:        return "Mixer de volume"
            case .musica:       return "Tocando agora"
            case .capturas:     return "Capturas recentes"
            case .arquivos:     return "Arquivos"
            case .sistema:      return "Sistema"
            case .calendario:   return "Calendário"
            case .notificacoes: return "Notificações"
            case .timer:        return "Timer"
            case .camera:       return "Espelho da câmera"
            case .downloads:    return "Downloads"
            case .rascunho:     return "Rascunho"
            case .agentes:      return "Agentes de IA"
            }
        }

        public var simbolo: String {
            switch self {
            case .controles:    return "slider.horizontal.3"
            case .mixer:        return "speaker.wave.2"
            case .musica:       return "music.note"
            case .capturas:     return "camera.viewfinder"
            case .arquivos:     return "tray"
            case .sistema:      return "gauge.with.dots.needle.33percent"
            case .calendario:   return "calendar"
            case .notificacoes: return "bell"
            case .timer:        return "timer"
            case .camera:       return "web.camera"
            case .downloads:    return "arrow.down.circle"
            case .rascunho:     return "note.text"
            case .agentes:      return "sparkles"
            }
        }

        /// Já feita nesta versão do Docka.
        public var disponivel: Bool {
            switch self {
            case .timer, .controles, .sistema, .arquivos, .rascunho, .capturas, .downloads, .musica, .calendario, .mixer, .notificacoes, .camera, .agentes: return true
            default: return false
            }
        }

        /// A ordem padrão da grade.
        public static let ordemPadrao: [Secao] = allCases
    }

    /// Os botões redondos dos lados da ilha aberta.
    public enum BotaoLateral: String, CaseIterable, Identifiable, Sendable, Codable {
        case inicio, timer, ajustes, volume, agentes

        public var id: String { rawValue }

        public var titulo: String {
            switch self {
            case .inicio:  return "Início (grade de seções)"
            case .timer:   return "Timer"
            case .ajustes: return "Ajustes da ilha"
            case .volume:  return "Volume"
            case .agentes: return "Agentes de IA"
            }
        }

        public var simbolo: String {
            switch self {
            case .inicio:  return "square.grid.2x2"
            case .timer:   return "timer"
            case .ajustes: return "gearshape"
            case .volume:  return "speaker.wave.2"
            case .agentes: return "sparkles"
            }
        }

        public var disponivel: Bool { true }

        public static let esquerdaPadrao: [BotaoLateral] = [.inicio, .timer]
        public static let direitaPadrao: [BotaoLateral] = [.ajustes, .volume]
    }

    /// A ordem gravada, sem repetidas nem desconhecidas, com as seções novas
    /// (que o arquivo antigo não conhecia) no fim.
    public static func ordem(gravada: [String]) -> [Secao] {
        var vistas = Set<Secao>()
        var r: [Secao] = []
        for s in gravada.compactMap(Secao.init(rawValue:)) where vistas.insert(s).inserted { r.append(s) }
        return r + Secao.ordemPadrao.filter { !vistas.contains($0) }
    }

    // MARK: - Medidas

    /// As medidas da ilha numa tela, em coordenadas do AppKit (origem embaixo).
    public struct Geometria: Equatable, Sendable {
        /// O recorte da câmera, ou o lugar dele numa tela sem recorte.
        public let recorte: CGRect
        /// A tela tem recorte de verdade (a ilha fechada some dentro dele).
        public let temRecorte: Bool

        public static let asa: CGFloat = 86
        public static let larguraSimulada: CGFloat = 190
        public static let crescimento = CGSize(width: 14, height: 6)
        public static let larguraAberta: CGFloat = 640
        public static let botao: CGFloat = 32
        public static let vaoDosBotoes: CGFloat = 12

        /// - Parameters:
        ///   - tela: o quadro inteiro da tela.
        ///   - areaEsquerda/areaDireita: as áreas da barra de menus dos dois
        ///     lados do recorte (`auxiliaryTopLeftArea`/`RightArea`); nil sem recorte.
        ///   - alturaDaBarra: altura da barra de menus, para a ilha simulada.
        public init(tela: CGRect, areaEsquerda: CGRect?, areaDireita: CGRect?, alturaDaBarra: CGFloat) {
            if let e = areaEsquerda, let d = areaDireita, d.minX > e.maxX {
                recorte = CGRect(x: e.maxX, y: tela.maxY - e.height, width: d.minX - e.maxX, height: e.height)
                temRecorte = true
            } else {
                let a = max(alturaDaBarra, 24)
                recorte = CGRect(x: tela.midX - Self.larguraSimulada / 2, y: tela.maxY - a,
                                 width: Self.larguraSimulada, height: a)
                temRecorte = false
            }
        }

        public init(recorte: CGRect, temRecorte: Bool) {
            self.recorte = recorte
            self.temRecorte = temRecorte
        }

        /// O cursor passou por cima: cresce um pouco, para baixo e para os lados.
        public var pairando: CGRect {
            CGRect(x: recorte.minX - Self.crescimento.width, y: recorte.minY - Self.crescimento.height,
                   width: recorte.width + 2 * Self.crescimento.width,
                   height: recorte.height + Self.crescimento.height)
        }

        /// Fechada com atividade: asas dos dois lados do recorte.
        public var compacta: CGRect {
            CGRect(x: recorte.minX - Self.asa, y: recorte.minY,
                   width: recorte.width + 2 * Self.asa, height: recorte.height)
        }

        /// Aberta, com `altura` de conteúdo abaixo do recorte.
        public func aberta(altura: CGFloat) -> CGRect {
            let l = max(Self.larguraAberta, recorte.width + 2 * Self.asa)
            let a = recorte.height + altura
            return CGRect(x: recorte.midX - l / 2, y: recorte.maxY - a, width: l, height: a)
        }

        /// Onde fica o botão lateral de índice `i` (de cima para baixo) de um lado.
        public func botao(_ i: Int, esquerda: Bool, aberta a: CGRect) -> CGRect {
            let x = esquerda ? a.minX - Self.vaoDosBotoes - Self.botao : a.maxX + Self.vaoDosBotoes
            let y = recorte.minY - 10 - CGFloat(i + 1) * Self.botao - CGFloat(i) * 10
            return CGRect(x: x, y: y, width: Self.botao, height: Self.botao)
        }
    }

    // MARK: - Estado

    public enum Estado: Equatable, Sendable {
        case fechada, pairando, aberta
    }

    /// Decide crescer, abrir e fechar, leitura a leitura do cursor.
    public struct Vigia: Sendable {
        public enum Acao: Equatable, Sendable { case nada, pairar, abrir, recolher, fechar }

        public private(set) var estado: Estado = .fechada
        private var pairandoDesde: Date?
        private var foraDesde: Date?

        public init() {}

        /// - Parameters:
        ///   - sobreAIlha: o cursor está sobre a forma atual (ou a zona dela).
        ///   - abrirAoPairar: parado tanto tempo em cima, ela abre; nil só abre no clique.
        ///   - folga: aberta, quanto tempo fora até fechar.
        ///   - fixada: aberta e presa (digitando, arrastando arquivo) — não fecha sozinha.
        public mutating func leu(sobreAIlha: Bool, em agora: Date, abrirAoPairar: TimeInterval?,
                                 folga: TimeInterval = 0.5, fixada: Bool = false) -> Acao {
            switch estado {
            case .fechada:
                guard sobreAIlha else { return .nada }
                estado = .pairando
                pairandoDesde = agora
                return abrirAoPairar == 0 ? abrir() : .pairar
            case .pairando:
                guard sobreAIlha else {
                    estado = .fechada; pairandoDesde = nil
                    return .recolher
                }
                if let espera = abrirAoPairar, let d = pairandoDesde, agora.timeIntervalSince(d) >= espera - 0.001 {
                    return abrir()
                }
                return .nada
            case .aberta:
                if sobreAIlha || fixada { foraDesde = nil; return .nada }
                guard let fora = foraDesde else { foraDesde = agora; return .nada }
                guard agora.timeIntervalSince(fora) >= folga - 0.001 else { return .nada }
                return fechar()
            }
        }

        /// Clique na ilha fechada, ou atalho.
        public mutating func clicou() -> Acao {
            estado == .aberta ? fechar() : abrir()
        }

        public mutating func abrir() -> Acao {
            estado = .aberta
            pairandoDesde = nil; foraDesde = nil
            return .abrir
        }

        public mutating func fechar() -> Acao {
            estado = .fechada
            pairandoDesde = nil; foraDesde = nil
            return .fechar
        }
    }

    // MARK: - Atividades ao vivo

    /// O que a ilha fechada mostra nas asas: um ícone à esquerda e um valor à
    /// direita (o timer: relógio e "14m").
    public struct Atividade: Equatable, Identifiable, Sendable {
        public enum Tipo: String, Sendable { case timer, pomodoro, cronometro, download, musica, calendario, agente, bateria, nivel, aviso }

        public let id: String
        public let tipo: Tipo
        public let simbolo: String
        public let valor: String
        /// Maior aparece primeiro.
        public let prioridade: Int
        /// 0…1, quando há (download, timer).
        public let progresso: Double?

        public init(id: String, tipo: Tipo, simbolo: String, valor: String, prioridade: Int, progresso: Double? = nil) {
            self.id = id; self.tipo = tipo; self.simbolo = simbolo
            self.valor = valor; self.prioridade = prioridade; self.progresso = progresso
        }
    }

    /// O que vai nas asas: a de maior prioridade sozinha, ou as duas maiores
    /// lado a lado quando "combinar" está ligado. `escolhida` (o usuário
    /// tocou numa) passa à frente.
    public static func visiveis(_ atividades: [Atividade], combinar: Bool, escolhida: String? = nil) -> [Atividade] {
        let ordenadas = atividades.sorted {
            if $0.id == escolhida { return true }
            if $1.id == escolhida { return false }
            return $0.prioridade != $1.prioridade ? $0.prioridade > $1.prioridade : $0.id < $1.id
        }
        return Array(ordenadas.prefix(combinar ? 2 : 1))
    }
}
