import Foundation

/// Onde procurar o ícone de um site — a parte testável da busca.
///
/// A busca fala SÓ com o site que o usuário digitou, nunca com serviço de
/// terceiros: mandar o host para um resolvedor de favicon (Google, DuckDuckGo)
/// entregaria a lista de sites do usuário a alguém que ele não escolheu.
public enum Favicon {

    /// URLs candidatas, na ordem de tentativa.
    ///
    /// O apple-touch-icon vem primeiro por ser maior (180×180, pensado para
    /// tela inicial); o favicon.ico da raiz é o retrocompatível que quase todo
    /// site tem. Sem parse de HTML: cobre a grande maioria e mantém a busca
    /// simples — quem não tiver nenhum dos dois fica com o globo.
    public static func candidatos(para site: String) -> [URL] {
        guard let url = URL(string: site), let host = url.host,
              let esquema = url.scheme, ["http", "https"].contains(esquema.lowercased())
        else { return [] }
        let porta = url.port.map { ":\($0)" } ?? ""
        let raiz = "\(esquema)://\(host)\(porta)"
        return [
            URL(string: "\(raiz)/apple-touch-icon.png"),
            URL(string: "\(raiz)/apple-touch-icon-precomposed.png"),
            URL(string: "\(raiz)/favicon.ico"),
        ].compactMap { $0 }
    }

    /// Nome do arquivo em cache para um site — um por host.
    ///
    /// Por host, e não por URL: `exemplo.com/a` e `exemplo.com/b` têm o mesmo
    /// ícone, e baixá-lo duas vezes seria desperdício.
    public static func nomeDoCache(para site: String) -> String? {
        guard let url = URL(string: site), let host = url.host?.lowercased()
        else { return nil }
        let porta = url.port.map { "_\($0)" } ?? ""
        return host + porta + ".png"
    }

    /// Tamanho mínimo para valer a pena: menor que isso vira um borrão no anel
    /// e o globo desenhado fica melhor.
    public static let ladoMinimo = 16

    /// Limite de resposta aceito (1 MB): um favicon é pequeno; algo maior é um
    /// site devolvendo página de erro ou coisa que não interessa.
    public static let bytesMaximos = 1_000_000
}
