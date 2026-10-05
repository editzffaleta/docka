import Foundation

/// Os avisos rápidos da ilha: aparecem nas asas por alguns segundos e somem
/// — carregador, fones, volume, brilho, copiado.
public enum AvisosDaIlha {

    /// Uma atividade com prazo.
    public struct Temporaria: Equatable, Sendable {
        public let atividade: Ilha.Atividade
        public let ate: Date
        public init(_ a: Ilha.Atividade, ate: Date) { atividade = a; self.ate = ate }
    }

    /// Junta um aviso novo: o do mesmo tipo é trocado (mexer no volume várias
    /// vezes não empilha avisos), e os vencidos saem.
    public static func juntar(_ nova: Temporaria, a lista: [Temporaria], agora: Date) -> [Temporaria] {
        [nova] + lista.filter { $0.atividade.id != nova.atividade.id && $0.ate > agora }
    }

    public static func vivas(_ lista: [Temporaria], agora: Date) -> [Ilha.Atividade] {
        lista.filter { $0.ate > agora }.map(\.atividade)
    }

    // MARK: bateria

    public enum EventoDaBateria: Equatable, Sendable {
        case conectou(Double)
        case desconectou(Double)
        case baixa(Double)
    }

    public static let limitesDeBateriaBaixa: [Double] = [0.20, 0.10, 0.05]

    /// O que mudou entre duas leituras. Bateria baixa só ao cruzar um limite
    /// descendo, e fora da tomada — avisar a cada leitura abaixo de 20%
    /// seria insuportável.
    public static func bateria(antes: (fracao: Double, naTomada: Bool)?, agora: (fracao: Double, naTomada: Bool)) -> EventoDaBateria? {
        guard let antes else { return nil }
        if agora.naTomada && !antes.naTomada { return .conectou(agora.fracao) }
        if !agora.naTomada && antes.naTomada { return .desconectou(agora.fracao) }
        if !agora.naTomada, limitesDeBateriaBaixa.contains(where: { antes.fracao > $0 && agora.fracao <= $0 }) {
            return .baixa(agora.fracao)
        }
        return nil
    }

    public static func simboloDaBateria(_ f: Double, carregando: Bool) -> String {
        if carregando { return "battery.100percent.bolt" }
        switch f {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default:      return "battery.100percent"
        }
    }

    // MARK: fones

    /// A saída de som é um fone? Bluetooth sempre conta (AirPods, fones e
    /// caixinhas); fora isso, pelo nome.
    public static func ehFone(nome: String, bluetooth: Bool) -> Bool {
        if bluetooth { return true }
        let n = nome.lowercased()
        return ["airpods", "headphone", "fone", "headset", "beats", "earpods", "buds"].contains { n.contains($0) }
    }

    public static func simboloDoFone(_ nome: String) -> String {
        let n = nome.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    // MARK: nível (volume e brilho)

    /// Mudou de verdade? Diferenças menores que meio ponto são ruído de leitura.
    public static func mudou(_ antes: Double?, _ agora: Double) -> Bool {
        guard let antes else { return false }
        return abs(antes - agora) >= 0.005
    }

    public static func porcentagem(_ v: Double) -> String { "\(Int((min(1, max(0, v)) * 100).rounded()))%" }
}
