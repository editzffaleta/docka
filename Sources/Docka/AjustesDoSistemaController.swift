import AppKit
import CoreBluetooth
import DockaCore

/// Pequenos ajustes do sistema: Espaços em ordem fixa, o Música que abre
/// sozinho, o Bluetooth no repouso e a aceleração do ponteiro.
final class AjustesDoSistemaController {
    static let shared = AjustesDoSistemaController()

    private var store: DockaStore { .shared }
    private var observadores: [NSObjectProtocol] = []
    private let chaveBluetooth = "docka.bluetoothTurnedOffBySleep"
    private let chaveAceleracaoOriginal = "docka.pointerAccelerationOriginal"

    func comecar() {
        let ws = NSWorkspace.shared.notificationCenter
        observadores = [
            ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.abriu(app)
            },
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.vaiDormir()
            },
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.acordou()
            },
        ]
        aplicarAceleracao()
    }

    // MARK: Espaços em ordem fixa

    /// O macOS reordena os Espaços pelo uso recente quando `mru-spaces` é
    /// verdadeiro (o padrão). Lido do próprio Dock, não guardado no Docka.
    static var espacosFixos: Bool {
        get {
            let v = CFPreferencesCopyAppValue("mru-spaces" as CFString, "com.apple.dock" as CFString) as? Bool
            return v == false
        }
        set {
            CFPreferencesSetAppValue("mru-spaces" as CFString, (!newValue) as CFBoolean, "com.apple.dock" as CFString)
            CFPreferencesAppSynchronize("com.apple.dock" as CFString)
            // o Dock só lê a opção ao abrir: reinicia (ele volta sozinho)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            p.arguments = ["Dock"]
            try? p.run()
        }
    }

    // MARK: o Música que abre sozinho

    private func abriu(_ app: NSRunningApplication) {
        guard store.bloquearMusica, app.bundleIdentifier == "com.apple.Music" else { return }
        // quem abre de propósito traz o app para a frente; espera um instante
        // para o macOS terminar de ativar antes de decidir
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard !app.isTerminated,
                  AjustesDoSistema.fecharMusica(estaNaFrente: app.isActive, abertoPorVoce: false) else { return }
            app.terminate()
        }
    }

    // MARK: Bluetooth no repouso

    private typealias LerBT = @convention(c) () -> Int32
    private typealias MudarBT = @convention(c) (Int32) -> Void
    private static let bt = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)
    private static var lerBT: LerBT? { dlsym(bt, "IOBluetoothPreferenceGetControllerPowerState").map { unsafeBitCast($0, to: LerBT.self) } }
    private static var mudarBT: MudarBT? { dlsym(bt, "IOBluetoothPreferenceSetControllerPowerState").map { unsafeBitCast($0, to: MudarBT.self) } }

    /// Mexer no Bluetooth pede a permissão de Bluetooth: pedida ao ligar a opção.
    private var gerente: CBCentralManager?
    func pedirPermissaoDeBluetooth() {
        guard CBManager.authorization == .notDetermined else { return }
        gerente = CBCentralManager(delegate: nil, queue: nil)
    }

    static var bluetoothPermitido: Bool { CBManager.authorization == .allowedAlways }

    private func vaiDormir() {
        guard store.bluetoothNoRepouso, Self.bluetoothPermitido, let ler = Self.lerBT, let mudar = Self.mudarBT else { return }
        let r = AjustesDoSistema.aoDormir(ligado: ler() != 0)
        if r.desligar { mudar(0) }
        UserDefaults.standard.set(r.lembrar, forKey: chaveBluetooth)
    }

    private func acordou() {
        if AjustesDoSistema.aoAcordar(desligadoPeloDocka: UserDefaults.standard.bool(forKey: chaveBluetooth)),
           Self.bluetoothPermitido, let mudar = Self.mudarBT {
            mudar(1)
        }
        UserDefaults.standard.set(false, forKey: chaveBluetooth)
        // depois do repouso o sistema pode voltar a aceleração ao padrão
        aplicarAceleracao()
    }

    // MARK: aceleração do ponteiro

    private typealias Criar = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias LerHID = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias MudarHID = @convention(c) (AnyObject, CFString, CFTypeRef) -> Bool
    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static let cliente: AnyObject? = dlsym(iokit, "IOHIDEventSystemClientCreateSimpleClient")
        .flatMap { unsafeBitCast($0, to: Criar.self)(kCFAllocatorDefault)?.takeRetainedValue() }
    private static let chaveHID = "HIDMouseAcceleration" as CFString

    /// A aceleração do mouse agora, como o sistema guarda (0,875 = padrão de fábrica perto disso).
    static var aceleracaoAtual: Double? {
        guard let c = cliente, let f = dlsym(iokit, "IOHIDEventSystemClientCopyProperty"),
              let v = unsafeBitCast(f, to: LerHID.self)(c, chaveHID)?.takeRetainedValue() as? NSNumber else { return nil }
        return AjustesDoSistema.dePontoFixo(v.int32Value)
    }

    @discardableResult
    private static func definirAceleracao(_ v: Double) -> Bool {
        guard let c = cliente, let f = dlsym(iokit, "IOHIDEventSystemClientSetProperty") else { return false }
        return unsafeBitCast(f, to: MudarHID.self)(c, chaveHID, NSNumber(value: AjustesDoSistema.pontoFixo(v)))
    }

    /// Liga: guarda o valor de antes (uma vez) e aplica o escolhido.
    /// Desliga: devolve o valor de antes.
    func aplicarAceleracao() {
        let d = UserDefaults.standard
        if store.aceleracaoControl {
            if d.object(forKey: chaveAceleracaoOriginal) == nil, let atual = Self.aceleracaoAtual {
                d.set(atual, forKey: chaveAceleracaoOriginal)
            }
            Self.definirAceleracao(AjustesDoSistema.limitar(store.aceleracao))
        } else if let original = d.object(forKey: chaveAceleracaoOriginal) as? Double {
            Self.definirAceleracao(original)
            d.removeObject(forKey: chaveAceleracaoOriginal)
        }
    }
}
