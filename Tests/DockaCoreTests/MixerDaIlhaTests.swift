import Testing
import Foundation
@testable import DockaCore

@Suite("Mixer da ilha")
struct MixerDaIlhaTests {
    @Test("Processo auxiliar do navegador conta como do navegador")
    func dono() {
        let apps = ["com.brave.Browser", "com.google.Chrome", "com.spotify.client", "com.google"]
        #expect(MixerDaIlha.dono("com.brave.Browser.helper", apps: apps) == "com.brave.Browser")
        #expect(MixerDaIlha.dono("com.google.Chrome.helper.Renderer", apps: apps) == "com.google.Chrome")
        #expect(MixerDaIlha.dono("com.spotify.client", apps: apps) == "com.spotify.client")
        #expect(MixerDaIlha.dono("com.apple.WebKit.GPU", apps: apps) == "com.apple.WebKit.GPU")
        #expect(MixerDaIlha.dono("com.brave.BrowserX", apps: apps) == "com.brave.BrowserX")   // não é prefixo de verdade
    }

    @Test("Curva do controle e rótulo")
    func curva() {
        #expect(MixerDaIlha.ganho(1) == 1)
        #expect(MixerDaIlha.ganho(0.5) == 0.25)
        #expect(MixerDaIlha.ganho(1.5) == 1.5)
        #expect(MixerDaIlha.ganho(-1) == 0)
        #expect(MixerDaIlha.rotulo(0.354) == "35%")
        #expect(!MixerDaIlha.precisaDesviar(1.0))
        #expect(MixerDaIlha.precisaDesviar(0.9))
    }
}
