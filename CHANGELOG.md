# Registro de mudanças

Todas as mudanças relevantes do Docka, por versão. O formato segue o espírito
do [Keep a Changelog](https://keepachangelog.com/pt-BR/), em português — como
todo o resto por aqui.

## [Não lançado]

### Novo

- **Manter acordado**: impede o Mac de dormir por 15 min, 30 min, 1 h, 2 h,
  5 h ou até você desligar. Fica no menu da barra (que mostra o tempo
  restante e troca o ícone por uma xícara enquanto está ligado), na nova
  seção **Energia** dos ajustes e num atalho global próprio. Opcionalmente
  deixa a tela apagar e segura só o sistema. Usa a mesma asserção de energia
  do `caffeinate`: API pública, sem permissão, e liberada na hora se o Docka
  for encerrado.
- **Ações rápidas**: travar a tela, apagar as telas, proteção de tela,
  repouso, ejetar todos os discos e ocultar/mostrar os ícones da mesa. Ficam
  num submenu opcional da barra, numa seção própria dos ajustes e cada uma
  pode ter atalho global. Nenhuma pede permissão. "Ejetar todos" leva o que
  não for o disco interno — inclusive SSD externo que não se declara
  ejetável — e só mostra aviso quando algum disco em uso não sai.
- **Prateleira**: painel numa lateral para estacionar arquivos, textos e
  links. Abre sozinha quando qualquer arrasto começa (ou encostando na
  borda, ou pelo atalho), recebe vários itens de uma vez e devolve: clique
  abre (texto é copiado), arrastar leva um item, e a alça "Tudo" leva todos
  numa só sessão. Arquivos são só referenciados — movido ou apagado, o item
  sai sozinho. Sem permissão: o arrasto é percebido pelo contador da área
  de arrasto do sistema, que qualquer app pode ler.
- **Bloco de notas**: notas em abas numa lateral (a esquerda, por padrão,
  longe da prateleira), salvas sozinhas meio segundo depois da última
  tecla num arquivo próprio em Application Support. Aceita digitação sem
  tirar o foco do app em que você está; enquanto você escreve, não some
  com o cursor longe, e Esc devolve o teclado. O atalho abre já pronto para
  digitar. Pré-visualização de Markdown com títulos, listas, citações,
  código e tarefas que se marcam com um clique; exporta a nota como `.md`.
- **Órbita com submenus e ações rápidas**: dois tipos novos de item no
  anel. **Submenu** abre outro anel no mesmo lugar, sem trocar o anel
  ativo; clique no miolo ou Esc volta um nível, e só fecha no anel de
  partida. **Ação rápida** trava a tela, ejeta discos e afins direto do
  anel. Apagar um anel leva junto os submenus que apontavam para ele.
- **Monitor do sistema**: painel de borda (direita, na base, por padrão)
  com CPU, memória e rede em gráficos dos últimos dois minutos, disco livre
  e bateria com tempo restante, e aviso quando o Mac esquenta. Opcionalmente
  mostra uma leitura ao lado do ícone na barra de menus. Só mede enquanto o
  painel está aberto ou há leitura na barra. Conferido contra `top`,
  `vm_stat` e `pmset`; memória em base 1024, como o Monitor de Atividade.
- **Alertas**: um aviso de vidro no canto superior direito quando a CPU
  fica alta por minutos seguidos, a memória aperta, o disco está quase
  cheio, a bateria está baixa ou o Mac esquenta. Limites ajustáveis; cada
  alerta avisa uma vez e só volta a avisar depois que a situação normaliza
  com folga. O aviso é do próprio Docka — notificações do sistema pediriam
  autorização. Memória e temperatura chegam por evento do sistema, sem
  medição contínua.
- **Brilho por tela**: os ajustes de Brilho listam cada tela conectada,
  com o brilho do painel onde ele existe e um **escurecimento por software**
  em todas — que funciona em monitores externos sem controle de brilho e
  também vai abaixo do mínimo do painel. A régua da borda passa a valer em
  qualquer monitor: onde não há brilho de hardware, ela escurece pela gama.
  O escurecimento para em 80% (a tela nunca fica preta), é lembrado por
  monitor e some sozinho se o Docka encerrar.
- **Histórico da área de transferência**: textos, links e arquivos
  copiados, com busca (sem diferenciar acento), fixar no topo e navegação
  pelo teclado num painel que abre pelo atalho; escolher um item o devolve
  à área de transferência, pronto para ⌘V. Os últimos também ficam num
  submenu da barra. Senhas de gerenciadores (marcadas como sigilosas pela
  convenção nspasteboard.org) não entram. Pode viver só na memória.
- **Colar sem formatação**, **limpar rastreadores de links** (manual ou a
  cada cópia) e **apagar a área de transferência** depois de um tempo.
- **Snippets**: textos prontos com `{data}`, `{hora}`, `{dia}` e
  `{clipboard}`, escolhidos num painel com busca pelo atalho.
- **Colar sozinho** — o primeiro **módulo opcional com permissão**: com a
  Acessibilidade concedida, escolher no histórico ou num snippet cola direto
  no app da frente (o ⌘V usa a tecla certa do layout em uso). O snippet
  devolve depois o que estava copiado antes. Sem a permissão, tudo continua
  só copiando. README e SECURITY.md passam a listar as permissões por módulo
  e o que fica gravado em disco.
- Roteiro dos próximos recursos em [`docs/ROADMAP.md`](docs/ROADMAP.md).

## [1.1.2] — 2026-07-30

### Identidade

- Logo trocada de novo, agora pela **Órbita**: um anel de vidro com quatro
  itens em volta e o apontado ampliado no topo. A da 1.1.1 mantinha a
  composição antiga (bandeja com ladrilhos) e mexia só em margem e gradiente
  — de longe ninguém via diferença, e a 32 px ela virava borrão como meia
  dúzia de utilitários. O anel é a forma que o Docka tem de mais sua e a
  única testada que continua legível no tamanho em que o ícone vive.

## [1.1.1] — 2026-07-30

Sem mudança de comportamento: o app funciona exatamente como a 1.1.0. O que
muda é a cara e a documentação.

### Identidade

- Logo redesenhada: squircle com a margem que o macOS pede (a antiga ia de
  borda a borda), gradiente teal mais profundo com luz no topo, prateleira de
  vidro e a rampa da ampliação — vizinhos translúcidos e o apontado opaco,
  bem acima da prateleira.
- A logo passa a ser **renderizada por código** (`scripts/render_logo.swift`):
  mudar a identidade vira editar números e rodar o script.

### Documentação

- README atualizado para o que o app virou — a versão publicada com a 1.1.0
  ainda descrevia o gerenciador "de três abas" e a bandeja única.
- GIF do topo refeito (o anterior era de antes de tudo) e a Órbita ganhou a
  animação que faltava.
- Seção **"E a rede?"**: o app faz uma conexão de saída desde a 1.1.0 — a
  busca da logo de um site — e a página que fala de confiança não podia
  calar sobre isso. Agora diz qual, quando, para onde e o que acontece sem
  rede.

## [1.1.0] — 2026-07-30

A maior versão desde o início: o Docka deixa de ser só uma bandeja e vira um
conjunto de superfícies de borda — bandejas múltiplas, réguas de brilho e
volume, e a Órbita.

### Órbita (novo)

- Anel de itens em volta do cursor: aponte na DIREÇÃO de um e clique — não é
  preciso acertar o ícone. O miolo é zona morta, então nada nasce selecionado.
- Quatro tipos de item: aplicativo, site, arquivo e pasta — cada um abre do
  jeito próprio.
- Logo do site baixada do próprio site, com prévia na hora ao digitar a URL, e
  botão "Atualizar logo" para site que trocou de identidade.
- Até 8 anéis nomeados; com a órbita aberta, a rolagem do mouse troca de anel.
- Editor visual nos ajustes: o anel desenhado como ele é, com zonas clicáveis,
  reordenação por setas e os quatro botões de adicionar.
- Gatilhos: atalho global, atalho por anel, quina da tela e botão extra do
  mouse (aperte para abrir; segure, aponte e solte para lançar de uma vez).

### Bandeja

- Várias bandejas, também nas laterais da tela, cada uma com posição e apps
  próprios — e um atalho global por bandeja.
- Ampliação com a curva do Dock real: pico no ícone apontado, vizinhos em
  rampa, fileira ancorada no cursor (sem tremor e sem elástico).
- Redimensionar arrastando o vidro, como no Dock — com o cursor certo.
- Balão de nome com rabinho, bolinha de execução no lugar exato e quique ao
  lançar.
- "Encerrar" no clique-direito de app aberto.
- A engrenagem saiu; as configurações abrem pela barra de menus, pelo
  clique-direito ou pelo atalho.

### Controles de borda (novo)

- Régua de brilho numa lateral: arrasto suavizado, tique por degrau, nível
  lido da tela de verdade (DisplayServices) — e agindo na tela sob o cursor,
  não sempre na principal.
- Régua de volume (CoreAudio, API pública): mesmo desenho, ícone que acompanha
  o nível como no menu de som; o toque no botão alterna o mudo.
- Os dois convivem na mesma lateral sem se cobrir.

### Gerenciador

- Reescrito no formato dos Ajustes do Sistema: barra lateral com busca,
  navegação com histórico, seções agrupadas.
- Aparência configurável: Tom (claro/escuro/automático) e material do painel
  com prévia simulada, no formato do controle Liquid Glass.
- Aba de Atalhos com uma combinação por ação — bandejas, brilho, volume,
  órbita, anéis e ajustes — com conflito apontado pelo nome.

### Notas

- **Rede:** a única conexão de saída é buscar a logo de um site que VOCÊ
  adicionou, direto naquele site — nunca em serviço de terceiros. Fora isso,
  zero rede, como sempre.
- **Permissões:** continua sem pedir nenhuma.

## [1.0.0] — 2026-07-07

- Primeira versão: bandeja única na borda inferior, revelada pelo cursor, com
  apps fixados, indicador de execução, atalho global ⇧⌘D e gerenciador.
