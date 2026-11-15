# 7z-context

Menu de contexto do **7-Zip** para exploradores de arquivos no Linux: botão direito → *7-Zip* → compactar, extrair, testar, listar. Bash puro, sem dependências além do próprio 7-Zip.

## Funcionalidades

- **Compactar** a seleção para `7z`, `zip`, `tar`, `tar.gz`, `tar.xz`, `tar.bz2`, ou **Adicionar ao arquivo…** (diálogo: formato, nível, nome, senha, criptografar nomes, dividir em volumes).
- **Extrair aqui** e **Extrair para pasta** (`nome/`), sem sobrescrever nada (conflitos viram `nome (1)`; configurável).
- **Testar** integridade e **Listar** conteúdo.
- Senha pedida por diálogo (3 tentativas), progresso com botão **Cancelar** (remove o arquivo parcial) e notificação ao terminar.
- Multivolume (`.7z.001`), tarballs (`.tar.gz` extrai em um passo) e nomes difíceis (espaços, acentos, aspas, `*`, `-`, quebras de linha).
- Idiomas: English e pt-BR (automático pelo `LANG`).

## Requisitos

- Bash 4+, 7-Zip (`7zz`, `7z` ou `7za`).
- Para diálogos: `kdialog`, `zenity` ou `yad` (ao menos um; sem nenhum, só notificações via `notify-send`).
- `python3` (apenas para o merge do `uca.xml` do Thunar).

## Instalação

```sh
git clone <este repositório> && cd 7zip-linux-context-menu
./install.sh install            # detecta os exploradores instalados
./install.sh install --fm all   # força todos
./install.sh install --fm dolphin,thunar --lang pt_BR --restart
./install.sh install --dry-run  # só mostra o que faria
```

Opções: `--fm auto|all|dolphin,nautilus,nemo,thunar,caja,pcmanfm`, `--prefix DIR` (padrão `~/.local`; o helper vai em `PREFIX/bin`), `--lang en|pt_BR`, `--restart` (reinicia o explorador), `--nautilus-mode auto|scripts|python`.

Tudo é instalado no diretório do usuário; nada precisa de root. O instalador grava um manifesto (`~/.local/share/7z-context/manifest`) e é idempotente.

```sh
./install.sh status    # o que está instalado e se algum arquivo sumiu
./install.sh doctor    # diagnóstico: 7-Zip, diálogos, exploradores, PATH
./install.sh uninstall           # remove exatamente o que o manifesto lista
./install.sh uninstall --purge   # também apaga config e log
```

## Integrações

| Explorador | Mecanismo | Local |
|---|---|---|
| Dolphin | ServiceMenu (KF6; KF5 se houver `kf5-config`) | `~/.local/share/kio/servicemenus/` |
| Nautilus | Scripts, ou extensão nautilus-python se disponível | `~/.local/share/nautilus/scripts/7-Zip/` |
| Caja | Scripts | `~/.config/caja/scripts/7-Zip/` |
| Nemo | `.nemo_action` | `~/.local/share/nemo/actions/` |
| Thunar | Ações personalizadas (merge em `uca.xml`, com backup) | `~/.config/Thunar/uca.xml` |
| PCManFM(-Qt) | DES-EMA | `~/.local/share/file-manager/actions/` |

## Configuração

`~/.config/7z-context/config` (`CHAVE=valor`, só chaves da lista; variáveis de ambiente têm precedência):

| Chave | Valores | Padrão |
|---|---|---|
| `CTX7Z_BIN` | caminho do 7-Zip | `7zz`, `7z`, `7za` |
| `CTX7Z_DIALOG` | `kdialog`, `zenity`, `yad`, `notify`, `none` | automático |
| `CTX7Z_OVERWRITE` | `rename`, `skip`, `overwrite` | `rename` |
| `CTX7Z_LEVEL` | `0 1 3 5 7 9` | `5` |
| `CTX7Z_LANG` | `en`, `pt_BR` | pelo `LANG` |

Log em `~/.local/state/7z-context/`. Código de saída do helper: 0 ok, 1 avisos, 2 falha, 3 cancelado, 64 uso inválido.

## Desenvolvimento

```sh
make test    # suíte automatizada (tests/run.sh; aceita filtro: ./tests/run.sh 't_i*')
make lint    # shellcheck -x -S style em todos os scripts
```

A suíte roda tudo em `HOME` temporário, com fixtures geradas na hora (nada binário no git), e usa stubs de `zenity`/`notify-send` para a parte de UI.

## Limitações conhecidas

- **Senha na linha de comando:** o 7-Zip recebe a senha por `-p`, então ela fica visível em `/proc/<pid>/cmdline` durante a operação, para outros processos do mesmo usuário (e root).
- **Prefixo sem `%`:** `--prefix` com `%` no caminho é recusado (ambíguo em `Exec=` de `.desktop`).
- **Ark:** o Ark mantém o próprio menu no Dolphin; o *7-Zip* aparece ao lado, não no lugar.
- **Thunar** só grava o `uca.xml` ao sair: feche-o (ou use `--restart`) para ver o menu.
- **Nemo e PCManFM:** os templates são genéricos (filtro por tipo MIME/extensão); `Extensions=any;dir;` do Nemo não foi verificado em um Nemo real.
- Um explorador pode exigir reiniciar a sessão/aplicativo para reler o menu.

## Verificado × não verificado

- **Verificado (testes automatizados + execução real):** helper completo (compactar, extrair, testar, listar, senhas, cancelamento, multivolume, nomes difíceis, diálogo de compressão em modo headless e via stubs); instalador/desinstalador em todos os exploradores (arquivos gerados e validados por parsers independentes), merge do Thunar, idempotência, `--dry-run`; instalação real no Dolphin.
- **Não verificado:** janelas reais de `zenity` (só stubs); `kdialog`/`yad`/`qdbus` (não instalados); Nautilus, Nemo, Thunar, Caja e PCManFM (não instalados — só arquivos gerados); API real do nautilus-python.

## Licença

MIT — ver `LICENSE`.
