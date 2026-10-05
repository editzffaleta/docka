import Foundation

/// As notificações recentes da ilha, lidas dos avisos que aparecem na tela
/// (pela Acessibilidade). Só na memória: somem ao travar a tela ou desligar.
public enum NotificacoesDaIlha {

    public struct Aviso: Equatable, Identifiable, Sendable {
        public let id: String
        public let app: String
        public let titulo: String
        public let subtitulo: String?
        public let corpo: String?
        public let chegou: Date

        public init(id: String, app: String, titulo: String, subtitulo: String? = nil, corpo: String? = nil, chegou: Date) {
            self.id = id; self.app = app; self.titulo = titulo
            self.subtitulo = subtitulo; self.corpo = corpo; self.chegou = chegou
        }
    }

    /// O nome do app, tirado da descrição do aviso — "App, Título, Subtítulo,
    /// Corpo": o que sobra antes das partes conhecidas. Sem o padrão, nil.
    public static func app(descricao: String, titulo: String?, subtitulo: String?, corpo: String?) -> String? {
        let partes = [titulo, subtitulo, corpo].compactMap { $0 }.filter { !$0.isEmpty }
        guard !partes.isEmpty else { return nil }
        let fim = ", " + partes.joined(separator: ", ")
        guard descricao.hasSuffix(fim) else { return nil }
        let app = String(descricao.dropLast(fim.count)).trimmingCharacters(in: .whitespaces)
        return app.isEmpty ? nil : app
    }

    public static let limite = 30

    /// Junta os avisos novos aos que já estavam: sem repetir (o mesmo aviso
    /// fica vários segundos na tela), os mais novos primeiro, até o limite.
    public static func juntar(_ novos: [Aviso], a lista: [Aviso]) -> [Aviso] {
        let conhecidos = Set(lista.map(\.id))
        let entram = novos.filter { !conhecidos.contains($0.id) }
        return Array((entram.sorted { $0.chegou > $1.chegou } + lista).prefix(limite))
    }

    /// Agrupados por app, na ordem do aviso mais recente de cada um.
    public static func porApp(_ lista: [Aviso]) -> [(app: String, avisos: [Aviso])] {
        var ordem: [String] = []
        var grupos: [String: [Aviso]] = [:]
        for a in lista.sorted(by: { $0.chegou > $1.chegou }) {
            if grupos[a.app] == nil { ordem.append(a.app) }
            grupos[a.app, default: []].append(a)
        }
        return ordem.map { ($0, grupos[$0]!) }
    }
}
