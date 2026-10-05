import AppKit
import DockaCore

/// Executa as ações rápidas. Só esvaziar o Lixo pede permissão (controlar o
/// Finder); as outras são ferramentas de linha de comando do sistema, APIs
/// públicas do NSWorkspace e funções do sistema resolvidas em runtime —
/// travar a tela, claro/escuro, Night Shift e o Dock automático.
enum AcoesRapidasBackend {

    /// A ação existe nesta versão do macOS? Só a de travar depende de API
    /// privada; se ela sumir, a ação some do menu em vez de falhar calada.
    static func disponivel(_ acao: AcaoRapida) -> Bool {
        switch acao {
        case .travarTela:     return travar != nil
        case .aparencia:      return mudarAparencia != nil
        case .nightShift:     return NightShift.disponivel
        case .dockAutomatico: return lerDock != nil && mudarDock != nil
        default:              return true
        }
    }

    /// O estado das alternâncias; `nil` para as ações que só executam.
    static func ligada(_ acao: AcaoRapida) -> Bool? {
        switch acao {
        case .iconesDaMesa:    return !iconesDaMesaVisiveis
        case .aparencia:       return modoEscuro
        case .nightShift:      return NightShift.ligado
        case .dockAutomatico:  return lerDock?() ?? false
        case .arquivosOcultos: return arquivosOcultosVisiveis
        default:               return nil
        }
    }

    static func executar(_ acao: AcaoRapida) {
        switch acao {
        case .travarTela:     travar?()
        case .apagarTelas:    rodar("/usr/bin/pmset", ["displaysleepnow"])
        case .protecaoDeTela: abrirProtecaoDeTela()
        case .repouso:        rodar("/usr/bin/pmset", ["sleepnow"])
        case .ejetarDiscos:   ejetarTodos()
        case .iconesDaMesa:   alternarIconesDaMesa()
        case .aparencia:      mudarAparencia?(!modoEscuro)
        case .nightShift:     NightShift.ligado.toggle()
        case .dockAutomatico: if let ler = lerDock, let mudar = mudarDock { mudar(!ler()) }
        case .arquivosOcultos: alternarArquivosOcultos()
        case .esvaziarLixo:   esvaziarLixo()
        }
    }

    // MARK: claro e escuro

    private typealias MudarAparencia = @convention(c) (Bool) -> Void
    private static let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    /// A função que a própria Central de Controle usa. A alternativa pública
    /// seria pedir aos Eventos do Sistema — e isso exige a permissão de
    /// Automação.
    private static let mudarAparencia: ((Bool) -> Void)? = {
        guard let s = dlsym(skylight, "SLSSetAppearanceThemeLegacy") else { return nil }
        let f = unsafeBitCast(s, to: MudarAparencia.self)
        return { f($0) }
    }()

    static var modoEscuro: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    // MARK: Dock automático

    private typealias LerDock = @convention(c) () -> Bool
    private typealias MudarDock = @convention(c) (Bool) -> Void
    private static let servicos = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
    /// As funções que o ⌥⌘D chama: o Dock troca na hora, sem reiniciar.
    private static let lerDock: (() -> Bool)? = dlsym(servicos, "CoreDockGetAutoHideEnabled")
        .map { s in let f = unsafeBitCast(s, to: LerDock.self); return { f() } }
    private static let mudarDock: ((Bool) -> Void)? = dlsym(servicos, "CoreDockSetAutoHideEnabled")
        .map { s in let f = unsafeBitCast(s, to: MudarDock.self); return { f($0) } }

    // MARK: arquivos ocultos

    static var arquivosOcultosVisiveis: Bool {
        let valor = CFPreferencesCopyAppValue("AppleShowAllFiles" as CFString, finder)
        switch valor {
        case let b as Bool:   return b
        case let s as String: return ["1", "true", "yes"].contains(s.lowercased())
        default:              return false
        }
    }

    /// Como os ícones da mesa: grava no Finder e o reinicia para reler.
    private static func alternarArquivosOcultos() {
        CFPreferencesSetAppValue("AppleShowAllFiles" as CFString, (!arquivosOcultosVisiveis) as CFBoolean, finder)
        CFPreferencesAppSynchronize(finder)
        rodar("/usr/bin/killall", ["Finder"])
    }

    // MARK: Lixo

    /// Pergunta antes: o que sai do Lixo não volta. Quem esvazia é o Finder,
    /// do jeito dele — com o som e o aviso de arquivo em uso.
    private static func esvaziarLixo() {
        let alerta = NSAlert()
        alerta.messageText = "Esvaziar o Lixo?"
        alerta.informativeText = "Tudo o que está no Lixo será apagado para sempre."
        alerta.alertStyle = .warning
        alerta.addButton(withTitle: "Esvaziar")
        alerta.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        guard alerta.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var erro: NSDictionary?
            NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&erro)
            guard let erro else { return }
            let codigo = erro[NSAppleScript.errorNumber] as? Int ?? 0
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "O Lixo não foi esvaziado"
                a.informativeText = codigo == -1743
                    ? "O Docka não tem permissão para controlar o Finder. Libere em Ajustes do Sistema → Privacidade e Segurança → Automação."
                    : (erro[NSAppleScript.errorMessage] as? String ?? "O Finder recusou (código \(codigo)).")
                NSApp.activate(ignoringOtherApps: true)
                a.runModal()
            }
        }
    }

    // MARK: travar

    private typealias FuncaoTravar = @convention(c) () -> Int32

    /// `SACLockScreenImmediate`, do login.framework — o que o ⌃⌘Q chama. A
    /// alternativa pública (apagar a tela) só trava se o usuário tiver
    /// "exigir senha imediatamente" ligado, e não dá para garantir isso.
    private static let travar: (() -> Void)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
              let s = dlsym(h, "SACLockScreenImmediate") else { return nil }
        let f = unsafeBitCast(s, to: FuncaoTravar.self)
        return { _ = f() }
    }()

    // MARK: proteção de tela

    private static func abrirProtecaoDeTela() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    // MARK: ejetar

    static func volumesMontados() -> [(VolumeMontado, URL)] {
        let chaves: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey,
                                        .volumeIsInternalKey, .volumeIsRootFileSystemKey,
                                        .volumeLocalizedNameKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: chaves,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(chaves)) else { return nil }
            let m = VolumeMontado(caminho: url.path,
                                  nome: v.volumeLocalizedName ?? url.lastPathComponent,
                                  raiz: v.volumeIsRootFileSystem ?? false,
                                  // na dúvida, interno: melhor não ejetar do que ejetar o errado
                                  interno: v.volumeIsInternal ?? true,
                                  ejetavel: v.volumeIsEjectable ?? false,
                                  removivel: v.volumeIsRemovable ?? false)
            return (m, url)
        }
    }

    /// Ejeta fora da main thread: um disco lento leva segundos para soltar, e
    /// a bandeja não pode engasgar esperando.
    private static func ejetarTodos() {
        let todos = volumesMontados()
        let alvos = Ejecao.alvos(todos.map(\.0))
        let urls = todos.filter { alvos.contains($0.0) }

        guard !urls.isEmpty else {
            avisar(Ejecao.resumo(ejetados: [], falhas: []), falhou: true)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var ejetados: [String] = []
            var falhas: [String] = []
            for (v, url) in urls {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                    ejetados.append(v.nome)
                } catch {
                    falhas.append(v.nome)
                }
            }
            DispatchQueue.main.async {
                avisar(Ejecao.resumo(ejetados: ejetados, falhas: falhas),
                       falhou: !falhas.isEmpty)
            }
        }
    }

    // MARK: ícones da mesa

    /// Lido direto das preferências do Finder, pelo CFPreferences.
    ///
    /// NUNCA por um processo `defaults` com `waitUntilExit`: esperar um
    /// processo gira o run loop, e este valor é lido no meio da montagem do
    /// menu da barra — o SwiftUI recebia uma segunda atualização dentro da
    /// primeira e o AttributeGraph abortava o app no primeiro clique no ícone.
    static var iconesDaMesaVisiveis: Bool {
        let valor = CFPreferencesCopyAppValue("CreateDesktop" as CFString, finder)
        let texto: String?
        switch valor {
        case let b as Bool:   texto = b ? "1" : "0"
        case let s as String: texto = s
        default:              texto = nil
        }
        return IconesDaMesa.visiveis(valorGravado: texto)
    }

    private static let finder = "com.apple.finder" as CFString

    /// Título que diz o que o clique VAI fazer, como nos menus do sistema.
    static func titulo(_ acao: AcaoRapida) -> String {
        if acao == .iconesDaMesa && !iconesDaMesaVisiveis { return "Mostrar ícones da mesa" }
        return acao.titulo
    }

    /// Grava a preferência do Finder e o reinicia — é o único jeito de ele
    /// reler o `CreateDesktop`. As janelas abertas do Finder voltam sozinhas.
    private static func alternarIconesDaMesa() {
        let mostrar = !iconesDaMesaVisiveis
        CFPreferencesSetAppValue("CreateDesktop" as CFString, mostrar as CFBoolean, finder)
        // grava já no cfprefsd: o Finder que vai nascer relê dali
        CFPreferencesAppSynchronize(finder)
        rodar("/usr/bin/killall", ["Finder"])
    }

    // MARK: utilidades

    /// Dispara o comando e segue, sem esperar. Esperar (`waitUntilExit`) gira
    /// o run loop, e nenhum destes comandos tem resposta que importe.
    private static func rodar(_ caminho: String, _ argumentos: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: caminho)
        p.arguments = argumentos
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { NSSound.beep() }
    }

    /// Aviso simples e sem permissão: notificações exigiriam pedir autorização.
    /// Ejetar com sucesso só toca o som; o diálogo fica para quando algo falhou,
    /// que é quando a pessoa precisa saber antes de puxar o cabo.
    private static func avisar(_ texto: String, falhou: Bool) {
        guard falhou else {
            DockaStore.shared.playSound("Pop", volume: 0.5)
            return
        }
        let alerta = NSAlert()
        alerta.messageText = "Ejetar todos os discos"
        alerta.informativeText = texto
        alerta.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alerta.runModal()
    }
}

/// O Night Shift, pelo cliente do CoreBrightness — o mesmo que a Central de
/// Controle usa. Ligar aqui é o "ligar até amanhã" de lá: o horário
/// programado continua valendo.
enum NightShift {
    private static let classe: NSObject.Type? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return NSClassFromString("CBBlueLightClient") as? NSObject.Type
    }()
    private static let cliente: NSObject? = classe?.init()

    /// Macs sem suporte (telas antigas) dizem não aqui.
    static var disponivel: Bool {
        guard let classe else { return false }
        let sel = NSSelectorFromString("supportsBlueLightReduction")
        guard classe.responds(to: sel) else { return cliente != nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(classe.method(for: sel), to: F.self)(classe, sel)
    }

    static var ligado: Bool {
        get {
            guard let c = cliente else { return false }
            let sel = NSSelectorFromString("getBlueLightStatus:")
            guard c.responds(to: sel) else { return false }
            // a estrutura: ativo, ligado, … — sobra espaço para o resto dela
            var status = [UInt8](repeating: 0, count: 64)
            typealias F = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
            let f = unsafeBitCast(c.method(for: sel), to: F.self)
            guard status.withUnsafeMutableBytes({ f(c, sel, $0.baseAddress!) }) else { return false }
            return status[1] != 0
        }
        set {
            guard let c = cliente else { return }
            let sel = NSSelectorFromString("setEnabled:")
            guard c.responds(to: sel) else { return }
            typealias F = @convention(c) (AnyObject, Selector, Bool) -> Bool
            _ = unsafeBitCast(c.method(for: sel), to: F.self)(c, sel, newValue)
        }
    }
}
