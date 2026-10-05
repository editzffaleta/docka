# Política de Segurança

## Versões com suporte

| Versão | Suporte |
|--------|---------|
| 1.x (mais recente) | ✅ Correções de segurança |
| Anteriores à última release | ❌ Atualize para a versão mais recente |

Apenas a release mais recente recebe correções. Como o Docka é leve e sem
migrações de dados, atualizar é sempre seguro: basta substituir o app.

## Como reportar uma vulnerabilidade

**Não abra uma issue pública para vulnerabilidades.**

1. Use a aba **[Security → Report a vulnerability](https://github.com/editzffaleta/docka/security/advisories/new)**
   do GitHub (relato privado), ou
2. Envie e-mail para **iosgithub.unsaddle264@passmail.com** com o assunto `[SEGURANÇA] Docka`.

Inclua, se possível:
- Versão do Docka e do macOS
- Passos para reproduzir
- Impacto esperado (o que um atacante conseguiria fazer)
- Prova de conceito, se houver

### O que esperar

| Etapa | Prazo alvo |
|-------|-----------|
| Confirmação de recebimento | até 72 horas |
| Avaliação inicial e triagem | até 7 dias |
| Correção publicada (se confirmada) | até 30 dias, conforme a gravidade |

Vulnerabilidades confirmadas são corrigidas em uma release nova e creditadas ao
pesquisador no changelog (a menos que prefira anonimato).

## Modelo de segurança do Docka

Para avaliar o impacto de um achado, vale conhecer o que o app **faz e não faz**:

### O que o Docka acessa
- **Posição do cursor** via `NSEvent.mouseLocation` (API pública, sem permissão TCC)
- **Lista de apps** em `/Applications` e `/System/Applications` (somente leitura de nomes/ícones)
- **Preferências próprias** em `UserDefaults` (caminhos dos apps fixados e ajustes)
- **Lançamento de apps** via `NSWorkspace` (mesmo mecanismo do Finder)
- **Área de transferência**, só com o histórico, a limpeza de links ou o
  "apagar depois de um tempo" ligados: lê o conteúdo quando o contador de
  mudanças muda. Itens marcados como sigilosos pela convenção
  nspasteboard.org (senhas de gerenciadores) são ignorados
- **Arquivos próprios** em `~/Library/Application Support/Docka/`: `notas.json`
  (bloco de notas), `snippets.json` e — com "Lembrar entre aberturas" ligado —
  `historico.json`. São **JSON em texto puro, sem criptografia**, protegidos
  apenas pelas permissões da sua conta: o histórico pode conter o que você
  copiou (exceto o que foi marcado como sigiloso). Desligue "Lembrar entre
  aberturas" para o histórico viver só na memória
- **DDC/CI** com monitores externos, pelo cabo de vídeo (funções `IOAVService*` do
  IOKit, privadas): só lê e escreve o **brilho** (código VCP 0x10), nunca
  escreve sem uma leitura bem-sucedida antes e mantém o valor entre 0 e o
  máximo que o monitor informa. Não pede permissão
- **Contadores do sistema** para o monitor (CPU, memória, rede, bateria, disco)
  e a **tabela de gama** das telas para o escurecimento — APIs públicas, sem permissão

### O que o Docka NÃO faz
- ❌ O núcleo não pede permissão de Acessibilidade, Monitoramento de Entrada ou
  Gravação de Tela. Permissões só existem em **módulos opcionais**, desligados
  por padrão e pedidos apenas quando você os liga:

  | Módulo | Permissão | Para quê, e só isso |
  |---|---|---|
  | Expandir gatilhos | Monitoramento de Entrada + Acessibilidade | Ver as teclas digitadas para achar o gatilho de um snippet (guarda só os últimos 32 caracteres, na memória; campos de senha nunca chegam) e então apagar o gatilho e colar o texto |
  | Colar sozinho | Acessibilidade | Enviar um ⌘V ao app da frente depois que você escolhe um item do histórico ou um snippet |
  | Alternador — mostrar cada janela | Acessibilidade | Listar as janelas abertas pelo título e trazer a escolhida para a frente |
  | Alternador — filtros | Acessibilidade | Ler a posição das janelas para filtrar por tela e esconder apps sem janela |
  | Alternador — prévias | Gravação de Tela | Capturar miniaturas das janelas só enquanto o alternador está aberto; ficam na memória e somem ao fechar |
  | Captura | Gravação de Tela | Capturar a área que você seleciona (pelo seletor do próprio macOS) para copiar o texto, ler um QR ou salvar a imagem. O reconhecimento roda no Mac, pelo Vision; nada é enviado |
  | Ajustes do mouse | Acessibilidade | Interceptar rolagem e botões extras do mouse (nunca o teclado) para inverter, deixar linear, suavizar e voltar/avançar |
  | Sair ao fechar | Acessibilidade | Contar as janelas dos apps escolhidos e pedir o encerramento quando chegam a zero |
  | Proteção do ⌘Q e ⌘W | Acessibilidade | Interceptar o teclado, agindo só sobre ⌘Q e ⌘W; as outras teclas passam sem serem guardadas |
  | Ilha — notificações | Acessibilidade | Ler, uma vez por segundo, os avisos que estão na tela (os grupos `AXNotificationCenterBanner` da Central de Notificações): app, título, subtítulo e texto. Só com a opção ligada, só na memória (até 30), apagados ao travar a tela |
  | Ilha — espelho da câmera | Câmera | Mostrar a imagem ao vivo; a captura só roda com a seção à vista ou o espelho aberto, e nenhum quadro é salvo |
  | Ilha — calendário | Calendários | Ler os compromissos (título, hora, local, notas para achar o link da reunião); nunca escreve nem envia |
  | Ilha — mixer por app | Gravação de áudio do sistema | Só para os apps cujo volume você mudou: o som deles passa por um toque de processo do Core Audio e volta à saída com outro ganho, sem ser gravado; com o controle em 100% ou o Docka fechado, o macOS desfaz o toque |
  | Ilha — equalizador ao vivo | Gravação de Tela | Medir o áudio que o Mac toca, em pedaços de 21 ms que são medidos e descartados — só com a opção ligada e a música tocando |
  | Ilha — capturas e downloads | Acesso à pasta | Listar nome, data e miniatura dos arquivos recentes da pasta de capturas e de Downloads, só com a seção aberta; o progresso dos downloads vem do que os navegadores anunciam, sem ler os arquivos |
  | Prévia do Dock | Acessibilidade | Perguntar qual ícone do Dock está sob o cursor (só perto da borda da tela) e listar, trazer ou fechar as janelas do app |
  | Prévia do Dock — miniaturas | Gravação de Tela | Capturar as janelas do app só enquanto a prévia está aberta; ficam na memória e somem ao fechar |
  | Arrastar segurando teclas | Acessibilidade | Interceptar cliques só com as teclas escolhidas apertadas, e mover ou redimensionar a janela sob o cursor |
  | Botão verde e cliques no Dock | Acessibilidade | Interceptar cliques e perguntar o que está sob o cursor; só o botão verde e ícones de app no Dock são assumidos |
  | Encaixar janelas | Acessibilidade | Ler e mudar posição e tamanho da janela da frente quando você usa um atalho ou o menu Janelas |

- ❌ Não captura teclado (os atalhos usam `RegisterEventHotKey`, que entrega apenas aquele atalho) — **exceto** com o módulo "Expandir gatilhos" ligado, que escuta as teclas como descrito na tabela acima
- ⚠️ Acessa a rede em DOIS casos, ambos por ação sua. Primeiro, a letra sincronizada da
  ilha (opcional, desligada por padrão): manda título, artista, álbum e duração
  da música ao lrclib.net, uma base aberta. Segundo: ao adicionar um site à órbita, busca o ícone
  (apple-touch-icon/favicon) **no próprio site digitado** — nunca em resolvedor de
  terceiros, que receberia sua lista de sites. Sessão efêmera (sem cookies),
  resposta limitada a 1 MB, resultado em cache local; sem rede, o anel usa um
  globo desenhado localmente. Fora isso: nenhuma conexão de saída, telemetria
  ou atualização automática
- ❌ Não lê conteúdo de arquivos do usuário (arrastar-e-soltar apenas repassa URLs ao app de destino via `NSWorkspace`)
- ❌ Não roda com privilégios elevados nem instala helpers/daemons
- ℹ️ Mouse e teclado, cada um só com a opção ligada: o "repique de teclas" e a
  "tecla super" interceptam o teclado (só olham o código da tecla e o momento, para
  descartar a repetição ou somar ⌃⌥⇧⌘ — nada é guardado); a tecla super remapeia o
  Caps Lock para F18 no sistema de eventos (`UserKeyMapping`, somado aos remapeamentos
  que já existiam e desfeito ao desligar ou fechar o Docka); o clique do meio lê só a
  CONTAGEM de dedos no trackpad, pela MultitouchSupport do sistema
- ℹ️ Finder, cada um só com a opção ligada: o recortar e colar intercepta o teclado
  só com o Finder na frente e só olha ⌘X e ⌘V; o instalador de .dmg lê o
  `hdiutil info` para saber de que imagem veio o volume, copia o app para
  /Applications só depois do seu clique, e o que é substituído ou apagado vai
  para o Lixo — nada é apagado de vez
- ℹ️ Manutenção: nada roda sozinho. As atualizações só consultam a rede ao clicar em
  Procurar (o feed declarado por cada app e a busca pública da App Store, em sessão
  efêmera); limpeza, mensageiros e desinstalador movem para o Lixo, nunca apagam de
  vez, e recusam apps do macOS; o Homebrew roda os comandos do próprio `brew`, com
  as permissões do usuário; "Encerrar" nas portas manda o pedido normal de fechar
  (SIGTERM) a um processo do próprio usuário, depois de confirmar
- ℹ️ Mídia: a gravação de tela usa o ScreenCaptureKit só entre o início e o
  parar que você escolhe, grava num arquivo local e deixa as janelas do Docka fora
  da imagem; as ferramentas de mídia convertem com AVFoundation, ImageIO e Vision
  no próprio Mac, gravam ao lado do original e nunca o sobrescrevem
- ℹ️ Som: a saída de cada app usa o mesmo toque de processo do mixer (o som passa
  pelo Docka até a saída escolhida, só enquanto o app toca, e nada é gravado); o
  microfone preferido, o nível, o mudo e a troca de saída são propriedades de
  dispositivo do Core Audio, sem permissão — e os microfones silenciados voltam
  como estavam ao religar ou ao fechar o Docka
- ℹ️ Painéis: a barra de comando busca arquivos pelo Spotlight só na pasta pessoal
  e só enquanto está aberta, e lê os menus do app da frente pela Acessibilidade só
  ao abrir; os scripts salvos rodam no `zsh` do usuário (sem privilégio a mais) só
  quando escolhidos; o modo de limpeza descarta as teclas por um prazo fixo, sem
  ler nem guardar nada, e o prazo é conferido a cada tecla — o teclado volta mesmo
  que a interface trave. As alternâncias usam funções do sistema (claro/escuro pelo
  SkyLight, Dock automático pelo CoreDock, Night Shift pelo CoreBrightness), e
  esvaziar o Lixo pede ao Finder por Apple Events, só depois da sua confirmação
- ℹ️ Ajustes do sistema, cada um só com a opção ligada: "Espaços na ordem" grava
  `mru-spaces` nas preferências do Dock e reinicia o Dock; "Bluetooth no repouso"
  desliga e religa o Bluetooth pelo IOBluetooth (pede a permissão de Bluetooth);
  "aceleração do mouse" muda a propriedade `HIDMouseAcceleration` do sistema de
  eventos e guarda o valor de antes para devolvê-lo ao desligar
- ℹ️ A seção Agentes de IA da ilha lê os registros que o Claude Code (`~/.claude/projects`)
  e o Codex (`~/.codex/sessions`) gravam no Mac — só dos últimos 7 dias, e de cada linha
  só modelo, tokens, horário, projeto e motivo da parada; o texto das conversas não é
  guardado nem enviado. Nada sai do Mac
- ⚠️ A música da ilha roda o `/usr/bin/perl` do sistema, que carrega a
  `libDockaTocando.dylib` (código do próprio Docka, em `Sources/DockaTocando`) para
  ler o "tocando agora" — desde o macOS 15.4 esse serviço só responde a processos da
  Apple, e o perl do sistema é um. O processo só lê o que toca e envia tocar, pausar,
  anterior, próxima e posição; sai sozinho quando o Docka fecha a entrada dele

### Áreas de interesse para pesquisadores
- Manuseio de URLs no arrastar-e-soltar (`.dropDestination`) — injeção de caminhos maliciosos
- Persistência de caminhos em `UserDefaults` — apontar itens fixados para binários inesperados
- O painel `NSPanel` em `level: .mainMenu` — sobreposição/spoofing de interface de outros apps
- O histórico da área de transferência — vazamento de conteúdo sigiloso que não use as marcas de nspasteboard.org
- O ⌘V sintético do "Colar sozinho" — colar no app errado se o foco mudar no intervalo de ~0,1 s
- O perl da música da ilha — o caminho da biblioteca vem do próprio pacote do app; trocar a dylib nos Recursos executaria código com a identidade do perl

## Verificação de integridade das releases

Os DMGs publicados nas releases têm assinatura ad-hoc (sem notarização, por ora).
Para verificar que o app não foi adulterado após o download:

```bash
codesign -dv --verbose=2 /Applications/Docka.app   # confere a assinatura
shasum -a 256 Docka-<versão>.dmg                    # compare com o hash da release
```

A partir do momento em que houver assinatura Developer ID e notarização, esta
seção será atualizada com o Team ID esperado.
