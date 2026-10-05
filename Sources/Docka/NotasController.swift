import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DockaCore

// MARK: - As notas

/// As notas e a aba selecionada, gravadas num arquivo próprio.
///
/// Arquivo, e não UserDefaults: uma nota pode crescer sem limite, e o plist de
/// preferências é lido inteiro a cada início — inclusive pelo `defaults`. Fica
/// fora do `DockaStore` porque cada tecla publicaria no store, e o store
/// acorda o TrayManager.
final class NotasModelo: ObservableObject {
    static let shared = NotasModelo()

    @Published private(set) var notas: [Nota] = [Nota()]
    @Published var selecionada: UUID

    private var gravacao: DispatchWorkItem?

    static var arquivo: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Docka", isDirectory: true)
                   .appendingPathComponent("notas.json")
    }

    private struct Gravado: Codable {
        var notas: [Nota]
        var selecionada: UUID?
    }

    private init() {
        let lidas = (try? Data(contentsOf: Self.arquivo))
            .flatMap { try? JSONDecoder().decode(Gravado.self, from: $0) }
        let notas = BlocoDeNotas.garantirUma(lidas?.notas ?? [])
        self.notas = notas
        selecionada = notas.first { $0.id == lidas?.selecionada }?.id ?? notas[0].id
    }

    var atual: Nota { notas.first { $0.id == selecionada } ?? notas[0] }

    var texto: String {
        get { atual.texto }
        set {
            guard let i = notas.firstIndex(where: { $0.id == selecionada }),
                  notas[i].texto != newValue else { return }
            notas[i].texto = newValue
            notas[i].editadaEm = Date()
            agendarGravacao()
        }
    }

    var podeCriar: Bool { notas.count < BlocoDeNotas.maximoDeNotas }

    func nova() {
        guard podeCriar else { return }
        let n = Nota()
        notas.append(n)
        selecionada = n.id
        agendarGravacao()
    }

    func fechar(_ id: UUID) {
        let r = BlocoDeNotas.remover(id, de: notas)
        notas = r.notas
        selecionada = r.selecionada
        agendarGravacao()
    }

    func selecionar(_ id: UUID) {
        selecionada = id
        agendarGravacao()
    }

    func alternarTarefa(linha: Int) {
        texto = BlocoDeNotas.alternarTarefa(texto, linha: linha)
    }

    /// Grava meio segundo depois da última tecla: gravar a cada tecla seria
    /// I/O por caractere, e esperar demais arrisca perder o que acabou de ser
    /// escrito se o Mac desligar.
    private func agendarGravacao() {
        gravacao?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.gravarAgora() }
        gravacao = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// Chamado também ao encerrar o Docka, para não perder o último meio segundo.
    func gravarAgora() {
        gravacao?.cancel()
        gravacao = nil
        let dados = Gravado(notas: notas, selecionada: selecionada)
        guard let json = try? JSONEncoder().encode(dados) else { return }
        let url = Self.arquivo
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? json.write(to: url, options: .atomic)
    }
}

// MARK: - O painel

/// Painel que aceita teclado sem ativar o Docka — como o Spotlight.
///
/// Um painel sem borda recusa virar janela-chave por padrão, e aí o que se
/// digita vai para o app da frente. Não-ativante e com `canBecomeKey`, ele
/// recebe as teclas enquanto o app em que a pessoa estava continua o ativo.
class PainelDeNotas: NSPanel {
    var aoEsc: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { aoEsc?() }

    /// Entrega o primeiro campo de texto ao teclado, depois do layout.
    ///
    /// O foco do SwiftUI sozinho não chega num painel que não ativa o
    /// Docka: na primeira abertura o pedido nem é visto, e nas seguintes o
    /// @FocusState já "estava" verdadeiro — o campo ficava sem cursor e o
    /// que se digitava se perdia.
    func focarCampo() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let campo = Self.campo(em: self.contentView) else { return }
            self.makeFirstResponder(campo)
        }
    }

    private static func campo(em v: NSView?) -> NSTextField? {
        guard let v else { return nil }
        if let t = v as? NSTextField, t.isEditable { return t }
        for f in v.subviews { if let t = campo(em: f) { return t } }
        return nil
    }
}

final class NotasEstado: ObservableObject {
    @Published var visible = false
    @Published var pinned = false
    @Published var previa = false
    /// Muda para pedir foco no editor — o atalho abre já pronto para digitar.
    @Published var pedidoDeFoco = 0
}

final class NotasController {
    let state = NotasEstado()
    private var panel: PainelDeNotas!
    private let store = DockaStore.shared
    private var hideDelay: TimeInterval = 0
    private var retirada: DispatchWorkItem?
    private var currentScreen: NSScreen? = NSScreen.main

    init() { buildPanel() }

    private var edge: TrayEdge { BlocoDeNotas.edge(persisted: store.notasBorda) }

    private func buildPanel() {
        panel = PainelDeNotas(contentRect: .zero,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        // depois de isFloatingPanel — ver o TrayController
        panel.level = .mainMenu
        panel.aoEsc = { [weak self] in self?.hide() }
        panel.contentView = NSHostingView(
            rootView: NotasView(exportar: { [weak self] in self?.exportar() })
                .environmentObject(store)
                .environmentObject(state)
                .environmentObject(NotasModelo.shared))
        layout()
    }

    func encerrar() {
        retirada?.cancel()
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func layout() {
        guard let screen = currentScreen else { return }
        switch TrayAppearance(persisted: store.appearance) {
        case .automatico: panel.appearance = nil
        case .claro:      panel.appearance = NSAppearance(named: .aqua)
        case .escuro:     panel.appearance = NSAppearance(named: .darkAqua)
        }
        panel.setFrame(
            TrayGeometry.frame(screenFrame: screen.frame,
                               visibleFrame: screen.visibleFrame,
                               edge: edge,
                               alignment: TrayAlignment(persisted: store.notasAlinhamento),
                               offset: 24,
                               followDock: store.followDock,
                               extent: BlocoDeNotas.comprimento,
                               thickness: BlocoDeNotas.espessura),
            display: true)
    }

    private func telaSobOCursor() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
    }

    func tick() {
        guard store.onboarded else { return }
        let loc = NSEvent.mouseLocation
        if !state.visible, let s = telaSobOCursor(), s != currentScreen {
            currentScreen = s
            layout()
        }
        guard let screen = currentScreen else { return }
        let f = panel.frame

        if !state.visible {
            if TrayGeometry.shouldReveal(cursor: loc, trayFrame: f,
                                         screenFrame: screen.frame, edge: edge,
                                         pressureZone: store.pressureZone) {
                reveal()
            }
            return
        }
        // Escrevendo, o cursor costuma ir para longe — e o bloco não pode sumir
        // no meio da frase. Enquanto ele tem o teclado, fica; clicar em outro
        // app tira o teclado dele, e aí volta a valer a regra da borda.
        if state.pinned || panel.isKeyWindow
            || TrayGeometry.isInsideTray(cursor: loc, trayFrame: f, edge: edge) {
            hideDelay = 0
        } else {
            hideDelay += 0.05
            if hideDelay > 0.35 { hide() }
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func reveal() {
        hideDelay = 0
        retirada?.cancel(); retirada = nil
        panel.orderFrontRegardless()
        withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                                   : .spring(duration: 0.42, bounce: 0.22)) {
            state.visible = true
        }
    }

    private func hide() {
        state.pinned = false
        NotasModelo.shared.gravarAgora()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.32)) {
            state.visible = false
        }
        // devolve o teclado já: com o painel sumindo, as teclas seguintes têm
        // de ir para o app que a pessoa estava usando
        panel.resignKey()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.state.visible else { return }
            self.panel.orderOut(nil)
        }
        retirada = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// O atalho abre pronto para digitar — o motivo de ter um atalho para
    /// notas é anotar sem tirar a mão do teclado.
    func toggleFromHotKey() {
        if state.visible && panel.isKeyWindow {
            hide()
        } else {
            if !state.visible {
                currentScreen = telaSobOCursor()
                layout()
                reveal()
            }
            state.pinned = true
            state.previa = false
            panel.makeKey()
            state.pedidoDeFoco += 1
        }
    }

    /// Salva a nota atual como .md. O painel desce de nível enquanto o
    /// diálogo está aberto: no nível da barra de menus, ele cobriria o próprio
    /// diálogo de salvar.
    private func exportar() {
        let nota = NotasModelo.shared.atual
        let dialogo = NSSavePanel()
        dialogo.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        dialogo.nameFieldStringValue = nota.titulo == "Nota vazia" ? "Nota.md" : "\(nota.titulo).md"
        state.pinned = true
        panel.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        let r = dialogo.runModal()
        panel.level = .mainMenu
        if r == .OK, let url = dialogo.url {
            try? nota.texto.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - A vista

struct NotasView: View {
    let exportar: () -> Void
    @EnvironmentObject var store: DockaStore
    @EnvironmentObject var state: NotasEstado
    @EnvironmentObject var modelo: NotasModelo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focado: Bool

    private var edge: TrayEdge { BlocoDeNotas.edge(persisted: store.notasBorda) }

    var body: some View {
        VStack(spacing: 0) {
            abas
            Divider().opacity(0.5)
            Group {
                if state.previa {
                    PreviaMarkdown(texto: modelo.texto) { modelo.alternarTarefa(linha: $0) }
                } else {
                    editor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.5)
            rodape
        }
        .frame(width: BlocoDeNotas.espessura - 20, height: BlocoDeNotas.comprimento - 20)
        .dockGlass(cornerRadius: 18, tint: store.glassTint)
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .offset(x: state.visible || reduceMotion ? 0 : (edge == .left ? -420 : 420))
        .opacity(state.visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: edge == .left ? .leading : .trailing)
        .padding(edge == .left ? .leading : .trailing, 10)
        .ignoresSafeArea()
        .onChange(of: state.pedidoDeFoco) { _, _ in focado = true }
    }

    private var editor: some View {
        TextEditor(text: Binding(get: { modelo.texto }, set: { modelo.texto = $0 }))
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .focused($focado)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .overlay(alignment: .topLeading) {
                if modelo.texto.isEmpty {
                    Text("Escreva aqui. # vira título, - [ ] vira tarefa.")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
    }

    private var abas: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(modelo.notas) { nota in
                        Aba(nota: nota, selecionada: nota.id == modelo.selecionada,
                            podeFechar: modelo.notas.count > 1 || !nota.texto.isEmpty)
                    }
                }
                .padding(.vertical, 1)
            }
            Button {
                modelo.nova()
                state.previa = false
                focado = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(!modelo.podeCriar)
            .help(modelo.podeCriar ? "Nova nota" : "Limite de \(BlocoDeNotas.maximoDeNotas) notas")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var rodape: some View {
        HStack(spacing: 10) {
            Button {
                state.previa.toggle()
                if !state.previa { focado = true }
            } label: {
                Label(state.previa ? "Editar" : "Ver",
                      systemImage: state.previa ? "pencil" : "eye")
            }
            .buttonStyle(.plain)
            .help(state.previa ? "Voltar a editar" : "Ver com a formatação do Markdown")

            Text(contagem)
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Copiar a nota") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(modelo.texto, forType: .string)
                }
                Button("Salvar como Markdown…") { exportar() }
                Divider()
                Button("Mostrar o arquivo das notas") {
                    NSWorkspace.shared.activateFileViewerSelecting([NotasModelo.arquivo])
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var contagem: String {
        let p = modelo.atual.palavras
        return p == 1 ? "1 palavra" : "\(p) palavras"
    }
}

private struct Aba: View {
    let nota: Nota
    let selecionada: Bool
    let podeFechar: Bool
    @EnvironmentObject var modelo: NotasModelo
    @State private var sobre = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                modelo.selecionar(nota.id)
            } label: {
                Text(nota.titulo)
                    .font(.system(size: 11, weight: selecionada ? .semibold : .regular))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            if podeFechar && (sobre || selecionada) {
                Button {
                    modelo.fechar(nota.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(nota.texto.isEmpty ? "Fechar" : "Apagar esta nota")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(selecionada ? 0.14 : (sobre ? 0.06 : 0))))
        .onHover { sobre = $0 }
    }
}

// MARK: - Pré-visualização

private struct PreviaMarkdown: View {
    let texto: String
    let marcar: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(Markdown.blocos(texto).enumerated()), id: \.offset) { _, bloco in
                    vista(bloco)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .textSelection(.enabled)
        }
    }

    /// Negrito, itálico, código e links de dentro da linha ficam com o
    /// sistema; se a linha não for Markdown válido, vai como texto puro.
    private func inline(_ s: String) -> Text {
        let opcoes = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: s, options: opcoes) { return Text(a) }
        return Text(s)
    }

    @ViewBuilder
    private func vista(_ bloco: Markdown.Bloco) -> some View {
        switch bloco {
        case .titulo(let nivel, let t):
            inline(t).font(.system(size: [0, 20, 16, 14][nivel], weight: .bold))
                .padding(.top, nivel == 1 ? 4 : 2)
        case .item(let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(t)
            }
        case .numerado(let n, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(n).").foregroundStyle(.secondary).monospacedDigit()
                inline(t)
            }
        case .tarefa(let feita, let t, let linha):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Button, e não onTapGesture: num painel não-ativante gesto
                // cru não recebe clique (ver ArrastoAppKit)
                Button { marcar(linha) } label: {
                    Image(systemName: feita ? "checkmark.square.fill" : "square")
                        .foregroundStyle(feita ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                inline(t)
                    .strikethrough(feita)
                    .foregroundStyle(feita ? .secondary : .primary)
            }
        case .citacao(let t):
            inline(t)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.secondary.opacity(0.5)).frame(width: 2)
                }
        case .codigo(let t):
            Text(t)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
        case .divisor:
            Divider().padding(.vertical, 4)
        case .paragrafo(let t):
            inline(t)
        case .vazio:
            Spacer().frame(height: 4)
        }
    }
}
