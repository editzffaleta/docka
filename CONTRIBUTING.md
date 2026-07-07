# Contribuindo com o Docka

Obrigado pelo interesse! O Docka é pequeno de propósito — contribuições são
bem-vindas desde que mantenham o app leve, sem dependências e sem permissões.

## Antes de começar

- **Bugs e ideias**: abra uma [issue](https://github.com/editzffaleta/docka/issues)
  descrevendo o comportamento atual, o esperado e sua versão do macOS.
- **Vulnerabilidades**: NÃO abra issue pública — siga a [Política de Segurança](SECURITY.md).
- **Mudanças grandes**: abra uma issue de discussão antes de escrever código,
  para alinharmos o escopo.

## Preparando o ambiente

Requisitos: macOS 14+ e as Command Line Tools do Xcode (`xcode-select --install`).

```bash
git clone https://github.com/editzffaleta/docka.git
cd docka
swift build          # compila
swift run            # roda (onboarding na primeira vez)
```

Iteração rápida durante o desenvolvimento:

```bash
swift build && pkill -f ".build/debug/Docka"; .build/debug/Docka &
```

Modo demo (bandeja fixa com hover simulado, útil para testar visual e capturas):

```bash
.build/debug/Docka --demo
```

## Princípios do projeto (inegociáveis)

1. **Zero dependências** — apenas SwiftUI, AppKit e frameworks do sistema.
   PRs que adicionem pacotes externos serão recusados.
2. **Zero permissões** — nada de Acessibilidade, Input Monitoring ou similares.
   Se a feature exige permissão TCC, ela não entra.
3. **Zero rede** — o app não faz nenhuma conexão de saída.
4. **Leve** — a bandeja precisa responder instantaneamente; evite trabalho
   pesado no timer de polling (roda 20×/s).

## Estilo de código

- Swift idiomático, SwiftUI declarativo; siga o estilo dos arquivos existentes.
- Comentários em **português**, curtos, explicando o *porquê* (restrições,
  truques de plataforma) — não o *o quê*.
- Interface: use os componentes de [Effects.swift](Sources/Docka/Effects.swift)
  (`glassCard`, `reveal`, `pulseGlow`, `AppLogo`, `PrimaryButton`) em vez de
  recriar visual. Paleta em `Theme` ([Models.swift](Sources/Docka/Models.swift)) —
  um accent só, textos em branco com opacidade.
- Todo botão custom usa `.buttonStyle(.plain)`.
- Números exibidos usam `design: .monospaced` e `.contentTransition(.numericText())`.
- Animações com `.spring`; interações têm estado de hover.

## Estrutura

| Arquivo | Responsabilidade |
|---------|-----------------|
| `DockaApp.swift` | `@main`, MenuBarExtra, janela principal, registro do atalho |
| `Models.swift` | `DockaStore` (estado/preferências), `PinnedApp`, `Theme` |
| `TrayController.swift` | `NSPanel` da bandeja, magnificação, polling do cursor |
| `HotKey.swift` | Atalho global ⌘⇧D (Carbon) |
| `OnboardingView.swift` | Fluxo de boas-vindas |
| `SettingsWindowView.swift` | Gerenciador (Apps / Comportamento / Sobre) |
| `Effects.swift` | Componentes visuais reutilizáveis |

## Processo de Pull Request

1. Fork e branch a partir de `main` (`git checkout -b minha-feature`).
2. Faça commits pequenos com mensagens descritivas em português
   (primeira linha ≤ 72 caracteres, imperativo: "Adiciona…", "Corrige…").
3. Antes de abrir o PR, confirme:
   - [ ] `swift build` limpo, sem warnings novos
   - [ ] App roda e a bandeja funciona (revelar, magnificar, abrir app, esconder)
   - [ ] Nenhuma dependência ou permissão nova
   - [ ] Mudanças visuais seguem o design system (e inclua um screenshot no PR)
4. Descreva no PR: o problema, a solução e como testar.
5. PRs são revisados assim que possível; ajustes podem ser pedidos antes do merge.

## Releases (mantenedor)

```bash
./scripts/make_dmg.sh <versão>        # gera dist/Docka-<versão>.dmg
gh release create v<versão> dist/Docka-<versão>.dmg --title "Docka <versão>"
```

Com conta Apple Developer, exporte `DOCKA_SIGN_ID` e `DOCKA_NOTARY_PROFILE`
antes para sair notarizado (detalhes no cabeçalho de `scripts/make_dmg.sh`).

## Licença

Ao contribuir, você concorda que sua contribuição será licenciada sob a
[licença MIT](LICENSE) do projeto.
