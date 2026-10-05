# Registro de mudanças

Todas as mudanças relevantes do Docka, por versão. O formato segue o espírito
do [Keep a Changelog](https://keepachangelog.com/pt-BR/), em português — como
todo o resto por aqui.

## [Não lançado]

### Novo

- **Sair ao fechar**: os apps escolhidos são encerrados quando a última
  janela deles fecha (só na passagem para zero janelas — um app recém-aberto
  não é encerrado). O Finder e o Dock nunca entram.
- **Proteção do ⌘Q e ⌘W**: segurar até a barra encher, apertar duas vezes
  ou usar ⌥ para confirmar, em todos os apps ou só nos escolhidos. O tap
  intercepta só esses dois atalhos.
- **Botão verde maximiza** na área útil, sem criar outro Espaço; clicar de
  novo volta ao tamanho de antes, e com ⌥ o botão faz o de sempre.
- **Cliques no Dock**: com o app já na frente e janela à vista, clicar no
  ícone dele minimiza as janelas, oculta o app ou passa para a próxima
  janela. Nos outros casos o Dock faz o de sempre.
- Os quatro pedem Acessibilidade e aparecem na lista de Permissões.
- **Busca no alternador**: com ele aberto, digitar filtra pelo nome do app
  ou pelo título da janela (sem ligar para acentos e maiúsculas); ⌫ apaga,
  Esc limpa e ↩ escolhe. Filtros opcionais: só a tela do cursor e esconder
  apps sem janela (pedem Acessibilidade).

### Mudou

- **O ícone da barra de menus abre um painel**, e não mais um menu: abas
  com ícones (Rápido, Sistema, Controles, Utilidades), cartões com
  interruptores e descrições, e Ajustes/Encerrar no rodapé. Rápido traz o
  Manter acordado e as ações rápidas em grade; Sistema mostra CPU, memória
  e rede ao vivo (medindo só com a aba aberta); Controles liga e desliga
  cada recurso, agrupado por área, com quantos estão ligados; Utilidades
  executa as ações com o atalho gravado ao lado.
- **Ajustes reorganizados**: a barra lateral ganha grupos com título
  (Essenciais, Controles de janela, Arquivos, Bordas, Utilidades), ícones
  de linha na cor de destaque, título fixo na janela, o Alternador numa
  seção própria e uma
  seção nova, **Recursos**, com duas abas: **Recursos** (um interruptor por
  recurso, com a permissão que cada um pede) e **Permissões** (cada
  permissão com o estado, para que serve, quais recursos ligados a usam e
  um atalho para os Ajustes do Sistema — e um aviso quando ela foi
  concedida mas nada ligado precisa dela, ou quando algo ligado precisa e
  ela falta).

## [1.3.0] — 2026-10-04

### Novo (experimental)

- **Brilho do painel em monitores externos (DDC/CI)**: monitores que
  entendem DDC ajustam o brilho de verdade, pela régua da borda e pelos
  ajustes de Brilho. O Docka só lê e muda o brilho (código VCP 0x10) — nada
  de entrada, cor ou padrões —, nunca escreve sem antes ler o valor e o
  máximo do próprio monitor, e conversa numa fila própria, mandando só o
  último valor do arrasto. Monitor que não responde (ou adaptador que não
  repassa DDC) segue no escurecimento por software.

  **Experimental:** conferido contra a especificação VESA DDC/CI, mas ainda
  não testado com um monitor externo de verdade. Se o seu monitor não
  responder ou se comportar mal, rode
  `Docka.app/Contents/MacOS/Docka --ddc-selftest` (só lê) e abra uma issue
  com a saída.

## [1.2.0] — 2026-10-04

A maior versão do Docka até aqui: mais de vinte recursos novos inspirados no
[Vorssaint](https://github.com/vorssaint/vorssaint-utils) — reescritos do
zero, porque ele é GPL-3.0 e o Docka é MIT. Todos nascem **desligados**: quem
não liga um recurso não paga nada por ele.

### Permissões

O núcleo — bandejas, órbita, réguas e quase tudo desta versão — continua sem
pedir permissão nenhuma. O que precisa de uma vem como **módulo opcional**:
desligado por padrão, pede a permissão só ao ser ligado e, sem ela, continua
funcionando no modo sem permissão. README e `SECURITY.md` listam cada módulo,
a permissão e para que ela é usada.

| Módulo | Permissão |
|---|---|
| Colar sozinho, encaixar janelas, alternador com janelas, ajustes do mouse | Acessibilidade |
| Texto da tela, captura de área, prévias do alternador | Gravação de Tela |
| Expandir gatilhos digitados | Monitoramento de Entrada + Acessibilidade |

Com o Docka assinado ad-hoc, o macOS pode pedir a permissão de novo depois da
atualização.

### Bordas e lançamento

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
### Sistema e energia

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
### Área de transferência e texto

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
### Janelas, mouse e captura

- **Encaixar janelas** (módulo opcional, Acessibilidade): atalhos e um
  menu "Janelas" na barra para mandar a janela da frente para metades,
  quartos e terços, maximizar, centralizar, levar para a próxima tela
  (mantendo a proporção) e voltar ao tamanho de antes. Repetir o atalho de
  uma metade alterna a largura entre ½, ⅓ e ⅔.
- **Alternador de apps**: num atalho próprio (sugestão ⌥Tab), mostra os
  apps na ordem de uso; segure o modificador, aperte de novo para avançar
  (⇧ volta, setas também) e solte para trocar. Sem permissão: soltar o
  modificador é percebido lendo o estado do teclado. Com Acessibilidade,
  opcionalmente lista cada janela pelo título e traz a escolhida para a
  frente. A ativação passa pelo LaunchServices, que funciona mesmo com a
  ativação cooperativa do macOS 14+.
- **Ajustes do mouse** (módulo opcional, Acessibilidade): inverter a
  rolagem da roda (vertical e horizontal, separadas) sem mexer no
  trackpad, rolagem linear (cada dente vale o mesmo), rolagem suave
  (deslize com desaceleração), rolar de lado segurando ⌥/⌃/⌘ e botões
  laterais como voltar/avançar (⌘[ / ⌘]). O botão usado pela Órbita fica
  com ela. Só eventos do mouse passam pelo Docka.
- **Captura** (módulo opcional): **conta-gotas** sem permissão, copiando
  em HEX, RGB, HSL ou SwiftUI; **texto da tela** com leitor de QR, que
  reconhece português e inglês no próprio Mac (Vision); e **captura de
  área** para a área de transferência ou a Mesa. A seleção é a do próprio
  macOS (a do ⇧⌘4). Texto e captura pedem Gravação de Tela.
- **Editor de anotação**: a captura de área abre num editor com seta,
  retângulo, caneta, marca-texto, texto, borrão e recorte (uma tecla por
  ferramenta), cores, espessura e ⌘Z; depois copia ou salva. As marcas
  são gravadas em pixels da captura, então a exportação sai na resolução
  Retina. O borrão pixeliza os pixels de verdade — conferido por OCR: o
  texto sob ele não pode mais ser lido.
- **Prévias no alternador** (Gravação de Tela): uma miniatura de cada
  janela no lugar do ícone, pelo ScreenCaptureKit. O alternador abre na
  hora com os ícones e as miniaturas chegam em seguida; no modo de
  janelas, cada janela casa com a sua miniatura pela posição na tela, não
  pelo título.
### Também nesta versão

- **Encaixar arrastando até a borda**, com prévia: laterais dão metades,
  cantos dão quartos e o topo maximiza.
- **Expandir gatilhos digitados** (módulo com Monitoramento de Entrada +
  Acessibilidade): digitar o gatilho de um snippet troca ele pelo texto.
  Guarda só os últimos 32 caracteres, na memória; campos de senha nunca
  chegam. Um gatilho não pode ser o começo de outro.
- **Apagar a área de transferência ao travar a tela ou dormir.**
- **Apps a ignorar** nos ajustes do mouse.

### Documentação

- Roteiro dos recursos em [`docs/ROADMAP.md`](docs/ROADMAP.md).
- `CONTRIBUTING.md`: a regra "zero permissões" vira "núcleo sem permissões;
  módulos opcionais pedem só quando ligados".
- `SECURITY.md`: permissões por módulo e o que fica gravado em disco (notas,
  snippets e, opcionalmente, o histórico — JSON sem criptografia em
  Application Support).

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
