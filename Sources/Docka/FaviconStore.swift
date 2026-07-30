import AppKit
import DockaCore

/// Baixa e guarda os ícones dos sites do anel.
///
/// **Esta é a única conexão de saída do Docka**, e existe a pedido do usuário:
/// ao adicionar um site à órbita, o ícone vem do PRÓPRIO site (apple-touch-icon
/// ou favicon.ico) — nunca de um resolvedor de terceiros, que receberia a lista
/// de sites como brinde. O resultado fica em disco; sem rede, ou sem ícone, o
/// anel mostra o globo desenhado localmente e nada quebra.
final class FaviconStore {
    static let shared = FaviconStore()

    private let pasta: URL
    /// Hosts com busca em andamento ou já falhada NESTA sessão — evita
    /// martelar um site fora do ar a cada quadro do anel.
    private var ocupados: Set<String> = []
    private let sessao: URLSession

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        pasta = base.appendingPathComponent("Docka/SiteIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)

        // efêmera e sem cache próprio: o cache é o arquivo em disco, e uma
        // sessão persistente guardaria cookies que ninguém pediu
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        sessao = URLSession(configuration: config)
    }

    /// Ícone em cache para o site, se já baixado.
    func icone(para site: String) -> NSImage? {
        guard let nome = Favicon.nomeDoCache(para: site) else { return nil }
        return NSImage(contentsOf: pasta.appendingPathComponent(nome))
    }

    /// Busca o ícone se ainda não houver, e avisa a interface quando chegar.
    /// Chamável de qualquer lugar, quantas vezes for — deduplica sozinha.
    func buscarSePreciso(_ site: String) {
        guard let nome = Favicon.nomeDoCache(para: site) else { return }
        DispatchQueue.main.async { [self] in
            guard !ocupados.contains(nome) else { return }
            guard !FileManager.default.fileExists(atPath: pasta.appendingPathComponent(nome).path)
            else { return }
            ocupados.insert(nome)
            tentar(Favicon.candidatos(para: site), nome: nome) { [weak self] imagem in
                guard let self else { return }
                if let imagem { self.gravar(imagem, nome: nome) }
                // falhou: fica no `ocupados` até o app reiniciar — o globo serve
            }
        }
    }

    /// Joga fora o cache e busca de novo — o "Atualizar logo" dos ajustes.
    ///
    /// Sem isto a logo era eterna: site que trocasse de identidade ficaria com
    /// a antiga para sempre, e não havia como pedir outra.
    func rebuscar(_ site: String) {
        guard let nome = Favicon.nomeDoCache(para: site) else { return }
        DispatchQueue.main.async { [self] in
            try? FileManager.default.removeItem(at: pasta.appendingPathComponent(nome))
            ocupados.remove(nome)   // a falha antiga não pode vetar a tentativa nova
            buscarSePreciso(site)
        }
    }

    /// Busca para a PRÉVIA dos ajustes: devolve a imagem (do cache ou da rede).
    func buscarParaPrevia(_ site: String, resultado: @escaping (NSImage?) -> Void) {
        if let pronta = icone(para: site) { resultado(pronta); return }
        guard let nome = Favicon.nomeDoCache(para: site) else { resultado(nil); return }
        tentar(Favicon.candidatos(para: site), nome: nome) { [weak self] imagem in
            if let imagem { self?.gravar(imagem, nome: nome) }
            resultado(imagem)
        }
    }

    /// Tenta as candidatas em ordem; a primeira imagem válida vence.
    private func tentar(_ urls: [URL], nome: String,
                        completo: @escaping (NSImage?) -> Void) {
        guard let primeira = urls.first else {
            DispatchQueue.main.async { completo(nil) }
            return
        }
        sessao.dataTask(with: primeira) { [weak self] dados, resposta, _ in
            if let dados, dados.count <= Favicon.bytesMaximos,
               (resposta as? HTTPURLResponse)?.statusCode == 200,
               let imagem = NSImage(data: dados),
               imagem.size.width >= CGFloat(Favicon.ladoMinimo) {
                DispatchQueue.main.async { completo(imagem) }
            } else {
                self?.tentar(Array(urls.dropFirst()), nome: nome, completo: completo)
            }
        }.resume()
    }

    private func gravar(_ imagem: NSImage, nome: String) {
        guard let tiff = imagem.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: pasta.appendingPathComponent(nome))
        DispatchQueue.main.async {
            // ícones de site não passam pelo NSCache do ItemVisual justamente
            // para esta chegada tardia aparecer; só falta a view redesenhar
            DockaStore.shared.objectWillChange.send()
        }
    }
}
