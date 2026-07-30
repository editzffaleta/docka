import Foundation

/// Uma bandeja: seus apps e onde ela mora.
///
/// O que é aparência (tamanho do ícone, ampliação, vidro, tom) continua global —
/// o Docka é um só, com várias bandejas, e não vários apps disfarçados.
public struct DockConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var apps: [String]            // caminhos dos .app
    public var edge: TrayEdge
    public var alignment: TrayAlignment
    public var offset: Double

    public init(id: UUID = UUID(),
                apps: [String] = [],
                edge: TrayEdge = .bottom,
                alignment: TrayAlignment = .end,
                offset: Double = 24) {
        self.id = id
        self.apps = apps
        self.edge = edge
        self.alignment = alignment
        self.offset = offset
    }

    /// Nome mostrado na lista de bandejas.
    public var titulo: String {
        "\(edge.titulo) · \(alignment.titulo(for: edge))"
    }

    /// Sugestão de borda para uma bandeja nova: a primeira livre, para a nova
    /// não nascer empilhada em cima de outra.
    public static func proximaBordaLivre(_ existentes: [DockConfig]) -> TrayEdge {
        let usadas = Set(existentes.map(\.edge))
        return TrayEdge.allCases.first { !usadas.contains($0) } ?? .bottom
    }
}
