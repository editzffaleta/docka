import AppKit
import DockaCore

/// Executa as ações rápidas. Nenhuma pede permissão: são ferramentas de linha
/// de comando do sistema, APIs públicas do NSWorkspace e, para travar a tela,
/// uma função do framework de login resolvida em runtime.
enum AcoesRapidasBackend {

    /// A ação existe nesta versão do macOS? Só a de travar depende de API
    /// privada; se ela sumir, a ação some do menu em vez de falhar calada.
    static func disponivel(_ acao: AcaoRapida) -> Bool {
        acao == .travarTela ? travar != nil : true
    }

    static func executar(_ acao: AcaoRapida) {
        switch acao {
        case .travarTela:     travar?()
        case .apagarTelas:    rodar("/usr/bin/pmset", ["displaysleepnow"])
        case .protecaoDeTela: abrirProtecaoDeTela()
        case .repouso:        rodar("/usr/bin/pmset", ["sleepnow"])
        case .ejetarDiscos:   ejetarTodos()
        case .iconesDaMesa:   alternarIconesDaMesa()
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

    /// Lido uma vez e mantido em memória: o menu da barra é reavaliado a cada
    /// mudança no store, e cada leitura seria um processo `defaults` novo.
    private(set) static var iconesDaMesaVisiveis: Bool =
        IconesDaMesa.visiveis(valorGravado: saida("/usr/bin/defaults",
                                                  ["read", "com.apple.finder", "CreateDesktop"]))

    /// Título que diz o que o clique VAI fazer, como nos menus do sistema.
    static func titulo(_ acao: AcaoRapida) -> String {
        if acao == .iconesDaMesa && !iconesDaMesaVisiveis { return "Mostrar ícones da mesa" }
        return acao.titulo
    }

    /// Grava a preferência do Finder e o reinicia — é o único jeito de ele
    /// reler o `CreateDesktop`. As janelas abertas do Finder voltam sozinhas.
    private static func alternarIconesDaMesa() {
        let mostrar = !iconesDaMesaVisiveis
        rodar("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool",
                                    mostrar ? "true" : "false"])
        rodar("/usr/bin/killall", ["Finder"])
        iconesDaMesaVisiveis = mostrar
    }

    // MARK: utilidades

    private static func rodar(_ caminho: String, _ argumentos: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: caminho)
        p.arguments = argumentos
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            NSSound.beep()
        }
    }

    private static func saida(_ caminho: String, _ argumentos: [String]) -> String? {
        let p = Process()
        let cano = Pipe()
        p.executableURL = URL(fileURLWithPath: caminho)
        p.arguments = argumentos
        p.standardOutput = cano
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: cano.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
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
