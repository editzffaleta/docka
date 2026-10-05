import AppKit
import DockaCore

/// As ferramentas do Docka que a barra de comando e o painel rápido mostram.
///
/// Cada uma é uma ação de atalho: escolher no painel ou na barra executa
/// exatamente o que o atalho dela executaria.
enum Ferramentas {

    /// As que fazem algo agora — um recurso desligado nos ajustes não aparece,
    /// senão o clique não faria nada.
    static func disponiveis() -> [AcaoDeAtalho] {
        let s = DockaStore.shared
        var lista: [AcaoDeAtalho] = [.barraDeComando, .painelRapido, .limpeza]
        if s.historicoControl { lista.append(.historico) }
        lista += [.snippets, .textoPuro]
        if s.capturaControl { lista += [.capturaArea, .contaGotas, .textoDaTela] }
        if s.notasControl { lista.append(.blocoDeNotas) }
        if s.prateleiraControl { lista.append(.prateleira) }
        if s.monitorControl { lista.append(.monitor) }
        if s.ilhaControl { lista.append(.ilha) }
        if s.orbitaControl { lista.append(.orbita) }
        if s.alternadorControl { lista.append(.alternador) }
        lista += [.acordado, .mudoMicrofones, .proximaSaida]
        lista += AcaoRapida.allCases.filter(AcoesRapidasBackend.disponivel).map { .rapida($0) }
        if s.janelasControl { lista += LayoutDeJanela.allCases.map { .janela($0) } }
        lista.append(.ajustes)
        return lista
    }

    static func titulo(_ a: AcaoDeAtalho) -> String {
        switch a {
        case .rapida(let r): return AcoesRapidasBackend.titulo(r)
        default:             return DockaStore.shared.nomeDaAcao(a.id)
        }
    }

    static func simbolo(_ a: AcaoDeAtalho) -> String {
        switch a {
        case .barraDeComando: return "magnifyingglass"
        case .painelRapido:   return "square.grid.3x3.fill"
        case .limpeza:        return "keyboard.badge.ellipsis"
        case .historico:      return "doc.on.clipboard"
        case .snippets:       return "text.badge.plus"
        case .textoPuro:      return "textformat"
        case .capturaArea:    return "camera.viewfinder"
        case .contaGotas:     return "eyedropper"
        case .textoDaTela:    return "text.viewfinder"
        case .blocoDeNotas:   return "note.text"
        case .prateleira:     return "tray.full"
        case .monitor:        return "chart.xyaxis.line"
        case .ilha:           return "rectangle.topthird.inset.filled"
        case .secaoDaIlha:    return "rectangle.topthird.inset.filled"
        case .orbita, .anel:  return "circle.dashed"
        case .alternador:     return "rectangle.on.rectangle"
        case .acordado:       return "cup.and.saucer"
        case .rapida(let r):  return r.simbolo
        case .janela:         return "rectangle.split.2x1"
        case .ajustes:        return "gearshape"
        case .brilho:         return "sun.max"
        case .volume:         return "speaker.wave.2"
        case .bandeja:        return "dock.rectangle"
        case .proximaSaida:   return "hifispeaker.and.homepod"
        case .mudoMicrofones: return "mic.slash"
        }
    }

    /// Ligada ou não, para as que têm estado; `nil` para as que só executam.
    static func ligada(_ a: AcaoDeAtalho) -> Bool? {
        switch a {
        case .acordado:      return AcordadoSessao.shared.ativo
        case .mudoMicrofones: return SomController.shared.microfonesMudos
        case .rapida(let r): return AcoesRapidasBackend.ligada(r)
        default:             return nil
        }
    }

    /// Executa depois que o painel some — senão a captura ou o histórico
    /// abririam com o painel ainda por cima.
    static func executar(_ a: AcaoDeAtalho) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            TrayManager.shared.executar(a)
        }
    }
}
