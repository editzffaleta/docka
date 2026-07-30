import Foundation
import CoreAudio
import AudioToolbox

/// Leitura e escrita do volume da saída de áudio padrão.
///
/// **Ao contrário do brilho, aqui a API é pública.** O `BrightnessBackend`
/// precisa do DisplayServices, framework não documentado que pode sumir numa
/// atualização; o volume sai do CoreAudio, documentado e estável. Também não
/// pede permissão nenhuma: nada de Acessibilidade, nada de Automação — não
/// estamos falando com outro app, e sim com o próprio subsistema de áudio.
///
/// O dispositivo é resolvido a cada chamada, de propósito: o usuário troca de
/// fone, conecta um monitor com alto-falante, e o "padrão" muda debaixo de nós.
enum VolumeBackend {

    /// Dispositivo de saída padrão do sistema, agora.
    private static func saidaPadrao() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var tam = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                            &addr, 0, nil, &tam, &id)
        return st == noErr && id != 0 ? id : nil
    }

    /// O volume "virtual" é o que o usuário entende por volume do sistema: o
    /// CoreAudio resolve sozinho se o dispositivo tem controle mestre ou só
    /// canais separados.
    private static func enderecoVolume() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func enderecoMudo() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// A saída atual aceita controle de volume?
    ///
    /// Nem toda aceita: saída digital ótica e alguns HDMI entregam o volume ao
    /// aparelho do outro lado. Quando é o caso, a interface esconde o controle
    /// em vez de oferecer um botão que não faz nada.
    static var disponivel: Bool {
        guard let dev = saidaPadrao() else { return false }
        var addr = enderecoVolume()
        return AudioObjectHasProperty(dev, &addr)
    }

    /// Volume atual (0…1), ou nil se não der para ler.
    ///
    /// Mudo conta como zero: é o que o usuário vê no menu de som, e deixar a
    /// régua marcando 50% com o Mac calado seria mentira.
    static func ler() -> Double? {
        guard let dev = saidaPadrao() else { return nil }
        if estaMudo(dev) == true { return 0 }
        var addr = enderecoVolume()
        var v: Float32 = 0
        var tam = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &tam, &v) == noErr else { return nil }
        return Double(v)
    }

    @discardableResult
    static func escrever(_ nivel: Double) -> Bool {
        guard let dev = saidaPadrao() else { return false }
        let alvo = Float32(max(0, min(1, nivel)))

        // Zero silencia de verdade e qualquer valor acima tira do mudo — sem
        // isso, subir a régua a partir do mudo mexeria num volume inaudível.
        definirMudo(dev, alvo == 0)

        var addr = enderecoVolume()
        var v = alvo
        return AudioObjectSetPropertyData(dev, &addr, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    private static func estaMudo(_ dev: AudioDeviceID) -> Bool? {
        var addr = enderecoMudo()
        guard AudioObjectHasProperty(dev, &addr) else { return nil }
        var m: UInt32 = 0
        var tam = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &tam, &m) == noErr else { return nil }
        return m != 0
    }

    private static func definirMudo(_ dev: AudioDeviceID, _ mudo: Bool) {
        var addr = enderecoMudo()
        guard AudioObjectHasProperty(dev, &addr) else { return }
        var m: UInt32 = mudo ? 1 : 0
        _ = AudioObjectSetPropertyData(dev, &addr, 0, nil,
                                       UInt32(MemoryLayout<UInt32>.size), &m)
    }

    /// Autoteste: lê, mexe, confere e devolve o que estava. Roda DENTRO do app,
    /// que é o único contexto que vale — no brilho foi testar fora dele que me
    /// levou ao caminho errado, e o hábito ficou.
    static func autoteste(paraArquivo caminho: String? = nil) -> String {
        let r = autoteste()
        if let caminho { try? r.write(toFile: caminho, atomically: true, encoding: .utf8) }
        return r
    }

    static func autoteste() -> String {
        guard disponivel else { return "indisponível: a saída atual não expõe volume" }
        guard let antes = ler() else { return "indisponível: leitura falhou" }
        let alvo = antes > 0.5 ? antes - 0.15 : antes + 0.15
        guard escrever(alvo) else { return "escrita recusada" }
        usleep(250_000)
        let depois = ler() ?? -1
        escrever(antes)
        return abs(depois - alvo) < 0.03
            ? "OK — leu \(Int(antes * 100))%, escreveu \(Int(alvo * 100))%, confirmou \(Int(depois * 100))%"
            : "FALHOU — alvo \(Int(alvo * 100))%, resultado \(Int(depois * 100))%"
    }
}
