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
| Órbita com submenus | ✅ pronto | item do tipo "anel" que abre outro anel; ações rápidas como item |

## Fase 2 — Sistema e energia (sem permissão)

| Recurso | Como |
|---|---|
| ✅ Monitor do sistema | CPU/memória (`host_statistics`), bateria (`IOPowerSources`), disco, rede (`getifaddrs`) — régua ou painel de borda |
| ✅ Leituras na barra de menus | texto curto no `MenuBarExtra` |
| ✅ Alertas | CPU alta contínua, memória, disco, bateria e temperatura — cartão próprio (as notificações do sistema pediriam autorização) |
| ✅ Brilho por monitor | brilho de hardware por tela + escurecimento por gama em qualquer monitor; ✅ DDC/CI nos monitores externos (só brilho; lê antes de escrever) |

## Fase 3 — Área de transferência e texto (pede Acessibilidade para colar)

| Recurso | Como |
|---|---|
| ✅ Histórico do clipboard | polling do `NSPasteboard.changeCount` (sem permissão); colar automaticamente exige Acessibilidade |
| ✅ Colar sem formatação | reescreve o pasteboard como texto puro |
| ✅ Limpar o clipboard automaticamente | temporizador de 1 min a 1 h e ✅ ao travar a tela ou dormir |
| ✅ Snippets de texto (painel) | painel pesquisável com variáveis; com o módulo "Colar sozinho" (Acessibilidade) insere direto |
| ✅ Colar sozinho | módulo opcional com Acessibilidade: ⌘V sintético no layout do teclado em uso |
| ✅ Expandir gatilhos digitados | módulo com Monitoramento de Entrada + Acessibilidade; memória de 32 caracteres |
| ✅ Limpar URL | remove `utm_*`, `fbclid` etc. do link copiado |

## Fase 4 — Janelas, mouse e captura (pede Acessibilidade e Gravação de Tela)

| Recurso | Permissão |
|---|---|
| ✅ Encaixe de janelas e layouts (atalhos e menu) | Acessibilidade — ✅ também arrastando até a borda, com prévia |
| ✅ Alternador de apps | atalho próprio, ordem de uso, sem permissão; janelas por título com Acessibilidade — ✅ prévias pelo ScreenCaptureKit (Gravação de Tela) |
| ✅ Rolagem suave, inverter rolagem, botões laterais | Acessibilidade (event tap só de mouse) — ✅ apps a ignorar; atalhos por botão ficam para depois |
| ✅ Conta-gotas, texto da tela (OCR + QR), captura de área | conta-gotas sem permissão; o resto com Gravação de Tela |
| ✅ Editor de anotação | seta, retângulo, caneta, marca-texto, texto, borrão e recorte; exporta em resolução Retina |

## Fase 5 — Janelas e o Dock da Apple (pede Acessibilidade)

Itens da lista do Vorssaint que tinham ficado de fora deste roteiro sem
registro — acrescentados aqui.

| Recurso | Permissão | Status |
|---|---|---|
| Sair ao fechar a última janela (por app) | Acessibilidade | ✅ |
| Proteção do ⌘Q e ⌘W (segurar, toque duplo ou tecla extra) | Acessibilidade | ✅ |
| Botão verde maximiza sem criar outro Espaço | Acessibilidade | ✅ |
| Cliques no Dock: minimizar, ocultar ou alternar janelas | Acessibilidade | ✅ |
| Prévia do Dock: janelas do app ao passar o mouse no ícone | Acessibilidade + Gravação de Tela | ✅ |
| Alternador: busca e filtros | — (filtros: Acessibilidade) | ✅ |
| Arrastar janelas segurando uma tecla, de qualquer ponto | Acessibilidade | ✅ |

## Fase 6 — Ilha Dinâmica

Uma ilha preta em volta do recorte da câmera (ou simulada, em Macs sem
recorte): passa o cursor e ela cresce; clica e abre uma grade de seções.
Fechada, mostra atividades ao vivo (timer, download, música), sozinhas ou
combinadas. Seções e atalhos configuráveis; botões redondos dos lados.
Escrita do zero — o visual segue a ideia, sem código, textos ou imagens de
outro projeto.

| Etapa | O que entra | Permissão | Status |
|---|---|---|---|
| 1. A ilha | forma em volta do recorte (e simulada), crescer ao passar o cursor, abrir e fechar, grade de seções com atalhos, botões dos lados, atividades ao vivo combináveis, ajustes | — | ✅ |
| 2. Timer | temporizador com régua, Pomodoro e cronômetro, com atividade ao vivo | — | ✅ |
| 3. Seções do Docka | Controles, Sistema, Arquivos (soltar arquivos na ilha), Rascunho, Capturas recentes, Downloads com progresso | — (Downloads: pasta escolhida) | ✅ |
| 4. Música | tocando agora com capa e controles, equalizador ao vivo, letra sincronizada | Automação (Música, Spotify) | ✅ |
| 5. Calendário e mixer | agenda do dia e do mês; volume por app | Calendários | ✅ |
| 6. Câmera e notificações | espelho da câmera; notificações recentes na ilha | Câmera; Acessibilidade | ✅ |
| 7. Agentes de IA | Claude Code e outros: limites, tokens, modelo, projeto e aviso de tarefa longa terminada, lendo os registros locais | — | ✅ |
| 8. Além do original | bateria e carregamento, fones conectando, área de transferência, avisos de volume e brilho (o Foco ficou de fora: o macOS só o informa a apps com um direito especial da Apple ou com Acesso Total ao Disco) | — | ✅ |

## Fase 7 — O resto da lista do Vorssaint

O que ainda falta da lista de recursos do Vorssaint, do mais simples ao mais
pesado. Cada um escrito do zero, opcional e desligado por padrão.

| Grupo | Recursos | Permissão | Status |
|---|---|---|---|
| 1. Ajustes do sistema | Espaços em ordem fixa; impedir o app Música de abrir sozinho; Bluetooth desligado no repouso; aceleração do ponteiro | — | ✅ |
| 2. Mouse e teclado | foco segue o mouse; filtro de clique duplo acidental; repique de teclas; tecla super; atalhos nos botões do mouse; clique do meio | Acessibilidade | ✅ |
| 3. Finder e arquivos | recortar e colar no Finder (⌘X/⌘V); instalador de imagem de disco (.dmg) | Acessibilidade (Finder) | ✅ |
| 4. Painéis | barra de comando (apps, janelas, arquivos, histórico, snippets, comandos de menu, contas, conversões, emojis); painel rápido; alternâncias rápidas; modo de limpeza | Acessibilidade (partes) | ✅ |
| 5. Áudio | ferramentas do microfone; saída de som por app | áudio do sistema | ✅ |
| 6. Mídia | gravação de tela; converter e comprimir vídeo e imagem | Gravação de Tela | ⏳ |
| 7. Manutenção | atualizações de apps; limpeza de caches; downloads dos mensageiros; desinstalador; Homebrew; portas abertas | — (partes: Acesso Total ao Disco) | ⏳ |

Ficam de fora: controle de ventoinha (o MacBook Air não tem ventoinha, e
exigiria um ajudante com privilégio de root) e brilho extra (só em telas
XDR).

## Fora do escopo

Coisas do Vorssaint que não combinam com um app de borda leve e sem
dependências: controle de ventoinha (helper com root), gerenciador do
Homebrew, atualizador de apps, desinstalador, gravação de tela com editor de
vídeo. (A Ilha Dinâmica e os agentes de IA saíram daqui: viraram a fase 6.) Podem ser reavaliadas
depois.
