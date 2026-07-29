import Foundation

/// Um atalho global: uma tecla mais os modificadores.
///
/// Guarda o **código virtual** da tecla — o mesmo número que o Carbon e o
/// `NSEvent` usam — e não o caractere. É o que o `RegisterEventHotKey` espera, e
/// é o que continua funcionando quando o usuário troca o layout do teclado.
public struct Shortcut: Equatable, Sendable, Codable {

    public struct Modifiers: OptionSet, Equatable, Sendable, Codable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift   = Modifiers(rawValue: 1 << 1)
        public static let option  = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⇧⌘D — o atalho histórico do Docka.
    public static let padrao = Shortcut(keyCode: 2, modifiers: [.command, .shift])

    /// Um atalho global sem ⌘, ⌥ ou ⌃ engoliria aquela tecla no sistema inteiro —
    /// digitar "D" em qualquer app abriria a bandeja. Shift sozinho não basta.
    public var isValid: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control])
    }

    /// Símbolos na ordem que a Apple usa nos menus: ⌃ ⌥ ⇧ ⌘ e então a tecla.
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    /// Versão falada, para o VoiceOver: "Comando Shift D" se entende melhor que
    /// uma fileira de símbolos.
    public var spokenDescription: String {
        var partes: [String] = []
        if modifiers.contains(.control) { partes.append("Controle") }
        if modifiers.contains(.option)  { partes.append("Opção") }
        if modifiers.contains(.shift)   { partes.append("Shift") }
        if modifiers.contains(.command) { partes.append("Comando") }
        partes.append(Self.keyName(keyCode))
        return partes.joined(separator: " ")
    }

    public static func keyName(_ code: UInt16) -> String {
        keyNames[code] ?? "Tecla \(code)"
    }

    // Códigos virtuais do Carbon (kVK_*). São fixos e independem do layout:
    // a tecla 2 é a que fica onde o "D" está no ANSI, seja qual for o idioma.
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7",
        28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\",
        43: ",", 44: "/", 47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Espaço", 51: "Delete", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
