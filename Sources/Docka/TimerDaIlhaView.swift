import SwiftUI
import DockaCore

/// A seção Timer da ilha: abas Timer, Pomodoro e Cronômetro.
struct TimerDaIlhaView: View {
    let mudar: (_ mudar: (inout TimerDaIlha, Date) -> Void) -> Void
    @EnvironmentObject var e: IlhaEstado

    private var t: TimerDaIlha { e.timer }
    private let laranja = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if t.ativo { correndo } else { parado }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .foregroundStyle(.white)
    }

    // MARK: parado: abas, ajuste e Iniciar

    private var parado: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(TimerDaIlha.Modo.allCases) { m in
                    Button { mudar { x, _ in x.modo = m } } label: {
                        Text(m.titulo)
                            .font(.system(size: 11.5, weight: t.modo == m ? .semibold : .regular))
                            .foregroundStyle(t.modo == m ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(t.modo == m ? 0.14 : 0)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { mudar { x, agora in
                    if x.modo == .cronometro { x.alternarCronometro(em: agora) } else { x.iniciar(em: agora) }
                } } label: {
                    Text("Iniciar").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 5)
                        .background(Capsule().fill(laranja))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            switch t.modo {
            case .temporizador: reguaDoTemporizador
            case .pomodoro:     ajustesDoPomodoro
            case .cronometro:
                HStack {
                    Spacer()
                    Text(TimerDaIlha.cronometro(0)).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    /// Régua de 1 a 60 minutos, com marcas a cada minuto e número a cada cinco.
    private var reguaDoTemporizador: some View {
        HStack(alignment: .center, spacing: 16) {
            GeometryReader { geo in
                let limite = TimerDaIlha.limiteDaRegua
                let passo = geo.size.width / CGFloat(limite)
                ZStack(alignment: .topLeading) {
                    ForEach(0...limite, id: \.self) { m in
                        let forte = m % 5 == 0
                        Rectangle()
                            .fill(m <= t.minutos ? laranja : Color.white.opacity(0.3))
                            .frame(width: 1.5, height: forte ? 22 : 14)
                            .offset(x: CGFloat(m) * passo - 0.75, y: forte ? 16 : 20)
                        if forte && m > 0 {
                            Text("\(m)").font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                                .foregroundStyle(m <= t.minutos ? laranja : Color.white.opacity(0.5))
                                .fixedSize()
                                .offset(x: CGFloat(m) * passo - 6, y: 0)
                        }
                    }
                    Image(systemName: "triangle.fill").font(.system(size: 7)).foregroundStyle(laranja)
                        .offset(x: CGFloat(t.minutos) * passo - 3.5, y: 40)
                }
                // os traços se posicionam por deslocamento, que não conta no
                // tamanho: sem este quadro, a área de toque teria o tamanho de
                // um traço só
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .overlay(ToqueAbsolutoAppKit { x in
                    let m = Int((x / passo).rounded())
                    mudar { t, _ in t.minutos = min(limite, max(1, m)) }
                })
            }
            .frame(height: 50)
            Text(TimerDaIlha.relogio(TimeInterval(t.minutos * 60)))
                .font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(laranja)
                .frame(width: 96, alignment: .trailing)
        }
    }

    private var ajustesDoPomodoro: some View {
        HStack(spacing: 22) {
            passo("Foco", t.minutosDeFoco, 5...90) { v in mudar { x, _ in x.minutosDeFoco = v } }
            passo("Pausa", t.minutosDePausa, 1...30) { v in mudar { x, _ in x.minutosDePausa = v } }
            passo("Pausa longa", t.minutosDePausaLonga, 5...60) { v in mudar { x, _ in x.minutosDePausaLonga = v } }
            Spacer()
            Text("A cada \(t.focosAntesDaLonga) focos, uma pausa longa")
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.trailing)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.top, 6)
    }

    private func passo(_ titulo: String, _ valor: Int, _ faixa: ClosedRange<Int>,
                       _ definir: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 6) {
                redondo("minus", "Menos um minuto de \(titulo.lowercased())", tamanho: 22) { definir(max(faixa.lowerBound, valor - 1)) }
                Text("\(valor) min").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 52)
                redondo("plus", "Mais um minuto de \(titulo.lowercased())", tamanho: 22) { definir(min(faixa.upperBound, valor + 1)) }
            }
        }
    }

    // MARK: correndo

    @ViewBuilder
    private var correndo: some View {
        if t.modo == .cronometro { cronometroCorrendo } else { contagemCorrendo }
    }

    private var contagemCorrendo: some View {
        let restante = t.restante(em: e.agora)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                redondo(t.rodando ? "pause.fill" : "play.fill", t.rodando ? "Pausar" : "Continuar", tamanho: 38, fundo: laranja, frente: .black) {
                    mudar { x, agora in if x.rodando { x.pausar(em: agora) } else { x.iniciar(em: agora) } }
                }
                redondo("xmark", "Parar", tamanho: 38) { mudar { x, _ in x.parar() } }
                if t.modo == .pomodoro {
                    redondo("forward.end.fill", "Pular para a próxima fase", tamanho: 38) {
                        // pula para o fim da fase: a próxima começa já
                        mudar { x, agora in
                            if case .pausado = x.corrida { x.iniciar(em: agora) }
                            x.corrida = .rodando(fim: agora)
                            _ = x.conferir(em: agora)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(t.modo == .pomodoro ? t.fase.titulo : "Timer")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(laranja)
                    if t.modo == .pomodoro {
                        HStack(spacing: 4) {
                            ForEach(0..<t.focosAntesDaLonga, id: \.self) { i in
                                Circle().fill(i < t.focosFeitos ? laranja : Color.white.opacity(0.25))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                }
                Text(TimerDaIlha.relogio(restante))
                    .font(.system(size: 44, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(t.rodando ? laranja : laranja.opacity(0.55))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(laranja).frame(width: geo.size.width * t.progresso(em: e.agora))
                }
            }
            .frame(height: 4)
        }
        .padding(.top, 4)
    }

    private var cronometroCorrendo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                redondo(t.rodando ? "pause.fill" : "play.fill", t.rodando ? "Pausar" : "Continuar", tamanho: 38, fundo: laranja, frente: .black) {
                    mudar { x, agora in x.alternarCronometro(em: agora) }
                }
                if t.rodando {
                    redondo("flag.fill", "Marcar volta", tamanho: 38) { mudar { x, agora in x.volta(em: agora) } }
                } else {
                    redondo("arrow.counterclockwise", "Zerar", tamanho: 38) { mudar { x, _ in x.zerarCronometro() } }
                }
                Spacer()
                Text(TimerDaIlha.cronometro(t.decorrido(em: e.agora)))
                    .font(.system(size: 44, weight: .semibold)).monospacedDigit().foregroundStyle(laranja)
            }
            if !t.voltas.isEmpty {
                HStack(spacing: 14) {
                    ForEach(Array(t.voltas.prefix(4).enumerated()), id: \.offset) { i, v in
                        Text("Volta \(t.voltas.count - i)  \(TimerDaIlha.cronometro(v))")
                            .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    private func redondo(_ simbolo: String, _ rotulo: String, tamanho: CGFloat, fundo: Color = Color.white.opacity(0.14),
                         frente: Color = .white, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo)
                .font(.system(size: tamanho * 0.38, weight: .bold))
                .foregroundStyle(frente)
                .frame(width: tamanho, height: tamanho)
                .background(Circle().fill(fundo))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
    }
}
