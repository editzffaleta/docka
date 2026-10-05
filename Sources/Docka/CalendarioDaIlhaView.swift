import SwiftUI
import AppKit
import EventKit
import DockaCore

/// Os compromissos, pelo EventKit. Pede acesso aos Calendários na primeira vez
/// que a seção abre — e só lê.
final class CalendarioModelo: ObservableObject {
    static let shared = CalendarioModelo()

    private let loja = EKEventStore()
    @Published private(set) var eventos: [CalendarioDaIlha.Evento] = []
    @Published private(set) var estado: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var mes = Date()
    @Published var dia = Date()
    private var observador: NSObjectProtocol?

    static var permitido: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    var calendario: Calendar { Calendar.current }

    /// Chamado quando a seção aparece e, uma vez por minuto, pelo aviso.
    func atualizar() {
        guard !simulando else { return }
        estado = EKEventStore.authorizationStatus(for: .event)
        guard estado == .fullAccess else { return }
        if observador == nil {
            observador = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: loja,
                                                                queue: .main) { [weak self] _ in self?.carregar() }
        }
        carregar()
    }

    func pedirAcesso() {
        loja.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.atualizar() }
        }
    }

    /// O mês à vista, com uma semana de folga dos dois lados, e sempre hoje
    /// (para o aviso do próximo compromisso).
    private func carregar() {
        let cal = calendario
        guard let m = cal.dateInterval(of: .month, for: mes) else { return }
        let inicio = min(cal.date(byAdding: .day, value: -7, to: m.start)!, cal.startOfDay(for: Date()))
        let fim = max(cal.date(byAdding: .day, value: 7, to: m.end)!, cal.date(byAdding: .day, value: 2, to: Date())!)
        let pred = loja.predicateForEvents(withStart: inicio, end: fim, calendars: nil)
        eventos = loja.events(matching: pred).map { e in
            CalendarioDaIlha.Evento(
                id: e.eventIdentifier ?? UUID().uuidString, titulo: e.title ?? "Sem título",
                inicio: e.startDate, fim: e.endDate, diaInteiro: e.isAllDay,
                local: e.location.flatMap { $0.isEmpty ? nil : $0 },
                cor: e.calendar.map { Self.hex($0.color) },
                reuniao: CalendarioDaIlha.linkDeReuniao([e.url?.absoluteString, e.location, e.notes]))
        }
    }

    private static func hex(_ c: NSColor) -> String {
        guard let r = c.usingColorSpace(.sRGB) else { return "#888888" }
        return String(format: "#%02X%02X%02X", Int(r.redComponent * 255), Int(r.greenComponent * 255), Int(r.blueComponent * 255))
    }

    /// Só para o autoteste de desenho: eventos de exemplo, sem tocar no EventKit.
    private var simulando = false
    func simular(_ lista: [CalendarioDaIlha.Evento]) {
        simulando = true
        estado = .fullAccess
        eventos = lista
    }

    func mudarMes(_ passo: Int) {
        mes = calendario.date(byAdding: .month, value: passo, to: mes) ?? mes
        carregar()
    }

    var atividade: Ilha.Atividade? {
        guard Self.permitido, let e = CalendarioDaIlha.proximo(eventos, agora: Date()) else { return nil }
        return Ilha.Atividade(id: "calendario", tipo: .calendario, simbolo: "calendar",
                              valor: CalendarioDaIlha.quando(e, agora: Date(), calendario: calendario,
                                                             hora: { $0.formatted(date: .omitted, time: .shortened) }),
                              prioridade: 70)
    }
}

extension Color {
    init(hex: String?) {
        guard let h = hex?.dropFirst(), h.count == 6, let v = UInt32(h, radix: 16) else { self = .gray; return }
        self = Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

struct CalendarioDaIlhaView: View {
    @ObservedObject private var m = CalendarioModelo.shared

    var body: some View {
        Group {
            switch m.estado {
            case .fullAccess: agenda
            case .notDetermined:
                pedido("Mostrar os seus compromissos?", "O Docka só lê o calendário, e nada sai do Mac.", "Permitir") { m.pedirAcesso() }
            default:
                pedido("Sem acesso aos Calendários", "Libere o Docka em Privacidade e Segurança → Calendários.", "Abrir Ajustes") {
                    if let u = URL(string: Permissao.calendarios.enderecoDosAjustes) { NSWorkspace.shared.open(u) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 6)
        .foregroundStyle(.white)
        .onAppear { m.atualizar() }
    }

    private func pedido(_ titulo: String, _ detalhe: String, _ botao: String, _ acao: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 22)).foregroundStyle(.red)
            Text(titulo).font(.system(size: 13, weight: .semibold))
            Text(detalhe).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            Button(action: acao) {
                Text(botao).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var agenda: some View {
        HStack(alignment: .top, spacing: 14) {
            mesEmGrade.frame(width: 206)
            listaDoDia.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: o mês

    private var mesEmGrade: some View {
        let cal = m.calendario
        let casas = CalendarioDaIlha.grade(do: m.mes, calendario: cal)
        let comEvento = Set(m.eventos.map { cal.startOfDay(for: $0.inicio) })
        let titulo = m.mes.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "pt_BR")))
        let iniciais = Array(cal.veryShortStandaloneWeekdaySymbols[(cal.firstWeekday - 1)...] +
                             cal.veryShortStandaloneWeekdaySymbols[..<(cal.firstWeekday - 1)])
        return VStack(spacing: 4) {
            HStack {
                Text(titulo.prefix(1).uppercased() + titulo.dropFirst()).font(.system(size: 12, weight: .semibold))
                Spacer()
                setinha("chevron.left", "Mês anterior") { m.mudarMes(-1) }
                setinha("chevron.right", "Próximo mês") { m.mudarMes(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array(iniciais.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                }
                ForEach(Array(casas.enumerated()), id: \.offset) { _, d in
                    if let d { casa(d, temEvento: comEvento.contains(cal.startOfDay(for: d))) }
                    else { Color.clear.frame(height: 20) }
                }
            }
        }
    }

    private func casa(_ d: Date, temEvento: Bool) -> some View {
        let cal = m.calendario
        let hoje = cal.isDateInToday(d)
        let escolhido = cal.isDate(d, inSameDayAs: m.dia)
        return Button { m.dia = d } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: d))")
                    .font(.system(size: 10.5, weight: hoje ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(escolhido ? Color.black : (hoje ? Color.red : Color.white))
                Circle().fill(temEvento ? (escolhido ? Color.black : Color.white.opacity(0.6)) : Color.clear)
                    .frame(width: 3, height: 3)
            }
            .frame(width: 24, height: 20)
            .background(Circle().fill(escolhido ? (hoje ? Color.red : Color.white) : Color.clear).frame(width: 20, height: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(d.formatted(date: .complete, time: .omitted))
    }

    private func setinha(_ s: String, _ rotulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: s).font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
    }

    // MARK: o dia

    private var listaDoDia: some View {
        let cal = m.calendario
        let doDia = CalendarioDaIlha.doDia(m.eventos, m.dia, calendario: cal)
        let titulo = cal.isDateInToday(m.dia) ? "Hoje" : (cal.isDateInTomorrow(m.dia) ? "Amanhã"
            : m.dia.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))))
        return VStack(alignment: .leading, spacing: 6) {
            Text(titulo.prefix(1).uppercased() + titulo.dropFirst()).font(.system(size: 12, weight: .semibold))
            if doDia.isEmpty {
                Text("Nenhum compromisso").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 10)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(doDia) { linha($0) }
                    }
                }
            }
        }
    }

    private func linha(_ e: CalendarioDaIlha.Evento) -> some View {
        let cal = m.calendario
        let agora = Date()
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: e.cor)).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.titulo).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                Text(e.diaInteiro ? "Dia inteiro"
                     : "\(e.inicio.formatted(date: .omitted, time: .shortened)) – \(e.fim.formatted(date: .omitted, time: .shortened))"
                       + (e.local.map { " · \($0)" } ?? ""))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if cal.isDateInToday(e.inicio) && e.fim > agora && !e.diaInteiro {
                Text(CalendarioDaIlha.quando(e, agora: agora, calendario: cal,
                                             hora: { $0.formatted(date: .omitted, time: .shortened) }))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(e.acontecendo(em: agora) ? Color.green : Color.orange)
            }
            if let r = e.reuniao {
                Button { NSWorkspace.shared.open(r) } label: {
                    Text("Entrar").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Color.green))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Entrar na reunião \(e.titulo)")
            }
        }
        .padding(.vertical, 2)
    }
}
