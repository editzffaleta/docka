# Roteiro — recursos inspirados no Vorssaint

O [Vorssaint](https://github.com/vorssaint/vorssaint-utils) serve só como
**referência de ideias**. Ele é GPL-3.0 e o Docka é MIT: nenhuma linha de código
dele entra aqui. Cada recurso é reescrito do zero, no estilo do Docka — lógica
pura no `DockaCore` com teste, casca no `Docka`. Também não usamos nome, logo nem
identidade visual do Vorssaint.

## Regras para os recursos novos

- **Desligado por padrão.** Quem não liga um recurso não paga nada por ele: sem
  timer, sem monitor, sem painel.
- **Sem permissão nas fases 1 e 2.** Esses recursos mantêm a promessa atual do
  Docka.
- **Fases 3 e 4 precisam de permissão** (Acessibilidade, Gravação de Tela).
  Entram como **módulos opcionais**, conforme a regra 2 do `CONTRIBUTING.md`:
  desligados por padrão e pedindo permissão só quando ligados. O núcleo
  (bandejas, órbita, réguas) continua sem pedir nada. Quando o primeiro módulo
  com permissão chegar, o README e o `SECURITY.md` ganham a lista do que cada
  um pede.

## Fase 1 — Bordas e lançamento (sem permissão)

| Recurso | Status | Como |
|---|---|---|
| Manter acordado | ✅ pronto | `IOPMAssertion` (IOKit, público) com timer; menu, atalho e seção Energia |
| Ações rápidas | ✅ pronto | travar tela, apagar telas, proteção de tela, repouso, ejetar discos, ocultar ícones da mesa |
| Prateleira (Shelf) | ✅ pronto | painel de borda que segura arquivos, textos e links arrastados |
| Bloco de notas | ✅ pronto | painel de borda com abas, salvamento automático e Markdown |
| Órbita com submenus | ⏳ | item do tipo "anel" que abre outro anel; ações rápidas como item |

## Fase 2 — Sistema e energia (sem permissão)

| Recurso | Como |
|---|---|
| Monitor do sistema | CPU/memória (`host_statistics`), bateria (`IOPowerSources`), disco, rede (`getifaddrs`) — régua ou painel de borda |
| Leituras na barra de menus | texto curto no `MenuBarExtra` |
| Alertas | CPU alta contínua, disco cheio, bateria baixa via `UserNotifications` |
| Brilho por monitor | estender o `BrightnessBackend` para várias telas |

## Fase 3 — Área de transferência e texto (pede Acessibilidade para colar)

| Recurso | Como |
|---|---|
| Histórico do clipboard | polling do `NSPasteboard.changeCount` (sem permissão); colar automaticamente exige Acessibilidade |
| Colar sem formatação | reescreve o pasteboard como texto puro |
| Limpar o clipboard automaticamente | timer e eventos de suspensão/bloqueio |
| Snippets de texto | expandir gatilhos exige Monitoramento de Entrada; o modo "menu pesquisável" não exige |
| Limpar URL | remove `utm_*`, `fbclid` etc. do link copiado |

## Fase 4 — Janelas, mouse e captura (pede Acessibilidade e Gravação de Tela)

| Recurso | Permissão |
|---|---|
| Encaixe de janelas e layouts | Acessibilidade |
| Alternador de apps com prévia | Gravação de Tela (prévia) + Acessibilidade |
| Rolagem suave, inverter rolagem, botões laterais | Acessibilidade / Monitoramento de Entrada |
| Captura de tela com anotação, OCR, conta-gotas | Gravação de Tela |

## Fora do escopo

Coisas do Vorssaint que não combinam com um app de borda leve e sem
dependências: controle de ventoinha (helper com root), gerenciador do
Homebrew, atualizador de apps, desinstalador, acompanhamento de agentes de IA,
Dynamic Island, gravação de tela com editor de vídeo. Podem ser reavaliadas
depois.
