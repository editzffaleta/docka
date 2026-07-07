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

### O que o Docka NÃO faz
- ❌ Não pede permissão de Acessibilidade, Monitoramento de Entrada ou Gravação de Tela
- ❌ Não captura teclado (o atalho ⌘⇧D usa `RegisterEventHotKey`, que entrega apenas aquele atalho)
- ❌ Não acessa a rede — nenhuma conexão de saída, telemetria ou atualização automática
- ❌ Não lê conteúdo de arquivos do usuário (arrastar-e-soltar apenas repassa URLs ao app de destino via `NSWorkspace`)
- ❌ Não roda com privilégios elevados nem instala helpers/daemons

### Áreas de interesse para pesquisadores
- Manuseio de URLs no arrastar-e-soltar (`.dropDestination`) — injeção de caminhos maliciosos
- Persistência de caminhos em `UserDefaults` — apontar itens fixados para binários inesperados
- O painel `NSPanel` em `level: .mainMenu` — sobreposição/spoofing de interface de outros apps

## Verificação de integridade das releases

Os DMGs publicados nas releases têm assinatura ad-hoc (sem notarização, por ora).
Para verificar que o app não foi adulterado após o download:

```bash
codesign -dv --verbose=2 /Applications/Docka.app   # confere a assinatura
shasum -a 256 Docka-<versão>.dmg                    # compare com o hash da release
```

A partir do momento em que houver assinatura Developer ID e notarização, esta
seção será atualizada com o Team ID esperado.
