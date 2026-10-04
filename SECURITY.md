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
- **Contadores do sistema** para o monitor (CPU, memória, rede, bateria, disco)
  e a **tabela de gama** das telas para o escurecimento — APIs públicas, sem permissão

### O que o Docka NÃO faz
- ❌ O núcleo não pede permissão de Acessibilidade, Monitoramento de Entrada ou
  Gravação de Tela. Permissões só existem em **módulos opcionais**, desligados
  por padrão e pedidos apenas quando você os liga:

  | Módulo | Permissão | Para quê, e só isso |
  |---|---|---|
  | Colar sozinho | Acessibilidade | Enviar um ⌘V ao app da frente depois que você escolhe um item do histórico ou um snippet |
  | Alternador — mostrar cada janela | Acessibilidade | Listar as janelas abertas pelo título e trazer a escolhida para a frente |
  | Alternador — prévias | Gravação de Tela | Capturar miniaturas das janelas só enquanto o alternador está aberto; ficam na memória e somem ao fechar |
  | Captura | Gravação de Tela | Capturar a área que você seleciona (pelo seletor do próprio macOS) para copiar o texto, ler um QR ou salvar a imagem. O reconhecimento roda no Mac, pelo Vision; nada é enviado |
  | Ajustes do mouse | Acessibilidade | Interceptar rolagem e botões extras do mouse (nunca o teclado) para inverter, deixar linear, suavizar e voltar/avançar |
  | Encaixar janelas | Acessibilidade | Ler e mudar posição e tamanho da janela da frente quando você usa um atalho ou o menu Janelas |

- ❌ Não captura teclado (o atalho ⌘⇧D usa `RegisterEventHotKey`, que entrega apenas aquele atalho)
- ⚠️ Acessa a rede em UM caso só: ao adicionar um site à órbita, busca o ícone
  (apple-touch-icon/favicon) **no próprio site digitado** — nunca em resolvedor de
  terceiros, que receberia sua lista de sites. Sessão efêmera (sem cookies),
  resposta limitada a 1 MB, resultado em cache local; sem rede, o anel usa um
  globo desenhado localmente. Fora isso: nenhuma conexão de saída, telemetria
  ou atualização automática
- ❌ Não lê conteúdo de arquivos do usuário (arrastar-e-soltar apenas repassa URLs ao app de destino via `NSWorkspace`)
- ❌ Não roda com privilégios elevados nem instala helpers/daemons

### Áreas de interesse para pesquisadores
- Manuseio de URLs no arrastar-e-soltar (`.dropDestination`) — injeção de caminhos maliciosos
- Persistência de caminhos em `UserDefaults` — apontar itens fixados para binários inesperados
- O painel `NSPanel` em `level: .mainMenu` — sobreposição/spoofing de interface de outros apps
- O histórico da área de transferência — vazamento de conteúdo sigiloso que não use as marcas de nspasteboard.org
- O ⌘V sintético do "Colar sozinho" — colar no app errado se o foco mudar no intervalo de ~0,1 s

## Verificação de integridade das releases

Os DMGs publicados nas releases têm assinatura ad-hoc (sem notarização, por ora).
Para verificar que o app não foi adulterado após o download:

```bash
codesign -dv --verbose=2 /Applications/Docka.app   # confere a assinatura
shasum -a 256 Docka-<versão>.dmg                    # compare com o hash da release
```

A partir do momento em que houver assinatura Developer ID e notarização, esta
seção será atualizada com o Team ID esperado.
