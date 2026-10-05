import Foundation

/// As listas de arquivos da ilha: capturas recentes e downloads.
///
/// Só a escolha e a ordem — quem lê a pasta é o app. Assim dá para testar
/// sem disco: cada arquivo chega como nome, data e tamanho.
public enum ArquivosDaIlha {

    public struct Arquivo: Equatable, Sendable {
        public let caminho: String
        public let data: Date
        public let tamanho: Int64

        public init(caminho: String, data: Date, tamanho: Int64) {
            self.caminho = caminho; self.data = data; self.tamanho = tamanho
        }

        public var nome: String { (caminho as NSString).lastPathComponent }
        public var extensao: String { (caminho as NSString).pathExtension.lowercased() }
    }

    /// Extensões dos downloads que ainda estão chegando (Safari, Chrome e
    /// parentes, Firefox, Opera, e o genérico).
    public static let extensoesParciais: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]

    public static let extensoesDeCaptura: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "mov", "mp4"]

    public static func parcial(_ a: Arquivo) -> Bool { extensoesParciais.contains(a.extensao) }

    /// O nome que o arquivo vai ter quando terminar: "foto.jpg.crdownload" → "foto.jpg".
    public static func nomeFinal(_ nome: String) -> String {
        let ext = (nome as NSString).pathExtension.lowercased()
        return extensoesParciais.contains(ext) ? (nome as NSString).deletingPathExtension : nome
    }

    /// Os mais recentes primeiro, sem ocultos e sem os que ainda estão chegando.
    public static func recentes(_ arquivos: [Arquivo], limite: Int) -> [Arquivo] {
        Array(arquivos
            .filter { !$0.nome.hasPrefix(".") && !parcial($0) }
            .sorted { $0.data > $1.data }
            .prefix(limite))
    }

    /// Só imagens e vídeos — numa pasta de capturas que é a Mesa, há de tudo.
    public static func capturas(_ arquivos: [Arquivo], limite: Int) -> [Arquivo] {
        recentes(arquivos.filter { extensoesDeCaptura.contains($0.extensao) }, limite: limite)
    }

    /// A pasta onde o macOS grava as capturas: a escolhida nos ajustes do
    /// Capturar Tela (`com.apple.screencapture location`), com "~" expandido,
    /// ou a Mesa.
    public static func pastaDeCapturas(gravada: String?, home: String) -> String {
        guard var g = gravada?.trimmingCharacters(in: .whitespaces), !g.isEmpty else {
            return (home as NSString).appendingPathComponent("Desktop")
        }
        if g.hasPrefix("~") { g = home + g.dropFirst() }
        return g
    }

    /// "agora", "há 5 min", "há 2 h", "ontem", "há 3 dias".
    public static func quando(_ data: Date, agora: Date) -> String {
        let s = agora.timeIntervalSince(data)
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(Int(s / 60)) min" }
        if s < 86_400 { return "há \(Int(s / 3600)) h" }
        let dias = Int(s / 86_400)
        return dias == 1 ? "ontem" : "há \(dias) dias"
    }

    /// Progresso de download para a asa: "42%".
    public static func porcentagem(_ fracao: Double) -> String {
        "\(Int((min(1, max(0, fracao)) * 100).rounded(.down)))%"
    }

    /// Vários downloads ao mesmo tempo viram um só na asa: a fração do total
    /// (média, quando o tamanho de algum é desconhecido).
    public static func progressoGeral(_ fracoes: [Double]) -> Double? {
        guard !fracoes.isEmpty else { return nil }
        return fracoes.reduce(0, +) / Double(fracoes.count)
    }
}
