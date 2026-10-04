import SwiftUI
import AppKit
import IOKit.ps
import DockaCore

// MARK: - Leitura dos contadores

/// Lê os contadores do sistema. Tudo API pública e sem permissão: Mach para
/// CPU e memória, IOKit para bateria, `getifaddrs` para rede e o próprio
/// FileManager para disco.
enum LeitorDoSistema {

    static func tiquesDeCPU() -> Metricas.TiquesDeCPU? {
        var n: natural_t = 0
        var info: processor_info_array_t?
        var tamanho: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &n, &info, &tamanho) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(tamanho) * MemoryLayout<integer_t>.stride))
        }
        // soma os núcleos: o painel mostra o Mac inteiro, não cada núcleo
        var t = Metricas.TiquesDeCPU(usuario: 0, sistema: 0, ocioso: 0, nice: 0)
        for c in 0..<Int(n) {
            let base = Int(CPU_STATE_MAX) * c
            t.usuario += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            t.sistema += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            t.ocioso  += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            t.nice    += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
        return t
    }

    static func memoriaEmUso() -> UInt64? {
        var vm = vm_statistics64()
        var n = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &n)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        var pagina: vm_size_t = 0
        host_page_size(mach_host_self(), &pagina)
        return Metricas.memoriaEmUso(internas: UInt64(vm.internal_page_count),
                                     descartaveis: UInt64(vm.purgeable_count),
                                     fixas: UInt64(vm.wire_count),
                                     comprimidas: UInt64(vm.compressor_page_count),
                                     tamanhoDaPagina: UInt64(pagina))
    }

    /// Disco de inicialização: livre "para uso importante" — o número que o
    /// Finder mostra, que já conta o espaço que o sistema libera sozinho.
    static func disco() -> (livre: UInt64, total: UInt64)? {
        let v = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let livre = v?.volumeAvailableCapacityForImportantUsage,
              let total = v?.volumeTotalCapacity else { return nil }
        return (UInt64(max(0, livre)), UInt64(max(0, total)))
    }

    struct Bateria {
        var fracao: Double
        var carregando: Bool
        var naTomada: Bool
        var minutos: Int?
    }

    /// `nil` num Mac sem bateria — aí o cartão some do painel.
    static func bateria() -> Bateria? {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let fontes = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        for fonte in fontes {
            guard let d = IOPSGetPowerSourceDescription(blob, fonte)?
                    .takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let atual = d[kIOPSCurrentCapacityKey] as? Int,
                  let maxima = d[kIOPSMaxCapacityKey] as? Int, maxima > 0 else { continue }
            let carregando = d[kIOPSIsChargingKey] as? Bool ?? false
            let tomada = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let chave = carregando ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            return Bateria(fracao: Double(atual) / Double(maxima), carregando: carregando,
                           naTomada: tomada, minutos: d[chave] as? Int)
        }
        return nil
    }

    /// Bytes recebidos e enviados, somando só as interfaces físicas, cada
    /// uma com o seu contador de 32 bits.
    static func contadoresDeRede() -> [String: (entrada: UInt64, saida: UInt64)] {
        var r: [String: (UInt64, UInt64)] = [:]
        var lista: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&lista) == 0 else { return [:] }
        defer { freeifaddrs(lista) }
        var p = lista
        while let a = p {
            defer { p = a.pointee.ifa_next }
            guard let endereco = a.pointee.ifa_addr,
                  endereco.pointee.sa_family == UInt8(AF_LINK),
                  let dados = a.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let nome = String(cString: a.pointee.ifa_name)
            guard Metricas.contaNoTrafego(nome) else { continue }
            r[nome] = (UInt64(dados.pointee.ifi_ibytes), UInt64(dados.pointee.ifi_obytes))
        }
        return r
    }
}

// MARK: - O estado do monitor

/// As leituras e o histórico, num objeto próprio: muda a cada 2 s, e no
/// `DockaStore` acordaria o TrayManager e todas as bandejas junto.
final class MonitorModelo: ObservableObject {
    static let shared = MonitorModelo()

    /// `shared` é o do app; o autoteste cria o seu, sem relógio.
    fileprivate init() {}

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoria: UInt64 = 0
    @Published private(set) var disco: (livre: UInt64, total: UInt64)?
    @Published private(set) var bateria: LeitorDoSistema.Bateria?
    @Published private(set) var entrada: Double = 0
    @Published private(set) var saida: Double = 0
    @Published private(set) var termico: ProcessInfo.ThermalState = .nominal

    @Published private(set) var historicoCPU = Historico()
    @Published private(set) var historicoMemoria = Historico()
    @Published private(set) var historicoEntrada = Historico()
    @Published private(set) var historicoSaida = Historico()

    let memoriaTotal = ProcessInfo.processInfo.physicalMemory
    static let intervalo: TimeInterval = 2

    private var relogio: Timer?
    private var ultimosTiques: Metricas.TiquesDeCPU?
    private var ultimaRede: [String: (entrada: UInt64, saida: UInt64)] = [:]
    private var ultimaLeitura: Date?
    /// Quem precisa das leituras agora: o painel aberto, a barra de menus.
    private var interessados: Set<String> = []

    /// Liga a coleta enquanto alguém olha. Sem interessados o relógio para —
    /// um monitor que mede o Mac não pode ser ele mesmo o que gasta CPU.
    func interesse(_ quem: String, _ quer: Bool) {
        if quer { interessados.insert(quem) } else { interessados.remove(quem) }
        if interessados.isEmpty {
            relogio?.invalidate()
            relogio = nil
        } else if relogio == nil {
            ler()
            let t = Timer(timeInterval: Self.intervalo, repeats: true) { [weak self] _ in self?.ler() }
            t.tolerance = 0.3
            RunLoop.main.add(t, forMode: .common)
            relogio = t
        }
    }

    fileprivate func ler() {
        let agora = Date()
        let segundos = ultimaLeitura.map { agora.timeIntervalSince($0) } ?? Self.intervalo
        ultimaLeitura = agora

        if let t = LeitorDoSistema.tiquesDeCPU() {
            if let antes = ultimosTiques {
                cpu = Metricas.usoDeCPU(de: antes, para: t)
                historicoCPU.adicionar(cpu)
            }
            ultimosTiques = t
        }
        if let m = LeitorDoSistema.memoriaEmUso() {
            memoria = m
            historicoMemoria.adicionar(Double(m) / Double(max(memoriaTotal, 1)))
        }

        let rede = LeitorDoSistema.contadoresDeRede()
        if !ultimaRede.isEmpty {
            var e: UInt64 = 0, s: UInt64 = 0
            for (nome, c) in rede {
                guard let antes = ultimaRede[nome] else { continue }
                e += Metricas.delta32(de: antes.entrada, para: c.entrada)
                s += Metricas.delta32(de: antes.saida, para: c.saida)
            }
            entrada = Double(e) / max(segundos, 0.5)
            saida = Double(s) / max(segundos, 0.5)
            historicoEntrada.adicionar(entrada)
            historicoSaida.adicionar(saida)
        }
        ultimaRede = rede

        disco = LeitorDoSistema.disco()
        bateria = LeitorDoSistema.bateria()
        termico = ProcessInfo.processInfo.thermalState
    }

    /// Duas leituras no contexto real do app, para conferir contra o `top`,
    /// o `vm_stat` e o `pmset`.
    static func autoteste() -> String {
        let m = MonitorModelo()
        m.ler()
        Thread.sleep(forTimeInterval: intervalo)
        m.ler()
        var linhas = [
            "cpu \(Metricas.porcentagem(m.cpu))",
            "memória \(Metricas.bytes(m.memoria, binario: true)) de \(Metricas.bytes(m.memoriaTotal, binario: true))",
            "rede ↓ \(Metricas.taxa(m.entrada)) ↑ \(Metricas.taxa(m.saida))",
        ]
        if let d = m.disco { linhas.append("disco \(Metricas.bytes(d.livre)) livres de \(Metricas.bytes(d.total))") }
        if let b = m.bateria {
            linhas.append("bateria \(Metricas.porcentagem(b.fracao)) carregando=\(b.carregando) tomada=\(b.naTomada) tempo=\(Metricas.tempo(minutos: b.minutos) ?? "-")")
        }
        linhas.append("térmico \(m.termico.rawValue)")
        return linhas.joined(separator: " | ")
    }

    /// O texto curto da barra de menus.
    func textoDaBarra(_ leitura: LeituraDaBarra) -> String? {
        switch leitura {
        case .nenhuma: return nil
        case .cpu:     return Metricas.porcentagem(cpu)
        case .memoria: return Metricas.bytes(memoria, binario: true)
        case .rede:    return "↓ " + Metricas.taxa(entrada)
        case .bateria: return bateria.map { Metricas.porcentagem($0.fracao) }
        }
    }
}

// MARK: - O painel

final class MonitorController {
    let state = TrayState()
    private var panel: NSPanel!
    private let store = DockaStore.shared
    private var hideDelay: TimeInterval = 0
    private var retirada: DispatchWorkItem?
    private var currentScreen: NSScreen? = NSScreen.main

    static let comprimento: CGFloat = 470
    static let espessura: CGFloat = 300

    init() { buildPanel() }

    private var edge: TrayEdge { Prateleira.edge(persisted: store.monitorBorda) }

    private func buildPanel() {
        panel = NSPanel(contentRect: .zero,
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
        panel.contentView = NSHostingView(
            rootView: MonitorView()
                .environmentObject(store)
                .environmentObject(state)
                .environmentObject(MonitorModelo.shared))
        layout()
    }

    func encerrar() {
        retirada?.cancel()
        MonitorModelo.shared.interesse("painel", false)
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
                               alignment: TrayAlignment(persisted: store.monitorAlinhamento),
                               offset: 24,
                               followDock: store.followDock,
                               extent: Self.comprimento,
                               thickness: Self.espessura),
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
        } else if state.pinned || TrayGeometry.isInsideTray(cursor: loc, trayFrame: f, edge: edge) {
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
        MonitorModelo.shared.interesse("painel", true)
        panel.orderFrontRegardless()
        withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                                   : .spring(duration: 0.42, bounce: 0.22)) {
            state.visible = true
        }
    }

    private func hide() {
        state.pinned = false
        MonitorModelo.shared.interesse("painel", false)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.32)) {
            state.visible = false
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.state.visible else { return }
            self.panel.orderOut(nil)
        }
        retirada = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func toggleFromHotKey() {
        if state.visible {
            hide()
        } else {
            currentScreen = telaSobOCursor()
            layout()
            state.pinned = true
            reveal()
        }
    }
}

// MARK: - A vista

struct MonitorView: View {
    @EnvironmentObject var store: DockaStore
    @EnvironmentObject var state: TrayState
    @EnvironmentObject var m: MonitorModelo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var edge: TrayEdge { Prateleira.edge(persisted: store.monitorBorda) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(Color.accentColor)
                Text("Sistema").font(.system(size: 13, weight: .semibold))
                Spacer()
                if m.termico.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    Label(m.termico == .critical ? "Muito quente" : "Quente",
                          systemImage: "thermometer.high")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            Cartao(titulo: "CPU", valor: Metricas.porcentagem(m.cpu), simbolo: "cpu") {
                Grafico(historico: m.historicoCPU, teto: 1, cor: .blue)
            }
            Cartao(titulo: "Memória",
                   valor: "\(Metricas.bytes(m.memoria, binario: true)) de \(Metricas.bytes(m.memoriaTotal, binario: true))",
                   simbolo: "memorychip") {
                Grafico(historico: m.historicoMemoria, teto: 1, cor: .purple)
            }
            Cartao(titulo: "Rede",
                   valor: "↓ \(Metricas.taxa(m.entrada))  ↑ \(Metricas.taxa(m.saida))",
                   simbolo: "network") {
                ZStack {
                    Grafico(historico: m.historicoEntrada, teto: nil, cor: .green)
                    Grafico(historico: m.historicoSaida, teto: nil, cor: .orange)
                }
            }
            HStack(spacing: 10) {
                if let d = m.disco, d.total > 0 {
                    Mini(titulo: "Disco", valor: "\(Metricas.bytes(d.livre)) livres",
                         fracao: 1 - Double(d.livre) / Double(d.total), simbolo: "internaldrive")
                }
                if let b = m.bateria {
                    Mini(titulo: b.carregando ? "Carregando" : (b.naTomada ? "Na tomada" : "Bateria"),
                         valor: Metricas.porcentagem(b.fracao)
                            + (Metricas.tempo(minutos: b.minutos).map { " · \($0)" } ?? ""),
                         fracao: b.fracao,
                         simbolo: b.carregando ? "battery.100.bolt" : "battery.75")
                }
            }
        }
        .padding(14)
        .frame(width: MonitorController.espessura - 20, height: MonitorController.comprimento - 20,
               alignment: .top)
        .dockGlass(cornerRadius: 18, tint: store.glassTint)
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .offset(x: state.visible || reduceMotion ? 0 : (edge == .left ? -340 : 340))
        .opacity(state.visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: edge == .left ? .leading : .trailing)
        .padding(edge == .left ? .leading : .trailing, 10)
        .ignoresSafeArea()
    }
}

private struct Cartao<Conteudo: View>: View {
    let titulo: String
    let valor: String
    let simbolo: String
    @ViewBuilder let conteudo: () -> Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(titulo, systemImage: simbolo)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valor)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            conteudo().frame(height: 42)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

private struct Mini: View {
    let titulo: String
    let valor: String
    let fracao: Double
    let simbolo: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(titulo, systemImage: simbolo)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(valor)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ProgressView(value: min(max(fracao, 0), 1))
                .progressViewStyle(.linear)
                .tint(.accentColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

/// Gráfico de linha do histórico, com a área embaixo levemente preenchida.
private struct Grafico: View {
    let historico: Historico
    let teto: Double?
    let cor: Color

    var body: some View {
        GeometryReader { g in
            let p = historico.pontos(largura: g.size.width, altura: g.size.height, teto: teto)
            if p.count > 1 {
                ZStack {
                    Path { c in
                        c.move(to: CGPoint(x: p[0].x, y: g.size.height))
                        p.forEach { c.addLine(to: $0) }
                        c.addLine(to: CGPoint(x: p[p.count - 1].x, y: g.size.height))
                        c.closeSubpath()
                    }
                    .fill(cor.opacity(0.18))
                    Path { c in
                        c.move(to: p[0])
                        p.dropFirst().forEach { c.addLine(to: $0) }
                    }
                    .stroke(cor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            } else {
                Text("Medindo…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}
