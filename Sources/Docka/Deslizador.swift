import SwiftUI
import DockaCore

/// A descrição de um controle deslizante de borda.
///
/// Brilho e volume são a mesma peça de interface: régua vertical numa lateral,
/// botão que corre com o valor, arrasto suavizado, tique por degrau. O que
/// distingue um do outro cabe nesta estrutura — o nome, o ícone, onde o valor
/// mora no store e como se lê e escreve no sistema. A régua, o painel e o
/// controlador são únicos e recebem isto.
struct Deslizador {
    let id: String
    /// "Brilho", "Volume" — usado no rótulo de acessibilidade e nos ajustes.
    let titulo: String
    /// O que a VoiceOver lê na régua.
    let rotulo: String
    let dica: String
    /// O que os ajustes dizem quando este Mac não expõe o controle.
    let avisoIndisponivel: String
    /// O que os ajustes explicam embaixo do nível.
    let nota: String
    /// Explicação do que o controle é, no interruptor que o liga.
    let descricao: String

    let nivel: ReferenceWritableKeyPath<DockaStore, Double>
    let borda: KeyPath<DockaStore, String>
    let alinhamento: KeyPath<DockaStore, String>
    let ligado: KeyPath<DockaStore, Bool>
    let bordaPadrao: TrayEdge

    /// Símbolo SF mostrado no botão em repouso, em função do nível.
    let simbolo: (Double) -> String

    let disponivel: () -> Bool
    let ler: () -> Double?
    let escrever: (Double) -> Void
    let tique: () -> Void

    func bordaAtual(_ store: DockaStore) -> TrayEdge {
        Deslizante.edge(persisted: store[keyPath: borda], padrao: bordaPadrao)
    }

    static let brilho = Deslizador(
        id: "brilho",
        titulo: "Brilho",
        rotulo: "Brilho da tela",
        dica: "Arraste para ajustar o brilho; toque para abrir os ajustes",
        avisoIndisponivel: "Este Mac não expõe o controle de brilho para apps.",
        nota: "O nível é lido da tela de verdade, e o controle não pede permissão nenhuma. Isso usa uma API do sistema não documentada: se uma atualização do macOS removê-la, o Docka esconde o controle em vez de fingir que funciona.",
        descricao: "Uma régua própria numa lateral da tela. Encoste o cursor na borda para revelá-la.",
        nivel: \.brightnessLevel,
        borda: \.brightnessEdge,
        alinhamento: \.brightnessAlignment,
        ligado: \.brightnessControl,
        bordaPadrao: .right,
        simbolo: { _ in "sun.max.fill" },
        disponivel: { BrightnessBackend.disponivel },
        ler: { BrightnessBackend.ler() },
        escrever: { BrightnessBackend.escrever($0) },
        tique: { DockaStore.shared.tiqueDeBrilho() })

    static let volume = Deslizador(
        id: "volume",
        titulo: "Volume",
        rotulo: "Volume da saída de áudio",
        dica: "Arraste para ajustar o volume; toque para abrir os ajustes",
        avisoIndisponivel: "A saída de áudio atual não aceita controle de volume — saída digital e alguns HDMI entregam o volume ao aparelho do outro lado.",
        nota: "O nível é lido da saída de verdade e acompanha a troca de fone. Diferente do brilho, aqui a API é pública (CoreAudio): não pede permissão nenhuma e não corre o risco de sumir numa atualização. Volume zero silencia de fato, e subir a régua tira do mudo.",
        descricao: "Uma régua própria numa lateral da tela, igual à do brilho. Encoste o cursor na borda para revelá-la.",
        nivel: \.volumeLevel,
        borda: \.volumeEdge,
        alinhamento: \.volumeAlignment,
        ligado: \.volumeControl,
        bordaPadrao: .left,
        // aqui o ícone informa: volume zero e volume baixo são estados que o
        // usuário confunde, e o macOS resolve isso mudando as ondinhas
        simbolo: { Volume.simbolo(level: $0) },
        disponivel: { VolumeBackend.disponivel },
        ler: { VolumeBackend.ler() },
        escrever: { VolumeBackend.escrever($0) },
        tique: { DockaStore.shared.tiqueDeVolume() })
}

/// Escreve o nível no sistema e devolve o que o sistema de fato assumiu.
///
/// Ninguém guarda o valor pedido: escrevemos, relemos e mostramos o real. O
/// sistema encaixa em degraus de 1/16 e pode recusar (saída sem controle de
/// volume, brilho no limite), e mostrar o pedido em vez do obtido seria mentir
/// para o usuário. O tique sai daqui pelo mesmo motivo — ele marca degrau
/// atravessado de verdade, não intenção.
enum NivelDoSistema {
    static func aplicar(_ novo: Double, atual: Double, com d: Deslizador) -> Double {
        guard abs(novo - atual) > 0.0001 else { return atual }
        d.escrever(novo)
        let depois = d.ler() ?? novo
        if Deslizante.crossedStep(from: atual, to: depois) { d.tique() }
        return depois
    }
}
