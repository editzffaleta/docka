# Docka

Uma bandeja de apps que vive escondida na borda inferior da tela do seu Mac.
Empurre o cursor para a borda e ela desliza para cima — com magnificação de
ícones, nome flutuante e indicador de apps abertos.

100% SwiftUI, sem dependências e **sem pedir nenhuma permissão do sistema**.

## Recursos

- 🪟 **Bandeja flutuante** em vidro (`ultraThinMaterial`) que aparece acima de
  qualquer janela, em todos os Spaces e apps em tela cheia
- 🔍 **Magnificação de ícones** com curva gaussiana — o ícone sob o cursor cresce
  até 1,75× a partir da linha de base e empurra os vizinhos
- 🏷️ **Balão com o nome** do app sobre o ícone ampliado
- ⚪ **Indicador de app em execução** (bolinha) sob cada ícone aberto
- 🐇 **Quique duplo** ao lançar um app
- 🎯 **Pressure Zone**: modo opcional que só revela a bandeja quando você empurra
  o cursor contra o canto de propósito — evita aberturas acidentais
- 🎛️ **Calibração ao vivo**: distância da borda e tamanho dos ícones ajustáveis
  com efeito imediato
- 🔊 Sons de sistema opcionais ao revelar e ao abrir apps
- 🧭 Onboarding em 3 passos + ícone na barra de menus com atalhos rápidos

## Como funciona

A bandeja é um `NSPanel` borderless não-ativante fixado na borda inferior
(`level: .mainMenu`, visível em todos os Spaces). A detecção do cursor é feita
por polling leve de `NSEvent.mouseLocation` (20×/s) — por isso não precisa de
permissão de Acessibilidade. Os ícones vêm de `NSWorkspace.shared.icon(forFile:)`
e a lista de apps instalados é lida de `/Applications` e `/System/Applications`.

## Rodando

Requer macOS 14+ e Xcode Command Line Tools.

```bash
git clone https://github.com/editzffaleta/docka.git
cd docka
swift run
```

Na primeira execução, o onboarding abre para você escolher os apps.
Depois, empurre o cursor até a borda inferior direita da tela. ✨

## Estrutura

```
Sources/Docka/
├── DockaApp.swift          # @main, MenuBarExtra, janela principal
├── Models.swift            # DockaStore (estado + preferências), PinnedApp
├── TrayController.swift    # NSPanel da bandeja + magnificação + polling do mouse
├── OnboardingView.swift    # fluxo de boas-vindas em 3 passos
├── SettingsWindowView.swift# abas Apps / Comportamento / Sobre
└── Effects.swift           # glass cards, aurora, partículas, botões
```

## Licença

MIT — veja [LICENSE](LICENSE).
