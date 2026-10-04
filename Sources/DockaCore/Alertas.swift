import Foundation

/// Um aviso a mostrar.
public struct Alerta: Equatable, Sendable {
    public enum Tipo: String, CaseIterable, Sendable {
        case cpu, memoria, disco, bateria, temperatura
    }

    public var tipo: Tipo
    public var titulo: String
    public var mensagem: String

    public init(tipo: Tipo, titulo: String, mensagem: String) {
        self.tipo = tipo
        self.titulo = titulo
        self.mensagem = mensagem
    }

    public var simbolo: String {
        switch tipo {
        case .cpu:         return "cpu"
        case .memoria:     return "memorychip"
        case .disco:       return "internaldrive"
        case .bateria:     return "battery.25"
        case .temperatura: return "thermometer.high"
        }
    }
}

/// Os limites escolhidos nos ajustes.
public struct LimitesDeAlerta: Equatable, Sendable {
    public var cpu: Double          // fração, 0…1
    public var cpuMinutos: Int
    public var discoLivreGB: Int
    public var bateria: Double      // fração, 0…1

    public init(cpu: Double = 0.85, cpuMinutos: Int = 2,
                discoLivreGB: Int = 10, bateria: Double = 0.20) {
        self.cpu = cpu
        self.cpuMinutos = cpuMinutos
        self.discoLivreGB = discoLivreGB
        self.bateria = bateria
    }
}

/// Decide QUANDO avisar. Cada alerta dispara uma vez e só volta a valer
/// depois que a situação normaliza com folga — sem isso, uma CPU oscilando em
/// volta do limite, ou uma bateria parada em 20%, repetiria o aviso sem parar.
///
/// Lógica pura: recebe leituras e o relógio, devolve o aviso. Quem lê o
/// sistema e mostra o cartão é a casca.
public struct VigiaDeAlertas: Sendable {
    public var limites: LimitesDeAlerta

    /// Desde quando a CPU está acima do limite sem interrupção.
    private var cpuAcimaDesde: Date?
    private var cpuArmado = true
    private var discoArmado = true
    private var bateriaArmado = true
    private var temperaturaArmado = true
    private var ultimaMemoria: Date?

    /// Folga para rearmar: a CPU precisa cair 10 pontos abaixo do limite.
    public static let folgaDeCPU = 0.10
    /// Entre dois avisos de memória: o sistema repete o sinal enquanto dura.
    public static let intervaloDeMemoria: TimeInterval = 10 * 60

    public init(limites: LimitesDeAlerta = LimitesDeAlerta()) {
        self.limites = limites
    }

    public mutating func cpu(_ uso: Double, em agora: Date) -> Alerta? {
        if uso >= limites.cpu {
            let desde = cpuAcimaDesde ?? agora
            cpuAcimaDesde = desde
            let minutos = agora.timeIntervalSince(desde) / 60
            guard cpuArmado, minutos >= Double(limites.cpuMinutos) else { return nil }
            cpuArmado = false
            return Alerta(tipo: .cpu, titulo: "CPU alta há \(limites.cpuMinutos) min",
                          mensagem: "O uso está em \(Metricas.porcentagem(uso)). O Monitor de Atividade mostra qual app está pesando.")
        }
        cpuAcimaDesde = nil
        if uso < limites.cpu - Self.folgaDeCPU { cpuArmado = true }
        return nil
    }

    public mutating func disco(livre: UInt64) -> Alerta? {
        let limite = UInt64(limites.discoLivreGB) * 1_000_000_000
        if livre < limite {
            guard discoArmado else { return nil }
            discoArmado = false
            return Alerta(tipo: .disco, titulo: "Disco quase cheio",
                          mensagem: "Restam \(Metricas.bytes(livre)) no disco de inicialização.")
        }
        // rearma só com 20% de folga: apagar um arquivo pequeno e baixar
        // outro não pode virar dois avisos
        if Double(livre) > Double(limite) * 1.2 { discoArmado = true }
        return nil
    }

    public mutating func bateria(_ fracao: Double, carregando: Bool, naTomada: Bool) -> Alerta? {
        if carregando || naTomada {
            bateriaArmado = true
            return nil
        }
        if fracao <= limites.bateria {
            guard bateriaArmado else { return nil }
            bateriaArmado = false
            return Alerta(tipo: .bateria, titulo: "Bateria em \(Metricas.porcentagem(fracao))",
                          mensagem: "Conecte o carregador em breve.")
        }
        if fracao > limites.bateria + 0.05 { bateriaArmado = true }
        return nil
    }

    /// `nivel` como o `ProcessInfo.ThermalState`: 0 normal, 1 regular,
    /// 2 sério, 3 crítico.
    public mutating func temperatura(nivel: Int) -> Alerta? {
        if nivel >= 2 {
            guard temperaturaArmado else { return nil }
            temperaturaArmado = false
            return Alerta(tipo: .temperatura,
                          titulo: nivel >= 3 ? "Mac muito quente" : "Mac esquentando",
                          mensagem: "O sistema já está reduzindo o desempenho para esfriar. Feche o que estiver pesado ou dê um respiro à ventilação.")
        }
        if nivel <= 1 { temperaturaArmado = true }
        return nil
    }

    /// O sistema avisou que a memória está apertada.
    public mutating func pressaoDeMemoria(critica: Bool, em agora: Date) -> Alerta? {
        if let u = ultimaMemoria, agora.timeIntervalSince(u) < Self.intervaloDeMemoria { return nil }
        ultimaMemoria = agora
        return Alerta(tipo: .memoria,
                      titulo: critica ? "Memória esgotando" : "Memória apertada",
                      mensagem: "O Mac está comprimindo e trocando memória com o disco. Fechar abas e apps alivia.")
    }
}
