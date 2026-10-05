import SwiftUI
import AppKit
import DockaCore

/// Lê os registros do Claude Code (`~/.claude/projects`) e do Codex
/// (`~/.codex/sessions`) a cada poucos segundos, numa fila à parte, e de
/// cada arquivo só o que cresceu desde a última leitura. Das linhas, guarda
/// só números e horários — o texto das conversas nunca sai do arquivo.
final class AgentesModelo: ObservableObject {
    static let shared = AgentesModelo()

    struct Claude: Equatable {
        var encontrado = false
        var atual: AgentesDaIlha.Janela?
        var hoje = AgentesDaIlha.Uso()
        var hojeValor: Double?
        var semana = AgentesDaIlha.Uso()
        var semanaValor: Double?
        var modelos: [String] = []
        var trabalhando: [(projeto: String, ha: TimeInterval)] = []
        var ultima: Date?

        static func == (a: Claude, b: Claude) -> Bool {
            a.encontrado == b.encontrado && a.atual == b.atual && a.hoje == b.hoje && a.semana == b.semana
                && a.modelos == b.modelos && a.ultima == b.ultima
                && a.trabalhando.map(\.projeto) == b.trabalhando.map(\.projeto)
                && a.trabalhando.map { Int($0.ha / 60) } == b.trabalhando.map { Int($0.ha / 60) }
        }
    }

    struct Codex: Equatable {
        var encontrado = false
        var primario: AgentesDaIlha.Limite?
        var secundario: AgentesDaIlha.Limite?
        var ultima: Date?
        var trabalhando = false
    }

    @Published private(set) var claude = Claude()
    @Published private(set) var codex = Codex()
    /// Chamado quando uma vez longa termina: (agente, projeto, duração).
    var aoTerminar: ((String, String, TimeInterval) -> Void)?

    private let fila = DispatchQueue(label: "docka.agentes", qos: .utility)
    private var relogio: Timer?
    private var lendo = false
    // só usados na fila
    private var posicoes: [String: UInt64] = [:]
    private var respostas: [AgentesDaIlha.Resposta] = []
    private var indicePorChave: [String: Int] = [:]
    private var avisados: [String: Date] = [:]
    private var primeiraLeitura = true

    /// DOCKA_AGENTES_PASTA troca a pasta, para testar com sessões de mentira
    /// sem tocar nos registros de verdade.
    private static var pastaDoClaude: URL {
        if let p = ProcessInfo.processInfo.environment["DOCKA_AGENTES_PASTA"] { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }
    private static var pastaDoCodex: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions") }

    func ligar(_ quer: Bool) {
        if quer, relogio == nil {
            ler()
            let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.ler() }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            relogio = t
        } else if !quer {
            relogio?.invalidate()
            relogio = nil
        }
    }

    private func ler() {
        guard !lendo else { return }
        lendo = true
        let minimo = DockaStore.shared.ilhaAvisoAgentes ? DockaStore.shared.ilhaAvisoAgentesMinutos * 60 : nil
        fila.async { [weak self] in
            guard let self else { return }
            let c = self.lerClaude(avisarApos: minimo)
            let x = self.lerCodex()
            DispatchQueue.main.async {
                self.lendo = false
                if c != self.claude { self.claude = c }
                if x != self.codex { self.codex = x }
            }
        }
    }

    // MARK: Claude Code (na fila)

    private func lerClaude(avisarApos minimo: TimeInterval?) -> Claude {
        var r = Claude()
        let fm = FileManager.default
        guard let projetos = try? fm.contentsOfDirectory(at: Self.pastaDoClaude, includingPropertiesForKeys: nil) else { return r }
        r.encontrado = true
        let agora = Date()
        let limite = agora.addingTimeInterval(-7 * 86_400)
        for p in projetos {
            let arquivos = (try? fm.contentsOfDirectory(at: p, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for a in arquivos where a.pathExtension == "jsonl" {
                guard let m = try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      m > limite else { continue }
                lerNovidades(a)
            }
        }
        if respostas.contains(where: { $0.momento < limite }) {
            respostas.removeAll { $0.momento < limite }
            indicePorChave = [:]
            for (i, x) in respostas.enumerated() { if let k = x.chave { indicePorChave[k] = i } }
        }
        guard !respostas.isEmpty else { return r }

        let cal = Calendar.current
        let hoje = cal.startOfDay(for: agora)
        for x in respostas {
            r.semana = r.semana + x.uso
            if x.momento >= hoje { r.hoje = r.hoje + x.uso }
        }
        r.semanaValor = soma(respostas)
        r.hojeValor = soma(respostas.filter { $0.momento >= hoje })
        r.atual = AgentesDaIlha.atual(AgentesDaIlha.janelas(respostas), agora: agora)
        var contagem: [String: Int] = [:]
        for x in respostas where x.momento >= hoje.addingTimeInterval(-86_400) { contagem[x.modelo, default: 0] += x.uso.saida }
        r.modelos = contagem.sorted { $0.value > $1.value }.prefix(2).map { $0.key }
        r.ultima = respostas.map(\.momento).max()

        // por sessão: quem está trabalhando, e quem acabou uma vez longa
        let porSessao = Dictionary(grouping: respostas.filter { $0.momento > agora.addingTimeInterval(-6 * 3600) }, by: \.sessao)
        for (sessao, l) in porSessao {
            if let ha = AgentesDaIlha.trabalhando(l, agora: agora) {
                r.trabalhando.append((l.last?.projeto ?? "", ha))
            }
            if let minimo, let v = AgentesDaIlha.vezLongaTerminada(l, minimo: minimo),
               agora.timeIntervalSince(v.fim) < 60, avisados[sessao] != v.fim {
                avisados[sessao] = v.fim
                // na primeira leitura, nada é "novo": não avisa do que acabou antes de abrir
                if !primeiraLeitura {
                    let projeto = l.last?.projeto ?? ""
                    DispatchQueue.main.async { self.aoTerminar?("Claude Code", projeto, v.duracao) }
                }
            }
        }
        r.trabalhando.sort { $0.ha > $1.ha }
        primeiraLeitura = false
        return r
    }

    private func soma(_ l: [AgentesDaIlha.Resposta]) -> Double? {
        var total = 0.0
        var algum = false
        for x in l { if let v = AgentesDaIlha.valor(modelo: x.modelo, uso: x.uso) { total += v; algum = true } }
        return algum ? total : nil
    }

    /// Lê só o que o arquivo ganhou desde a última vez, até a última linha
    /// completa; das linhas, só as de resposta com uso viram JSON.
    /// Em blocos de até 4 MB: um registro de sessão longa passa de 100 MB, e
    /// lê-lo inteiro de uma vez deixaria o Docka pesado só para isso.
    private func lerNovidades(_ a: URL) {
        guard let h = try? FileHandle(forReadingFrom: a) else { return }
        defer { try? h.close() }
        guard let tamanho = try? h.seekToEnd() else { return }
        while true {
            let desde = posicoes[a.path] ?? 0
            guard tamanho > desde else { return }
            let lidos = autoreleasepool { lerBloco(h, a, desde: desde, ate: min(tamanho, desde + 4 << 20)) }
            if !lidos { return }
        }
    }

    /// Um bloco, até a última linha completa. Devolve se avançou.
    private func lerBloco(_ h: FileHandle, _ a: URL, desde: UInt64, ate: UInt64) -> Bool {
        try? h.seek(toOffset: desde)
        guard let dados = try? h.read(upToCount: Int(ate - desde)), let fim = dados.lastIndex(of: 0x0A) else {
            // uma linha maior que o bloco: pula o bloco inteiro para não travar
            if ate - desde >= 4 << 20 { posicoes[a.path] = ate; return true }
            return false
        }
        posicoes[a.path] = desde + UInt64(fim + 1)
        // filtro barato antes de decodificar: só linhas que falam de resposta
        let marca = Data("\"assistant\"".utf8)
        var inicio = dados.startIndex
        while inicio <= fim, let nl = dados[inicio...fim].firstIndex(of: 0x0A) {
            let linha = dados[inicio..<nl]
            inicio = nl + 1
            guard linha.range(of: marca) != nil,
                  let o = try? JSONSerialization.jsonObject(with: linha) as? [String: Any],
                  let x = AgentesDaIlha.respostaDoClaude(o) else { continue }
            if let k = x.chave, let i = indicePorChave[k] {
                respostas[i] = x        // a mesma mensagem de novo: fica a mais nova
            } else {
                if let k = x.chave { indicePorChave[k] = respostas.count }
                respostas.append(x)
            }
        }
        return true
    }

    // MARK: Codex (na fila)

    private func lerCodex() -> Codex {
        var r = Codex()
        let fm = FileManager.default
        guard let e = fm.enumerator(at: Self.pastaDoCodex, includingPropertiesForKeys: [.contentModificationDateKey]) else { return r }
        var arquivos: [(URL, Date)] = []
        for case let u as URL in e where u.pathExtension == "jsonl" {
            if let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate { arquivos.append((u, m)) }
        }
        guard let (maisNovo, quando) = arquivos.max(by: { $0.1 < $1.1 }) else { return r }
        r.encontrado = true
        r.ultima = quando
        guard let dados = try? Data(contentsOf: maisNovo) else { return r }
        var comecou = false
        for linha in dados.split(separator: 0x0A) {
            guard let o = try? JSONSerialization.jsonObject(with: linha) as? [String: Any] else { continue }
            if let l = AgentesDaIlha.limiteDoCodex(o) { r.primario = l.primario; r.secundario = l.secundario }
            if let p = o["payload"] as? [String: Any], let t = p["type"] as? String {
                if t == "task_started" { comecou = true } else if t == "task_complete" { comecou = false }
            }
        }
        r.trabalhando = comecou && Date().timeIntervalSince(quando) < 120
        return r
    }

    var atividade: Ilha.Atividade? {
        if let t = claude.trabalhando.first {
            return Ilha.Atividade(id: "agentes", tipo: .agente, simbolo: "sparkles", valor: AgentesDaIlha.duracao(t.ha), prioridade: 35)
        }
        if codex.trabalhando {
            return Ilha.Atividade(id: "agentes", tipo: .agente, simbolo: "sparkles", valor: "Codex", prioridade: 35)
        }
        return nil
    }

    /// Só para o autoteste de desenho.
    func simular(_ c: Claude, _ x: Codex) { claude = c; codex = x }
}

// MARK: - A vista

struct AgentesDaIlhaView: View {
    @ObservedObject private var m = AgentesModelo.shared
    private let laranja = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            cartaoClaude
            cartaoCodex
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        .foregroundStyle(.white)
    }

    private func cabecalho(_ nome: String, _ simbolo: String, _ cor: Color, estado: String, ativo: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: simbolo).font(.system(size: 12, weight: .semibold)).foregroundStyle(cor)
                .accessibilityHidden(true)
            Text(nome).font(.system(size: 12.5, weight: .semibold))
            Spacer()
            Text(estado).font(.system(size: 10, weight: .medium)).lineLimit(1)
                .foregroundStyle(ativo ? Color.black : Color.white.opacity(0.6))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(ativo ? Color.green : Color.white.opacity(0.1)))
                .accessibilityLabel(ativo ? "Trabalhando: \(estado)" : estado)
        }
    }

    private func barra(_ fracao: Double, _ cor: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(cor).frame(width: g.size.width * min(1, max(0, fracao)))
            }
        }
        .frame(height: 5)
    }

    private func linha(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(valor).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
        }
    }

    private func usoEValor(_ u: AgentesDaIlha.Uso, _ v: Double?) -> String {
        AgentesDaIlha.tokens(u.total) + " tokens" + (v.map { " · " + AgentesDaIlha.dolares($0) } ?? "")
    }

    private var cartaoClaude: some View {
        let c = m.claude
        let agora = Date()
        let estado: String = {
            if let t = c.trabalhando.first { return "\(t.projeto) · \(AgentesDaIlha.duracao(t.ha))" }
            if let u = c.ultima { return "parado · " + ArquivosDaIlha.quando(u, agora: agora) }
            return "sem uso"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            cabecalho("Claude Code", "sparkle", laranja, estado: estado, ativo: !c.trabalhando.isEmpty)
            if !c.encontrado {
                Text("Nenhum registro em ~/.claude").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
            } else {
                if let j = c.atual {
                    let fracao = agora.timeIntervalSince(j.inicio) / j.fim.timeIntervalSince(j.inicio)
                    HStack {
                        Text("Janela de 5 h").font(.system(size: 10.5, weight: .medium))
                        Spacer()
                        Text("renova às \(j.fim.formatted(date: .omitted, time: .shortened))").font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    barra(fracao, laranja)
                    linha("Nesta janela", usoEValor(j.uso, j.valor))
                } else {
                    linha("Janela de 5 h", "nenhuma aberta")
                }
                linha("Hoje", usoEValor(c.hoje, c.hojeValor))
                linha("7 dias", usoEValor(c.semana, c.semanaValor))
                if !c.modelos.isEmpty {
                    linha("Modelos", c.modelos.map { $0.replacingOccurrences(of: "claude-", with: "") }.joined(separator: ", "))
                }
                if c.trabalhando.count > 1 {
                    linha("Sessões ativas", c.trabalhando.map(\.projeto).joined(separator: ", "))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    private var cartaoCodex: some View {
        let x = m.codex
        let agora = Date()
        let estado = x.trabalhando ? "trabalhando" : (x.ultima.map { "parado · " + ArquivosDaIlha.quando($0, agora: agora) } ?? "sem uso")
        return VStack(alignment: .leading, spacing: 6) {
            cabecalho("Codex", "chevron.left.forwardslash.chevron.right", .white, estado: estado, ativo: x.trabalhando)
            if !x.encontrado {
                Text("Nenhum registro em ~/.codex").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(Array([x.primario, x.secundario].compactMap { $0 }.enumerated()), id: \.offset) { _, l in
                    HStack {
                        Text(l.janelaMinutos >= 10_000 ? "Semana" : (l.janelaMinutos >= 300 ? "Janela de 5 h" : "\(l.janelaMinutos) min"))
                            .font(.system(size: 10.5, weight: .medium))
                        Spacer()
                        let usado = AgentesDaIlha.usadoAgora(l, agora: agora)
                        Text("\(Int(usado))% usado").font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                    }
                    let usado = AgentesDaIlha.usadoAgora(l, agora: agora)
                    barra(usado / 100, usado > 80 ? .orange : .blue)
                    if let renova = l.renova {
                        linha(renova > agora ? "Renova" : "Renovou", renova.formatted(.dateTime.day().month().hour().minute()))
                    }
                }
                if let p = x.primario?.plano { linha("Plano", p) }
                if x.primario == nil { Text("Sem leitura do limite ainda").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }
}
