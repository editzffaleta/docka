import SwiftUI
import AppKit
import DockaCore

// MARK: - O vigia

/// Lê o sistema em ritmo lento e passa as leituras ao `VigiaDeAlertas`.
///
/// Dez segundos bastam: o alerta de CPU é sobre minutos seguidos, e disco e
/// bateria mudam devagar. Memória e temperatura nem são lidas — o sistema
/// avisa quando mudam, por evento.
final class VigiaController {
    private let store = DockaStore.shared
    private var vigia = VigiaDeAlertas()
    private var relogio: Timer?
    private var ultimosTiques: Metricas.TiquesDeCPU?
    private var voltas = 0
    private var fonteDeMemoria: DispatchSourceMemoryPressure?
    private var observadorTermico: NSObjectProtocol?

    static let intervalo: TimeInterval = 10

    init() {
        atualizarLimites()
        let t = Timer(timeInterval: Self.intervalo, repeats: true) { [weak self] _ in self?.ler() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        relogio = t
        ultimosTiques = LeitorDoSistema.tiquesDeCPU()

        // pressão de memória: o próprio kernel avisa, sem medir nada
        let fonte = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical],
                                                            queue: .main)
        fonte.setEventHandler { [weak self, weak fonte] in
            guard let self, let fonte, self.store.alertaMemoria else { return }
            let critica = fonte.data.contains(.critical)
            self.mostrar(self.vigia.pressaoDeMemoria(critica: critica, em: Date()))
        }
        fonte.resume()
        fonteDeMemoria = fonte

        observadorTermico = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.store.alertaTemperatura else { return }
            self.mostrar(self.vigia.temperatura(nivel: ProcessInfo.processInfo.thermalState.rawValue))
        }
    }

    func encerrar() {
        relogio?.invalidate()
        relogio = nil
        fonteDeMemoria?.cancel()
        fonteDeMemoria = nil
        if let o = observadorTermico { NotificationCenter.default.removeObserver(o) }
        observadorTermico = nil
    }

    func atualizarLimites() {
        vigia.limites = LimitesDeAlerta(cpu: store.alertaCPULimite,
                                        cpuMinutos: store.alertaCPUMinutos,
                                        discoLivreGB: store.alertaDiscoGB,
                                        bateria: store.alertaBateriaLimite)
    }

    private func ler() {
        let agora = Date()
        voltas += 1

        if let t = LeitorDoSistema.tiquesDeCPU() {
            if let antes = ultimosTiques, store.alertaCPU {
                mostrar(vigia.cpu(Metricas.usoDeCPU(de: antes, para: t), em: agora))
            }
            ultimosTiques = t
        }
        if store.alertaBateria, let b = LeitorDoSistema.bateria() {
            mostrar(vigia.bateria(b.fracao, carregando: b.carregando, naTomada: b.naTomada))
        }
        // disco a cada minuto: espaço livre não some em dez segundos
        if store.alertaDisco, voltas % 6 == 1, let d = LeitorDoSistema.disco() {
            mostrar(vigia.disco(livre: d.livre))
        }
    }

    private func mostrar(_ alerta: Alerta?) {
        guard let alerta else { return }
        AvisoController.shared.mostrar(alerta)
    }

    /// As leituras REAIS passando pelo vigia, com limites forçados para
    /// disparar — confere o caminho inteiro sem esperar a CPU esquentar e
    /// sem mostrar nada na tela.
    static func autoteste() -> String {
        var v = VigiaDeAlertas(limites: LimitesDeAlerta(cpu: 0, cpuMinutos: 0,
                                                       discoLivreGB: 100_000, bateria: 1))
        var saida: [String] = []
        if let a = LeitorDoSistema.tiquesDeCPU() {
            Thread.sleep(forTimeInterval: 1)
            if let b = LeitorDoSistema.tiquesDeCPU(),
               let al = v.cpu(Metricas.usoDeCPU(de: a, para: b), em: Date()) {
                saida.append("\(al.tipo.rawValue): \(al.titulo) — \(al.mensagem)")
            }
        }
        if let d = LeitorDoSistema.disco(), let al = v.disco(livre: d.livre) {
            saida.append("\(al.tipo.rawValue): \(al.titulo) — \(al.mensagem)")
        }
        if let b = LeitorDoSistema.bateria() {
            let al = v.bateria(b.fracao, carregando: b.carregando, naTomada: b.naTomada)
            saida.append(al.map { "\($0.tipo.rawValue): \($0.titulo)" }
                         ?? "bateria: sem aviso (na tomada = \(b.naTomada), como deve ser)")
        }
        if let al = v.pressaoDeMemoria(critica: false, em: Date()) {
            saida.append("\(al.tipo.rawValue): \(al.titulo)")
        }
        saida.append("térmico agora: \(ProcessInfo.processInfo.thermalState.rawValue)")
        return saida.joined(separator: "\n")
    }
}

// MARK: - O cartão de aviso

/// Um cartão de vidro no canto superior direito, como uma notificação.
///
/// Próprio, e não `UserNotifications`: as notificações do sistema pedem
/// autorização na primeira vez, e os recursos desta fase não pedem nada.
final class AvisoController {
    static let shared = AvisoController()

    private var panel: NSPanel?
    private let estado = AvisoEstado()
    private var fila: [Alerta] = []
    private var retirada: DispatchWorkItem?

    static let largura: CGFloat = 360
    static let altura: CGFloat = 96
    /// Tempo na tela antes de sumir sozinho.
    static let duracao: TimeInterval = 8

    func mostrar(_ alerta: Alerta) {
        // retorno de captura troca o que está na tela: duas capturas seguidas
        // não podem engolir o aviso da segunda
        if alerta.tipo == .captura, estado.alerta?.tipo == .captura {
            estado.alerta = alerta
            retirada?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.fechar() }
            retirada = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duracao, execute: item)
            return
        }
        // o mesmo tipo já na fila não entra de novo
        guard estado.alerta?.tipo != alerta.tipo,
              !fila.contains(where: { $0.tipo == alerta.tipo }) else { return }
        if estado.alerta == nil { exibir(alerta) } else { fila.append(alerta) }
    }

    private func construir() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.largura, height: Self.altura),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isFloatingPanel = true
        p.level = .mainMenu
        p.contentView = NSHostingView(
            rootView: AvisoView(fechar: { [weak self] in self?.fechar() })
                .environmentObject(estado)
                .environmentObject(DockaStore.shared))
        return p
    }

    private func exibir(_ alerta: Alerta) {
        let p = panel ?? construir()
        panel = p
        let loc = NSEvent.mouseLocation
        let tela = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
        if let v = tela?.visibleFrame {
            p.setFrame(NSRect(x: v.maxX - Self.largura - 8, y: v.maxY - Self.altura - 8,
                              width: Self.largura, height: Self.altura), display: true)
        }
        estado.alerta = alerta
        p.orderFrontRegardless()
        DockaStore.shared.playSound("Glass", volume: 0.5)
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { estado.visivel = true }

        retirada?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.fechar() }
        retirada = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duracao, execute: item)
    }

    func fechar() {
        retirada?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { estado.visivel = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.estado.alerta = nil
            if self.fila.isEmpty {
                self.panel?.orderOut(nil)
            } else {
                self.exibir(self.fila.removeFirst())
            }
        }
    }

    /// O que o botão do aviso abre, se houver.
    static func acao(para tipo: Alerta.Tipo) -> (titulo: String, abrir: () -> Void)? {
        switch tipo {
        case .cpu, .memoria, .temperatura:
            return ("Monitor de Atividade", {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                    configuration: .init(), completionHandler: nil)
            })
        case .disco:
            return ("Armazenamento", {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                    NSWorkspace.shared.open(url)
                }
            })
        case .bateria, .captura:
            return nil
        }
    }
}

final class AvisoEstado: ObservableObject {
    @Published var alerta: Alerta?
    @Published var visivel = false
}

struct AvisoView: View {
    let fechar: () -> Void
    @EnvironmentObject var estado: AvisoEstado
    @EnvironmentObject var store: DockaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let a = estado.alerta {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: a.simbolo)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.gradient))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.titulo).font(.system(size: 13, weight: .semibold))
                        Text(a.mensagem)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let acao = AvisoController.acao(para: a.tipo) {
                            Button("Abrir \(acao.titulo)") { acao.abrir(); fechar() }
                                .buttonStyle(.link)
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    Spacer(minLength: 0)
                    Button(action: fechar) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dispensar")
                }
                .padding(12)
                .frame(width: AvisoController.largura - 16, alignment: .leading)
                .dockGlass(cornerRadius: 16, tint: store.glassTint)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .offset(x: estado.visivel || reduceMotion ? 0 : 380)
        .opacity(estado.visivel ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .ignoresSafeArea()
    }
}
