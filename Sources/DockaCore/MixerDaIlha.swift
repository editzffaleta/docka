import Foundation

/// O mixer da ilha: de que app é cada som, e a curva do controle de volume.
public enum MixerDaIlha {

    /// O app dono de um processo de áudio. O som do navegador sai de um
    /// processo auxiliar ("com.brave.Browser.helper"), e o do Safari de um
    /// "com.apple.WebKit.GPU" — que não tem como saber de qual app é, e fica
    /// com o próprio nome.
    public static func dono(_ bundleDoProcesso: String, apps: [String]) -> String {
        if apps.contains(bundleDoProcesso) { return bundleDoProcesso }
        // o app de identificador mais longo que é prefixo: "com.google.Chrome"
        // ganha de "com.google" se os dois existirem
        let candidatos = apps.filter { bundleDoProcesso.hasPrefix($0 + ".") }
        return candidatos.max { $0.count < $1.count } ?? bundleDoProcesso
    }

    /// Controle (0…1,5) → ganho. Até 100% segue uma curva quadrática, como o
    /// ouvido percebe volume; acima, sobe em linha até 1,5× (um reforço para
    /// app baixinho, sem distorcer demais).
    public static func ganho(_ controle: Double) -> Float {
        let c = min(1.5, max(0, controle))
        return Float(c <= 1 ? c * c : c)
    }

    /// "100%", "35%", "150%".
    public static func rotulo(_ controle: Double) -> String {
        "\(Int((min(1.5, max(0, controle)) * 100).rounded()))%"
    }

    /// O controle só precisa de um desvio quando sai de 100%: no padrão, o
    /// som do app não passa pelo Docka.
    public static func precisaDesviar(_ controle: Double) -> Bool { abs(controle - 1) > 0.005 }
}
