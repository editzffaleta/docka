// O "tocando agora" do sistema, para a ilha do Docka.
//
// Esta biblioteca não é carregada pelo Docka: quem a carrega é o /usr/bin/perl
// do sistema. Desde o macOS 15.4, o serviço do "tocando agora" só responde a
// processos da própria Apple — e o perl do sistema é um deles. O Docka roda o
// perl, que carrega esta biblioteca e chama uma das duas funções abaixo.
//
// As duas têm a assinatura de uma função do perl (interpretador e CV) e nunca
// voltam: terminam o processo.

/// Escreve uma linha JSON a cada mudança do que está tocando, até a entrada
/// padrão fechar (o Docka encerrou ou desligou a seção).
void docka_ouvir(void *interpretador, void *cv);

/// Envia o comando de DOCKA_COMANDO (número do MediaRemote) ou, com
/// DOCKA_POSICAO, leva a música para aquele segundo.
void docka_comando(void *interpretador, void *cv);
