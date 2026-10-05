import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import DockaCore

// MARK: - Notificações

/// Os avisos que aparecem na tela, lidos da Central de Notificações pela
/// Acessibilidade. Só com a opção ligada; só na memória; apagados ao travar a
/// tela ou desligar a opção.
final class NotificacoesModelo: ObservableObject {
    static let shared = NotificacoesModelo()

    @Published private(set) var avisos: [NotificacoesDaIlha.Aviso] = []
    private var relogio: Timer?
    private var observadorDeTrava: NSObjectProtocol?

    func sincronizar() {
        let quer = DockaStore.shared.ilhaControl && DockaStore.shared.ilhaNotificacoes && Colagem.permitido
        if quer, relogio == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.olhar() }
            t.tolerance = 0.3
            RunLoop.main.add(t, forMode: .common)
            relogio = t
            observadorDeTrava = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                self?.avisos = []
            }
        } else if !quer, relogio != nil {
            relogio?.invalidate(); relogio = nil
            if let o = observadorDeTrava { DistributedNotificationCenter.default().removeObserver(o) }
            observadorDeTrava = nil
            avisos = []
        }
    }

    func limpar() { avisos = [] }

    /// Os avisos à vista agora. Cada um é um grupo `AXNotificationCenterBanner`
    /// na janela da Central, com os textos marcados title, subtitle e body.
    private func olhar() {
        guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return }
        var novos: [NotificacoesDaIlha.Aviso] = []
        let agora = Date()
        for w in Self.lista(AXUIElementCreateApplication(nc.processIdentifier), kAXWindowsAttribute) {
            Self.procurar(w, profundidade: 0) { banner in
                guard let id = Self.texto(banner, kAXIdentifierAttribute) else { return }
                var partes: [String: String] = [:]
                for f in Self.lista(banner, kAXChildrenAttribute) {
                    if let k = Self.texto(f, kAXIdentifierAttribute), let v = Self.texto(f, kAXValueAttribute) { partes[k] = v }
                }
                guard let titulo = partes["title"] else { return }
                let desc = Self.texto(banner, kAXDescriptionAttribute) ?? ""
                let app = NotificacoesDaIlha.app(descricao: desc, titulo: titulo, subtitulo: partes["subtitle"],
                                                 corpo: partes["body"]) ?? "Notificação"
                novos.append(.init(id: id, app: app, titulo: titulo, subtitulo: partes["subtitle"], corpo: partes["body"],
                                   chegou: agora))
            }
        }
        guard !novos.isEmpty else { return }
        let juntos = NotificacoesDaIlha.juntar(novos, a: avisos)
        if juntos != avisos { avisos = juntos }
    }

    private static func procurar(_ e: AXUIElement, profundidade: Int, _ achou: (AXUIElement) -> Void) {
        guard profundidade < 8 else { return }
        if texto(e, kAXSubroleAttribute) == "AXNotificationCenterBanner" { achou(e); return }
        for f in lista(e, kAXChildrenAttribute) { procurar(f, profundidade: profundidade + 1, achou) }
    }

    private static func texto(_ e: AXUIElement, _ k: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success, let s = v as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func lista(_ e: AXUIElement, _ k: String) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success else { return [] }
        return (v as? [AXUIElement]) ?? []
    }

    /// Só para o autoteste de desenho.
    func simular(_ l: [NotificacoesDaIlha.Aviso]) { avisos = l }
}

struct NotificacoesDaIlhaView: View {
    @ObservedObject private var m = NotificacoesModelo.shared
    @EnvironmentObject var store: DockaStore

    var body: some View {
        Group {
            if !store.ilhaNotificacoes {
                centro("Ver as notificações aqui?",
                       "A ilha guarda os avisos que aparecerem na tela daqui para a frente — só na memória, e apaga tudo quando a tela trava. Pede Acessibilidade.",
                       "Ligar") { store.ilhaNotificacoes = true }
            } else if !Colagem.permitido {
                centro("Falta a Acessibilidade", "É por ela que o Docka lê os avisos da tela.", "Abrir Privacidade") {
                    Colagem.abrirAjustesDePrivacidade()
                }
            } else if m.avisos.isEmpty {
                centro("Nada por aqui ainda", "Os avisos novos aparecem aqui assim que surgirem na tela.", nil, {})
            } else {
                lista
            }
        }
        .padding(.horizontal, 16).padding(.top, 6)
        .foregroundStyle(.white)
    }

    private func centro(_ t: String, _ d: String, _ botao: String?, _ acao: @escaping () -> Void) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "bell").font(.system(size: 20))
            Text(t).font(.system(size: 13, weight: .semibold))
            Text(d).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if let botao {
                Button(action: acao) {
                    Text(botao).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(m.avisos.count) recentes").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { m.limpar() } label: {
                    Text("Limpar").font(.system(size: 10.5, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12))).contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(m.avisos) { linha($0) }
                }
            }
        }
    }

    private func linha(_ a: NotificacoesDaIlha.Aviso) -> some View {
        let app = NSWorkspace.shared.runningApplications.first { $0.localizedName == a.app }
        return Button {
            app?.activate()
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Group {
                    if let i = app?.icon { Image(nsImage: i).resizable() } else { Image(systemName: "app.badge") }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(a.titulo).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text(a.chegou.formatted(date: .omitted, time: .shortened)).font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Text([a.subtitulo, a.corpo].compactMap { $0 }.joined(separator: " — "))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(a.app): \(a.titulo)")
    }
}

// MARK: - Espelho da câmera

/// A câmera ao vivo, para conferir a cara antes de uma chamada. Liga só com a
/// seção à vista ou o espelho flutuante aberto — a luz verde apaga junto.
final class CameraModelo: ObservableObject {
    static let shared = CameraModelo()

    let sessao = AVCaptureSession()
    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published private(set) var atual: AVCaptureDevice?
    @Published private(set) var estado = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var espelhar = true
    @Published private(set) var flutuante = false
    private var interessados: Set<String> = []
    private let fila = DispatchQueue(label: "docka.camera")
    private var painel: NSPanel?

    func listar() {
        let tipos: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: tipos, mediaType: .video, position: .unspecified).devices
        if atual == nil || !cameras.contains(where: { $0.uniqueID == atual?.uniqueID }) {
            atual = AVCaptureDevice.default(for: .video) ?? cameras.first
        }
    }

    func pedirAcesso() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async {
                self.estado = AVCaptureDevice.authorizationStatus(for: .video)
                self.reavaliar()
            }
        }
    }

    /// Quem quer a câmera ligada (a seção, o espelho flutuante).
    func interesse(_ quem: String, _ quer: Bool) {
        if quer { interessados.insert(quem) } else { interessados.remove(quem) }
        reavaliar()
    }

    func escolher(_ d: AVCaptureDevice) {
        atual = d
        configurar()
    }

    private func reavaliar() {
        estado = AVCaptureDevice.authorizationStatus(for: .video)
        guard estado == .authorized else { return }
        listar()
        if interessados.isEmpty {
            fila.async { if self.sessao.isRunning { self.sessao.stopRunning() } }
        } else {
            configurar()
        }
    }

    private func configurar() {
        guard let d = atual else { return }
        fila.async {
            self.sessao.beginConfiguration()
            self.sessao.inputs.forEach { self.sessao.removeInput($0) }
            if let e = try? AVCaptureDeviceInput(device: d), self.sessao.canAddInput(e) { self.sessao.addInput(e) }
            self.sessao.commitConfiguration()
            if !self.sessao.isRunning { self.sessao.startRunning() }
        }
    }

    // MARK: o espelho flutuante

    func alternarFlutuante() {
        if let p = painel {
            p.orderOut(nil)
            painel = nil
            flutuante = false
            interesse("flutuante", false)
            return
        }
        let tela = NSScreen.main?.visibleFrame ?? .zero
        let p = NSPanel(contentRect: NSRect(x: tela.maxX - 300, y: tela.maxY - 240, width: 280, height: 210),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hv = NSHostingView(rootView: EspelhoFlutuante(fechar: { [weak self] in self?.alternarFlutuante() })
            .environmentObject(self))
        hv.sizingOptions = []
        p.contentView = hv
        p.orderFrontRegardless()
        painel = p
        flutuante = true
        interesse("flutuante", true)
    }
}

/// A imagem da câmera, por uma camada de prévia do AVFoundation.
struct PreviaDaCamera: NSViewRepresentable {
    let sessao: AVCaptureSession
    let espelhar: Bool

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let camada = AVCaptureVideoPreviewLayer(session: sessao)
        camada.videoGravity = .resizeAspectFill
        v.layer = camada
        aplicar(camada)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        if let c = v.layer as? AVCaptureVideoPreviewLayer { aplicar(c) }
    }

    private func aplicar(_ c: AVCaptureVideoPreviewLayer) {
        guard let conexao = c.connection, conexao.isVideoMirroringSupported else { return }
        conexao.automaticallyAdjustsVideoMirroring = false
        conexao.isVideoMirrored = espelhar
    }
}

private struct EspelhoFlutuante: View {
    let fechar: () -> Void
    @EnvironmentObject var m: CameraModelo

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PreviaDaCamera(sessao: m.sessao, espelhar: m.espelhar)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Button(action: fechar) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.55)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Fechar o espelho")
        }
        .frame(width: 280, height: 210)
    }
}

struct CameraDaIlhaView: View {
    @ObservedObject private var m = CameraModelo.shared

    var body: some View {
        Group {
            switch m.estado {
            case .authorized: camera
            case .notDetermined:
                pedido("Conferir a câmera aqui?", "A imagem só aparece na ilha e não é gravada.", "Permitir") { m.pedirAcesso() }
            default:
                pedido("Sem acesso à câmera", "Libere o Docka em Privacidade e Segurança → Câmera.", "Abrir Ajustes") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 6)
        .foregroundStyle(.white)
        .onAppear { m.interesse("ilha", true) }
        .onDisappear { m.interesse("ilha", false) }
    }

    private func pedido(_ t: String, _ d: String, _ b: String, _ acao: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "web.camera").font(.system(size: 22))
            Text(t).font(.system(size: 13, weight: .semibold))
            Text(d).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            Button(action: acao) {
                Text(b).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color.white)).contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var camera: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if m.flutuante {
                    VStack(spacing: 6) {
                        Image(systemName: "pip").font(.system(size: 22))
                        Text("No espelho flutuante").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                } else {
                    PreviaDaCamera(sessao: m.sessao, espelhar: m.espelhar)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .frame(width: 256, height: 160)
            VStack(alignment: .leading, spacing: 8) {
                Text("Câmera").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                ForEach(m.cameras, id: \.uniqueID) { d in
                    Button { m.escolher(d) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: d.uniqueID == m.atual?.uniqueID ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(d.uniqueID == m.atual?.uniqueID ? Color.green : Color.white.opacity(0.4))
                            Text(d.localizedName).font(.system(size: 11.5)).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    pilula(m.espelhar ? "Espelhado" : "Como os outros veem", "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                        m.espelhar.toggle()
                    }
                    pilula(m.flutuante ? "Fechar espelho" : "Espelho flutuante", "pip.enter") { m.alternarFlutuante() }
                }
            }
        }
    }

    private func pilula(_ t: String, _ s: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 4) {
                Image(systemName: s).font(.system(size: 10, weight: .semibold))
                Text(t).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
