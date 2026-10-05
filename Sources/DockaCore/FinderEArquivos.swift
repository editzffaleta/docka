import Foundation

/// Finder e arquivos: o recortar e colar do Finder e o instalador de imagem
/// de disco — as regras, sem tocar no Finder nem no disco.
public enum FinderEArquivos {

    // MARK: recortar e colar

    /// O Finder não recorta arquivos: copia com ⌘C e move com ⌥⌘V. O Docka
    /// faz o ⌘X virar "copiar e lembrar" e o ⌘V seguinte virar "mover".
    public struct Recorte: Sendable {
        public enum Acao: Equatable, Sendable { case deixar, copiarELembrar, mover }

        /// O número da área de transferência logo depois do ⌘C do Docka: se
        /// mudar (você copiou outra coisa), o recorte é esquecido.
        public private(set) var lembrado: Int?

        public init() {}

        /// ⌘X no Finder. Editando texto (renomeando), é o recortar de texto de sempre.
        public mutating func recortar(editandoTexto: Bool) -> Acao {
            editandoTexto ? .deixar : .copiarELembrar
        }

        /// Depois do ⌘C, o número da área de transferência.
        public mutating func copiou(numero: Int) { lembrado = numero }

        /// ⌘V no Finder: move se houver um recorte que ainda vale.
        public mutating func colar(editandoTexto: Bool, numeroAgora: Int) -> Acao {
            guard !editandoTexto, let l = lembrado else { return .deixar }
            lembrado = nil
            return l == numeroAgora ? .mover : .deixar
        }

        public mutating func esquecer() { lembrado = nil }
        public var ativo: Bool { lembrado != nil }
    }

    // MARK: imagem de disco

    /// Os apps no topo de um volume montado — o que um instalador de .dmg
    /// costuma trazer, ao lado do atalho para Aplicativos.
    public static func apps(noVolume itens: [String]) -> [String] {
        itens.filter { $0.hasSuffix(".app") && !$0.hasPrefix(".") }.sorted()
    }

    /// O arquivo .dmg de um volume, tirado do `hdiutil info -plist`.
    public static func imagem(doVolume volume: String, info: [String: Any]) -> String? {
        let imagens = info["images"] as? [[String: Any]] ?? []
        for i in imagens {
            let entidades = i["system-entities"] as? [[String: Any]] ?? []
            if entidades.contains(where: { ($0["mount-point"] as? String) == volume }) {
                return i["image-path"] as? String
            }
        }
        return nil
    }

    /// Só oferece instalar volumes que vieram de um .dmg e trazem exatamente
    /// um app — pendrive, disco externo ou imagem com vários apps ficam de fora.
    public static func oferecer(volume: String, itens: [String], imagem: String?) -> String? {
        guard let imagem, imagem.lowercased().hasSuffix(".dmg") else { return nil }
        let a = apps(noVolume: itens)
        return a.count == 1 ? a[0] : nil
    }
}
