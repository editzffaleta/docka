import Testing
@testable import DockaCore

@Suite("Ações rápidas")
struct AcaoRapidaTests {

    private func vol(_ caminho: String, raiz: Bool = false, interno: Bool = false,
                     ejetavel: Bool = false, removivel: Bool = false) -> VolumeMontado {
        VolumeMontado(caminho: caminho, nome: caminho, raiz: raiz, interno: interno,
                      ejetavel: ejetavel, removivel: removivel)
    }

    @Test("O disco interno nunca é ejetado")
    func interno() {
        let alvos = Ejecao.alvos([vol("/", raiz: true, interno: true),
                                  vol("/System/Volumes/Data", interno: true),
                                  vol("/Volumes/Dados", interno: true)])
        #expect(alvos.isEmpty)
    }

    @Test("SSD externo que não se diz ejetável entra mesmo assim")
    func ssdExterno() {
        // é o caso real que motivou o critério: USB-C, ejetável = falso
        let alvos = Ejecao.alvos([vol("/Volumes/M2 256 GB")])
        #expect(alvos.map(\.caminho) == ["/Volumes/M2 256 GB"])
    }

    @Test("Imagem de disco e pendrive entram")
    func removiveis() {
        let alvos = Ejecao.alvos([vol("/Volumes/Instalador", interno: true, ejetavel: true),
                                  vol("/Volumes/PEN", removivel: true)])
        #expect(alvos.count == 2)
    }

    @Test("Resumo do que aconteceu")
    func resumo() {
        #expect(Ejecao.resumo(ejetados: [], falhas: []) == "Nenhum disco para ejetar.")
        #expect(Ejecao.resumo(ejetados: ["PEN"], falhas: []) == "PEN foi ejetado.")
        #expect(Ejecao.resumo(ejetados: ["A", "B"], falhas: ["C"])
                == "2 discos ejetados. C está em uso e não foi ejetado.")
        #expect(Ejecao.resumo(ejetados: [], falhas: ["C", "D"]) == "Em uso, não ejetados: C, D.")
    }

    @Test("Chave ausente do Finder quer dizer ícones visíveis")
    func iconesDaMesa() {
        #expect(IconesDaMesa.visiveis(valorGravado: nil))
        #expect(IconesDaMesa.visiveis(valorGravado: ""))
        #expect(IconesDaMesa.visiveis(valorGravado: "1\n"))
        #expect(!IconesDaMesa.visiveis(valorGravado: "0\n"))
        #expect(!IconesDaMesa.visiveis(valorGravado: "false"))
    }

    @Test("A ação rápida vira atalho e volta")
    func atalho() {
        for a in AcaoRapida.allCases {
            #expect(AcaoDeAtalho(id: AcaoDeAtalho.rapida(a).id) == .rapida(a))
        }
        #expect(AcaoDeAtalho(id: "rapida:inexistente") == nil)
    }
}
