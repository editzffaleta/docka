# Registro de mudanças

Todas as mudanças relevantes do Docka, por versão. O formato segue o espírito
do [Keep a Changelog](https://keepachangelog.com/pt-BR/), em português — como
todo o resto por aqui.

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
