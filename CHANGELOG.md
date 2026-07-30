# Registro de mudanças

Todas as mudanças relevantes do Docka, por versão. O formato segue o espírito
do [Keep a Changelog](https://keepachangelog.com/pt-BR/), em português — como
todo o resto por aqui.

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
