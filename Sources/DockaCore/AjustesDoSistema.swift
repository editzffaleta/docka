import Foundation

/// Pequenos ajustes do sistema: as regras, sem tocar no sistema.
public enum AjustesDoSistema {

    // MARK: o app Música

    /// O Música abriu sozinho (pela tecla de play, ao conectar fones) e não
    /// por você? Quem abre de propósito — pelo Dock, Spotlight, Launchpad —
    /// deixa o app na frente; aberto "pelas costas", ele fica atrás.
    public static func fecharMusica(estaNaFrente: Bool, abertoPorVoce: Bool) -> Bool {
        !estaNaFrente && !abertoPorVoce
    }

    // MARK: Bluetooth no repouso

    /// Ao dormir: desliga se estava ligado — e lembra que foi o Docka.
    public static func aoDormir(ligado: Bool) -> (desligar: Bool, lembrar: Bool) {
        ligado ? (true, true) : (false, false)
    }

    /// Ao acordar: só religa o que o próprio Docka desligou. Quem dormiu com
    /// o Bluetooth desligado acorda com ele desligado.
    public static func aoAcordar(desligadoPeloDocka: Bool) -> Bool { desligadoPeloDocka }

    // MARK: aceleração do ponteiro

    /// O sistema guarda a aceleração em ponto fixo 16.16 (0,875 → 57344).
    public static func pontoFixo(_ v: Double) -> Int32 { Int32((v * 65536).rounded()) }
    public static func dePontoFixo(_ v: Int32) -> Double { Double(v) / 65536 }

    /// "Sem aceleração" é o valor -1 — o mouse anda sempre na mesma
    /// proporção da mão, rápida ou devagar.
    public static let semAceleracao: Double = -1

    /// A faixa que o controle oferece (a mesma dos Ajustes do Sistema, 0 a 3).
    public static func limitar(_ v: Double) -> Double {
        v < 0 ? semAceleracao : min(3, v)
    }
}
