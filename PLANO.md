# PLANO — `7z-context`: menu de contexto do 7-Zip para exploradores de arquivos Linux

> Autor: Planejador · 2026-11-15 · Para: @Programador (implementação) e @QA (testes)
> Diretório oficial do projeto: `/home/leonardo/Projetos/7zip-linux-context-menu/`
> Status: pronto para implementar. Não contém a implementação final, só especificação, ordem e critérios de aceite.

---

## 0. Decisões assumidas (padrões explícitos)

| # | Decisão | Motivo |
|---|---------|--------|
| D1 | **Diretório oficial do projeto: `/home/leonardo/Projetos/7zip-linux-context-menu/`** (git init lá; este `PLANO.md` fica na raiz dele). Todo código, templates e testes vivem nesse diretório. | Pedido explícito do usuário. |
| D2 | Tudo em **Bash 4+** + POSIX coreutils. **python3** só é exigido para mesclar o `uca.xml` do Thunar (e para a extensão Nautilus opcional). | Bash está presente em toda distro; mesclar XML com sed não é seguro. |
| D3 | Instalação **por usuário** (`~/.local/...`, `~/.config/...`), sem root. Prefixo configurável com `--prefix`. | Pedido no brief. |
| D4 | Helper instalado em `~/.local/bin/7z-context-helper`, e **todas as integrações chamam o caminho absoluto** (não dependem do `PATH`). | Sessões gráficas (lançadas por display manager) muitas vezes não têm `~/.local/bin` no `PATH`. |
| D5 | Idiomas: **inglês (padrão) + pt_BR**. `Name[pt_BR]=` nos `.desktop`; mensagens do helper escolhidas por `LANG`/`LC_MESSAGES` (`pt*` → pt_BR). | O sistema do usuário está em `pt_BR.UTF-8`. |
| D6 | Política de sobrescrita padrão: **nunca sobrescrever** — renomear automaticamente (`-aou` no 7z, sufixo ` (2)`, ` (3)`… para arquivos/pastas de saída). | Evita perda de dados silenciosa. |
| D7 | Nautilus no MVP usa **Scripts** (submenu *Scripts → 7-Zip*); extensão `nautilus-python` fica como etapa opcional (Passo 11). | Scripts funcionam sem dependências; a extensão depende de pacote extra. |
| D8 | Testes automatizados com **bats-core** se instalado; caso contrário `tests/run.sh` em Bash puro com o mesmo conteúdo. Lint obrigatório com `shellcheck`. | bats é o padrão para Bash; fallback evita bloqueio. |
| D9 | Licença MIT, nome do projeto `7z-context`. | Padrão razoável; trocar se o usuário quiser. |

Ambiente real da máquina do usuário (verificado em 2026-11-15): `7z` = **7-Zip 26.06 oficial** (pacote `7zip`, também fornece `7za`), `zenity` e `notify-send` instalados, **sem** `kdialog`/`yad`; **Dolphin 26.08 / KIO 6.31 (KF6)**; sessão **Hyprland**. Os demais exploradores **não** estão instalados → só o Dolphin pode ser testado de ponta a ponta localmente (ver §9).

---

## 1. Visão geral da arquitetura

```
 Explorador (Dolphin/Nautilus/Nemo/Thunar/Caja/PCManFM)
        │  clique direito → item do menu "7-Zip"
        ▼
 arquivo de integração (gerado pelo instalador, específico de cada explorador)
        │  exec "<abs>/7z-context-helper" <ação> [opções] <arquivos...>
        ▼
 7z-context-helper  (único lugar com lógica)
   ├─ detecta binário: 7zz → 7z → 7za  (ou $CTX7Z_BIN)
   ├─ detecta UI: kdialog → zenity → yad → notify-send → stderr  (ou $CTX7Z_DIALOG)
   ├─ normaliza caminhos (relativos, espaços, unicode, '-' inicial, '*', '?')
   ├─ executa 7z com progresso, cancelamento, senha, renomeação de saída
   └─ mostra resultado + grava log
```

Regra de ouro: **arquivos de integração não têm lógica** — só mapeiam item de menu → `helper <ação> %F`. Toda correção acontece no helper.

### Estrutura do repositório

```
/home/leonardo/Projetos/7zip-linux-context-menu/
├── PLANO.md                         # este plano
├── bin/7z-context-helper            # script central (executável)
├── install.sh                       # instalador/desinstalador/diagnóstico
├── templates/
│   ├── dolphin/7z-context.desktop.in           # ServiceMenu "todos os arquivos/pastas"
│   ├── dolphin/7z-context-archives.desktop.in  # ServiceMenu só para arquivos compactados
│   ├── nemo/7zctx-*.nemo_action.in
│   ├── thunar/uca-actions.xml.in               # fragmento a mesclar
│   ├── scripts/shim.sh.in                      # shim usado por Nautilus e Caja
│   ├── desema/7zctx-menu.desktop.in            # Type=Menu (PCManFM/PCManFM-Qt)
│   ├── desema/7zctx-*.desktop.in               # Type=Action
│   └── nautilus-python/7z_context.py.in        # opcional (Passo 11)
├── share/mimetypes.list             # lista única de MIME types de arquivos compactados
├── share/extensions.list            # lista única de extensões (*.7z, *.zip, …)
├── tests/
│   ├── helper.bats  install.bats  (ou run.sh)
│   └── fixtures/make_fixtures.sh    # gera fixtures em tempo de teste (nada binário no git)
├── README.md
└── LICENSE
```

`share/mimetypes.list` e `share/extensions.list` são a **fonte única** para todas as integrações e para o helper (o instalador copia para `~/.local/share/7z-context/`).

---

## 2. Itens de menu (contrato funcional)

Submenu **"7-Zip"** com os itens abaixo. "Visível em" diz quando o item aparece nos exploradores que permitem filtrar por tipo (Dolphin, Nemo, Thunar, PCManFM). Nautilus/Caja (scripts) não filtram → o helper valida e mostra erro amigável.

| ID da ação | Rótulo EN | Rótulo pt_BR | Visível em | Comando |
|---|---|---|---|---|
| `compress-dialog` | Add to archive… | Adicionar ao arquivo… | qualquer arquivo/pasta | `helper compress-dialog %F` |
| `compress-7z` | Compress to .7z | Compactar em .7z | qualquer | `helper compress 7z %F` |
| `compress-zip` | Compress to .zip | Compactar em .zip | qualquer | `helper compress zip %F` |
| `compress-targz` | Compress to .tar.gz | Compactar em .tar.gz | qualquer | `helper compress tar.gz %F` |
| `extract-here` | Extract here | Extrair aqui | só compactados | `helper extract-here %F` |
| `extract-to` | Extract to folder | Extrair para pasta própria | só compactados | `helper extract-to %F` |
| `test` | Test archive | Testar arquivo | só compactados | `helper test %F` |
| `list` | List contents | Listar conteúdo | só compactados | `helper list %F` |

Ícones (tema freedesktop, com fallback natural do tema): `archive-insert` (compactar), `archive-extract` (extrair), `dialog-ok`/`checkmark` (testar), `view-list-text` (listar). Ícone do submenu: `package-x-generic`.

---

## 3. Especificação do helper `bin/7z-context-helper`

### 3.1 Interface CLI

```
7z-context-helper compress <7z|zip|tar|tar.gz|tar.xz|tar.bz2> [--level N] [--name NOME] -- ARQUIVOS...
7z-context-helper compress-dialog ARQUIVOS...
7z-context-helper extract-here ARQUIVOS...
7z-context-helper extract-to   ARQUIVOS...
7z-context-helper test         ARQUIVOS...
7z-context-helper list         ARQUIVOS...
7z-context-helper doctor        # mostra binário/UI detectados, versões, caminhos de log
7z-context-helper --version | --help
```
Saída do processo: `0` tudo OK; `1` algum item com aviso; `2` algum item falhou; `3` cancelado pelo usuário; `64` uso inválido.

### 3.2 Configuração (sem `source`!)

Ordem de prioridade: variável de ambiente > `~/.config/7z-context/config` > padrão. O config é lido linha a linha como `CHAVE=valor`, **só chaves da whitelist**, nunca executado com `source`/`eval`.

| Chave | Valores | Padrão |
|---|---|---|
| `CTX7Z_BIN` | caminho do binário | autodetectar |
| `CTX7Z_DIALOG` | `kdialog` `zenity` `yad` `notify` `none` | autodetectar |
| `CTX7Z_OVERWRITE` | `rename` `skip` `overwrite` | `rename` |
| `CTX7Z_LEVEL` | `0 1 3 5 7 9` | `5` |
| `CTX7Z_LANG` | `en` `pt_BR` | por `LANG` |

`CTX7Z_DIALOG=none` = **modo headless**: nenhuma janela, mensagens em stderr, senha via `CTX7Z_PASSWORD` (só para testes). É o modo usado pelos testes automatizados.

### 3.3 Detecção do binário
1. `$CTX7Z_BIN` se definido e executável (senão erro claro).
2. `7zz` (7-Zip oficial), depois `7z`, depois `7za`.
3. Se for `7za`, marcar "formatos limitados" (sem RAR etc.) — erros de "Unsupported archive" devem sugerir instalar `7zip`/`p7zip-full`.
4. Nenhum → diálogo de erro: "7-Zip não encontrado. Instale o pacote 7zip (Arch: `7zip`, Debian/Ubuntu: `7zip` ou `p7zip-full`, Fedora: `7zip` ou `p7zip-plugins`)".

### 3.4 Detecção da UI
1. `$CTX7Z_DIALOG` se definido.
2. Se `XDG_CURRENT_DESKTOP` contém `KDE` e existe `kdialog` → `kdialog`.
3. Senão primeiro disponível: `zenity` → `yad` → `kdialog`.
4. Senão `notify-send` (só notificações; operações que exigem entrada — senha, diálogo de compactação — falham com notificação explicando que é preciso zenity/kdialog/yad).
5. Sem nada disso, ou sem `DISPLAY`/`WAYLAND_DISPLAY` → `none` (stderr + log).

Camada de UI = funções com a mesma assinatura para cada backend:
`ui_info`, `ui_warn`, `ui_error`, `ui_question` (sim/não), `ui_entry` (texto com valor padrão), `ui_password`, `ui_choice` (lista), `ui_compress_form`, `ui_progress_start/update/finish`, `ui_text` (texto longo/rolável), `ui_notify`.

Observações por backend:
- **zenity/yad**: `--progress --percentage=0 --auto-close` lendo números pelo stdin; `--text-info --filename=` para listagem; `--forms` (zenity) / `--form` (yad) para o diálogo de compactação.
- **kdialog**: progresso via `kdialog --progressbar` + `qdbus`/`qdbus6` (`Set "" value N`, `wasCancelled`). Se não houver `qdbus*`, usar notificação de início/fim (sem barra). Formulário = sequência de diálogos (`--combobox`, `--inputbox`, `--password`). Listagem: `--textbox ARQUIVO_TEMP`.
- **notify-send**: `notify-send -a 7-Zip -i <ícone> "título" "corpo"`; no fim sempre uma notificação de resumo.

### 3.5 Normalização de entradas (crítico)
Para cada argumento:
1. Se não começar com `/`, prefixar `"$PWD/"` (scripts do Nautilus/Caja passam nomes relativos ao diretório atual).
2. Aceitar `file://` (decodificar `%XX`) por robustez; rejeitar outros esquemas (`smb://`, `sftp://`, `trash://`, `recent://`) com mensagem "local apenas".
3. Rejeitar o que não existe (`[ -e ]`), reportar no resumo e seguir com os demais.
4. Deduplicar.
5. **Nunca** usar `for f in $*`, `eval`, `sh -c "… $f …"` ou `xargs` sem `-0`. Sempre arrays Bash e `"${arr[@]}"`.
6. Em **todas** as chamadas ao 7z: `-spd` (desliga curingas — nomes com `*`/`?` não podem expandir), `--` antes de nomes de arquivo, `-y` só onde a política de sobrescrita for decidida explicitamente.

Nomes que DEVEM funcionar: espaços, acentos/emoji, `'`, `"`, `$`, `` ` ``, `\`, `*`, `?`, `[`, nome começando com `-`, nome com quebra de linha (exceto via variável de ambiente do Nautilus — ver riscos).

### 3.6 Operação `compress`
- **Nome de saída**: 1 item → `<basename>.<ext>` (pasta `Fotos` → `Fotos.7z`; arquivo `a.txt` → `a.7z`, removendo só a última extensão; arquivo oculto `.bashrc` → `.bashrc.7z`). Vários itens → `<nome da pasta pai>.<ext>`; se a pasta pai for `/` → `Archive.<ext>`.
- **Destino**: diretório do primeiro item. Se não for gravável → erro claro (não tentar outro lugar no MVP).
- **Colisão**: se o arquivo de saída existir → sufixo `Nome (2).7z`, `Nome (3).7z`… (função única `unique_path`, reusada em extract-to).
- **Caminhos dentro do arquivo**: passar caminhos absolutos ao 7z; ele armazena relativo ao pai de cada item (`/a/b/Fotos` → `Fotos/...`). Não usar `-spf`. Itens de diretórios diferentes com o mesmo basename → avisar que haverá conflito no arquivo (7z aceita, mas extração duplicará nomes) — aceitável no MVP, só documentar.
- **Formatos**:
  - `7z`: `7z a -t7z -mx=$LEVEL -spd -bsp1 -bso0 -bse2 -- SAIDA ITENS…`
  - `zip`: `-tzip` (com `-mcu=on` para nomes UTF-8).
  - `tar`: `-ttar`.
  - `tar.gz|tar.xz|tar.bz2`: **pipeline em dois estágios** — `7z a -ttar -so -an -spd -- ITENS… | 7z a -t{gzip|xz|bzip2} -si"<nome>.tar" -mx=$LEVEL -- SAIDA`. Verificar `PIPESTATUS` dos dois lados. Progresso: barra pulsante (tamanho total desconhecido no estágio 2). Fallback se o pipeline falhar por limitação de versão: `tar -C … -czf/-cJf/-cjf` com `--` e caminhos relativos via `-C "$dir" "$base"`.
- Arquivo parcial em caso de erro/cancelamento → **apagar** a saída incompleta.

### 3.7 Diálogo `compress-dialog`
Campos (com padrão): Nome do arquivo (nome calculado em 3.6, editável) · Formato (`7z`, `zip`, `tar`, `tar.gz`, `tar.xz`, `tar.bz2`) · Nível (`0 Armazenar`, `1 Mais rápido`, `5 Normal`, `7 Máximo`, `9 Ultra`) · Senha (opcional; só 7z/zip) · "Criptografar nomes de arquivo" (só 7z → `-mhe=on`) · Dividir em volumes (opcional, ex.: `100m` → `-v100m`; validar `^[0-9]+[kmg]?$`).
Validações: nome não vazio, sem `/`; senha com formato tar.* → avisar e ignorar ou bloquear (escolher bloquear com mensagem); se a extensão digitada não bater com o formato, acrescentar a extensão certa. Cancelar → sair com 3, sem efeito colateral.

### 3.8 Operação `extract-here`
- Para cada arquivo compactado: `7z x -spd -aou -o"<dir do arquivo>" -bsp1 -- ARQUIVO` (`-aou` = renomear em conflito, conforme D6; `skip` → `-aos`; `overwrite` → `-aoa`).
- **Tarballs comprimidos** (`.tar.gz .tgz .tar.xz .txz .tar.bz2 .tbz .tbz2 .tar.zst .tzst .tar.lz .tar.lzma`): 7z extrairia só o `.tar`. Fazer em dois estágios: `7z x -so -- ARQ | 7z x -si -ttar -aou -o"$dest"`; verificar ambos os status; fallback `tar -xf ARQ -C "$dest"` (GNU tar autodetecta compressão) se o 7z não suportar (ex.: zstd em versões antigas).
- **Multivolume**: aceitar só o primeiro volume (`.7z.001`, `.zip.001`, `.part1.rar`/`.part01.rar`, `.z01`+`.zip` → usar o `.zip`); se o usuário selecionou vários volumes do mesmo conjunto, processar o conjunto **uma vez** (agrupar por nome-base).
- Arquivo que não é compactado (extensão desconhecida **e** `7z l` falha) → item no resumo "não é um arquivo compactado suportado", segue para o próximo.

### 3.9 Operação `extract-to`
- Pasta de destino = `<dir>/<nome sem extensão de arquivo compactado>`: remover extensões compostas conhecidas da lista (`.tar.gz`, `.tar.xz`, `.7z.001`, `.part1.rar`…); `Backup 2024.tar.gz` → `Backup 2024/`.
- Se a pasta existir → `unique_path` (`Backup 2024 (2)/`). Nunca extrair dentro de pasta já existente.
- Criar a pasta, extrair como em 3.8 com `-o"$pasta"`. Em erro fatal/cancelamento com pasta vazia ou criada por nós → remover a pasta criada (só se nós a criamos).
- (Fora do MVP, documentar como ideia: "extração inteligente" que evita pasta dupla quando o arquivo já tem uma única raiz — 7z tem `-spe`.)

### 3.10 Operações `test` e `list`
- `test`: `7z t -spd -bsp1 -- ARQ`; resultado OK/ERRO por arquivo; resumo final "3 OK, 1 com erro" + detalhes do erro (últimas ~20 linhas do stderr).
- `list`: `7z l -spd -- ARQ` → texto em `ui_text` (um bloco por arquivo, com cabeçalho). Para tarball comprimido, listar o `.tar` interno via pipeline (`7z x -so … | 7z l -si -ttar`).

### 3.11 Senhas
- **Detecção antes de extrair/testar/listar**: `7z l -slt -spd -p"$SENTINELA" -- ARQ </dev/null` (sentinela fixa e improvável, ex.: `__7zctx_probe__`; arquivos sem criptografia ignoram `-p`).
  - Saída contém `Can not open encrypted archive` / `Wrong password` → cabeçalho criptografado → pedir senha.
  - Saída contém linha `Encrypted = +` → conteúdo criptografado → pedir senha.
- Pedir com `ui_password` ("Senha para <nome>"); até **3 tentativas**; validar a senha com `7z t` só se o arquivo for pequeno (<50 MB), senão tentar a extração direto e tratar "Wrong password" (limpando o que tiver sido extraído na pasta criada).
- **Sempre** redirecionar stdin de `/dev/null` para o 7z → ele nunca pode ficar travado esperando senha num terminal invisível.
- Nunca gravar a senha no log; mascarar `-p…` ao registrar comandos.
- Risco aceito e documentado: a senha aparece em `/proc/<pid>/cmdline` durante a execução (limitação do 7z CLI).

### 3.12 Progresso e cancelamento
- 7z com `-bsp1 -bso0 -bse2` (progresso no stdout, sem listagem, erros no stderr). O progresso usa `\b`/`\r`: converter com `tr '\b\r' '\n\n'` e extrair `^ *([0-9]{1,3})%` com `grep --line-buffered`/`sed -u` → alimentar `ui_progress_update`.
- Vários arquivos: barra global = `(i-1 + pct/100) / N`, texto "Extraindo 2 de 5: nome".
- Cancelamento (zenity/yad: diálogo de progresso fecha com código ≠ 0; kdialog: `wasCancelled`): matar o 7z (`kill` no PID, depois `wait`), apagar saída parcial (3.6/3.9), resumo "Cancelado", sair com 3.
- Operações muito rápidas (<1 s) não devem "piscar" janela de progresso: abrir a barra só após ~700 ms (ou aceitar o piscar no MVP — **escolha: aceitar no MVP**, `--auto-close` resolve o essencial).

### 3.13 Resultado, log e erros
- Final de toda operação: notificação de resumo (sempre que houver notify-send) e, se houve erro, `ui_error` com detalhes.
- Log em `${XDG_STATE_HOME:-~/.local/state}/7z-context/helper.log` (rotacionar: se >1 MB, mover para `.1`). Cada linha: data, ação, arquivo, código do 7z, duração.
- Mapear códigos do 7z: `0` OK · `1` aviso (ex.: arquivo bloqueado) · `2` erro fatal · `7` linha de comando · `8` memória · `255` interrompido.
- Erros comuns traduzidos: "No space left on device", "Permission denied", "Unsupported archive type"/"Can not open the file as archive", "Wrong password", "Data Error"/"CRC Failed".

---

## 4. Integrações por explorador

Todas geradas a partir de `templates/*.in` pelo instalador, substituindo `@HELPER@` pelo caminho absoluto **já escapado** para o formato de cada arquivo, e `@MIMETYPES@`/`@PATTERNS@` a partir de `share/*.list`. Todo arquivo gerado tem prefixo `7zctx` (ou marcador `7zctx-` no ID) para desinstalar sem tocar no resto.

### 4.1 KDE Dolphin (ServiceMenus)
- Destino KF6 (e KF5 ≥ 5.85): `~/.local/share/kio/servicemenus/`. Só se `kf5-config`/Dolphin KF5 antigo for detectado, também `~/.local/share/kservices5/ServiceMenus/`.
- **Os arquivos precisam ser executáveis** (`chmod +x`) — KIO ignora service menus de usuário não executáveis.
- Dois arquivos, ambos com `X-KDE-Submenu=7-Zip` (o Dolphin funde submenus de mesmo nome):
  - `7z-context.desktop`: `MimeType=all/allfiles;inode/directory;` → ações de compactar.
  - `7z-context-archives.desktop`: `MimeType=<lista de share/mimetypes.list>` → extrair/testar/listar.
- Esqueleto:
  ```ini
  [Desktop Entry]
  Type=Service
  X-KDE-ServiceTypes=KonqPopupMenu/Plugin
  MimeType=all/allfiles;inode/directory;
  Actions=compressDialog;compress7z;compressZip;compressTarGz;
  X-KDE-Submenu=7-Zip
  X-KDE-Priority=TopLevel
  Icon=package-x-generic

  [Desktop Action compress7z]
  Name=Compress to .7z
  Name[pt_BR]=Compactar em .7z
  Icon=archive-insert
  Exec=@HELPER_DESKTOP_QUOTED@ compress 7z %F
  ```
- Escape do `Exec` conforme Desktop Entry Spec: se o caminho tiver espaço ou caractere reservado, envolver em aspas duplas e escapar `"` `` ` `` `$` `\`.
- Depois de instalar: `kbuildsycoca6` (ou `kbuildsycoca5`) se existir; não é obrigatório no KF6.
- Validar com `desktop-file-validate` (aceitar avisos sobre chaves `X-KDE-*`).
- Atenção: o **Ark** já instala um submenu "Extrair" próprio; o nosso fica separado sob "7-Zip" — documentar, não remover nada do Ark.

### 4.2 GNOME Files / Nautilus (Scripts)
- Destino: `~/.local/share/nautilus/scripts/7-Zip/` — o nome do **arquivo** é o rótulo do menu; subpasta vira submenu ("Scripts → 7-Zip → …").
- Um shim executável por ação (rótulo no idioma detectado na instalação; `--lang` no instalador força):
  ```sh
  #!/bin/sh
  # 7zctx-generated
  exec '@HELPER_SH_QUOTED@' extract-here "$@"
  ```
  O helper resolve nomes relativos com `$PWD` (Nautilus executa o script no diretório atual).
- **Não usar** `NAUTILUS_SCRIPT_SELECTED_FILE_PATHS` (separado por `\n`, quebra com nomes que contêm quebra de linha). Usar só `"$@"`.
- Locais remotos (sftp/smb) não passam argumentos úteis → helper reporta "local apenas" (aceitável).
- Prefixo numérico para ordenar? Nautilus ordena por nome; usar rótulos naturais e aceitar ordem alfabética no MVP.

### 4.3 Cinnamon Nemo (`.nemo_action`)
- Destino: `~/.local/share/nemo/actions/7zctx-<acao>.nemo_action` (Nemo recarrega sozinho).
- Esqueleto:
  ```ini
  [Nemo Action]
  Name=Extract here
  Name[pt_BR]=Extrair aqui
  Comment=Extract with 7-Zip
  Exec=@HELPER_NEMO@ extract-here %F
  Icon-Name=archive-extract
  Selection=notnone
  Mimetypes=@MIMETYPES@        # só nas ações de arquivo compactado
  Extensions=any;               # nas ações de compactar (inclui pastas: usar Extensions=any; e testar dir)
  Quote=double
  ```
  `Quote=double` faz o Nemo citar cada `%F`. Testar explicitamente seleção de **pastas** (em algumas versões é preciso `Extensions=any;` + `Selection=notnone`; se pasta não aparecer, adicionar `Mimetypes=inode/directory;` numa ação duplicada — QA confirma).
- Submenu: Nemo ≥ 6 tem layout de ações em `~/.config/nemo/actions-tree.json`. **Não** sobrescrever esse arquivo no MVP (formato varia entre versões); usar rótulos com prefixo `7-Zip: ` para agrupar visualmente. Submenu real via JSON fica opcional, só se o arquivo não existir.

### 4.4 XFCE Thunar (`uca.xml`)
- Arquivo: `~/.config/Thunar/uca.xml` (pode já ter ações do usuário — **mesclar, nunca substituir**).
- Mescla via `python3` (`xml.etree.ElementTree`): backup `uca.xml.7zctx.bak` (só se não existir backup anterior), remover `<action>` cujo `<unique-id>` começa com `7zctx-`, inserir as novas, gravar atomicamente (arquivo temporário + `mv`). Se o arquivo não existir, criar `<?xml version="1.0" encoding="UTF-8"?><actions/>`. XML inválido → abortar só a integração Thunar com mensagem, sem tocar no arquivo.
- O Thunar regrava o `uca.xml` ao sair: o instalador avisa e (com `--restart`) roda `thunar -q` antes de mesclar.
- Ação:
  ```xml
  <action>
    <icon>archive-extract</icon>
    <name>Extrair aqui</name>
    <submenu>7-Zip</submenu>                 <!-- Thunar ≥ 4.18; versões antigas ignoram -->
    <unique-id>7zctx-extract-here</unique-id>
    <command>@HELPER_SH_QUOTED@ extract-here %F</command>
    <description>Extrair com 7-Zip</description>
    <range>*</range>
    <patterns>@PATTERNS@</patterns>          <!-- *.7z;*.zip;*.tar.gz;… -->
    <other-files/>
  </action>
  ```
  Ações de compactar: `<patterns>*</patterns>` + `<directories/><audio-files/><image-files/><other-files/><text-files/><video-files/>`.
- Thunar só suporta um idioma por `<name>` → usar o idioma escolhido na instalação.

### 4.5 MATE Caja (Scripts)
- Destino: `~/.config/caja/scripts/7-Zip/` — mesmo shim do Nautilus (4.2). Caja também executa no diretório atual e passa nomes como argumentos.
- Se **caja-actions** estiver instalado, o Caja também lê as ações DES-EMA de 4.6 → itens duplicados. Regra: se detectar `caja-actions` (`command -v caja-actions-config-tool` ou pacote), **não** instalar os scripts do Caja e avisar que as ações DES-EMA servem para ele.

### 4.6 LXDE PCManFM / LXQt PCManFM-Qt (DES-EMA / FileManager-Actions)
- Destino: `~/.local/share/file-manager/actions/`.
- Um menu + uma ação por item:
  ```ini
  # 7zctx-menu.desktop
  [Desktop Entry]
  Type=Menu
  Name=7-Zip
  Icon=package-x-generic
  ItemsList=7zctx-compress-dialog;7zctx-compress-7z;7zctx-compress-zip;7zctx-compress-targz;7zctx-extract-here;7zctx-extract-to;7zctx-test;7zctx-list;

  # 7zctx-extract-here.desktop
  [Desktop Entry]
  Type=Action
  Name=Extract here
  Name[pt_BR]=Extrair aqui
  Icon=archive-extract
  Profiles=main;

  [X-Action-Profile main]
  MimeTypes=@MIMETYPES@
  SelectionCount=>0
  Exec=@HELPER_DESKTOP_QUOTED@ extract-here %F
  ```
  Ações de compactar: `MimeTypes=all/all;`. Os IDs em `ItemsList` são os nomes dos arquivos sem `.desktop`.
- Esse mesmo diretório é lido por FileManager-Actions (Nautilus antigo) e caja-actions — ver 4.5.

---

## 5. Instalador `install.sh`

### 5.1 CLI
```
./install.sh install   [--fm auto|all|dolphin,nautilus,nemo,thunar,caja,pcmanfm] [--prefix DIR] [--lang en|pt_BR] [--restart] [--dry-run]
./install.sh uninstall [--purge] [--dry-run]     # --purge também apaga config e log
./install.sh status                               # o que está instalado, versões, exploradores detectados
./install.sh doctor                               # = status + helper doctor + checagens (PATH, exec bit, xml válido)
```
Padrão: `install --fm auto` = instalar para cada explorador **detectado** (`command -v dolphin nautilus nemo thunar caja pcmanfm pcmanfm-qt`). `--fm all` instala tudo mesmo sem detectar (útil para quem instala o explorador depois). Recusa rodar como root (a não ser que `--prefix` seja explícito) para não poluir `/root`.

### 5.2 Comportamento
1. Checagens: Bash ≥ 4; 7-Zip presente (se não, **avisa mas instala** — o helper mostra erro amigável depois); `zenity|kdialog|yad` ausentes → aviso; `python3` ausente → pula Thunar com aviso.
2. Copiar `bin/7z-context-helper` → `$PREFIX/bin/` (0755), `share/*.list` → `$PREFIX/share/7z-context/`.
3. Gerar integrações (§4) com escape correto por formato.
4. Gravar **manifesto** `$PREFIX/share/7z-context/manifest` com cada arquivo criado (+ marcação "thunar-merge" para o caso especial). A desinstalação usa o manifesto; se faltar, cai para varredura por prefixo `7zctx`/marcador `# 7zctx-generated` **nos diretórios conhecidos** apenas.
5. Pós-instalação: `kbuildsycoca6/5` se houver; mensagens "reinicie o Nautilus: `nautilus -q`", "Thunar: `thunar -q`".
6. Avisar se `$PREFIX/bin` não está no `PATH` (não bloqueia nada, pois integrações usam caminho absoluto).
7. **Idempotente**: rodar `install` duas vezes = mesmo resultado, sem duplicar ações no `uca.xml`. Reinstalar com outro `--prefix` deve primeiro desinstalar o anterior (ler manifesto antigo).
8. `--dry-run`: imprime cada arquivo que seria criado/alterado/removido, não toca no disco.
9. Desinstalar: remover arquivos do manifesto, remover só `<action>` `7zctx-*` do `uca.xml`, apagar pastas `7-Zip/` de scripts **só se ficarem vazias**, remover helper e `share/7z-context/`. Nunca apagar nada fora do manifesto/marcadores.

---

## 6. Passos de implementação (ordem)

Cada passo termina com `shellcheck` limpo nos scripts tocados e commit próprio.

| Passo | Entrega | Depende de |
|---|---|---|
| 1 | Esqueleto do repo em `/home/leonardo/Projetos/7zip-linux-context-menu/` (`git init`, `.gitignore`), README inicial, `share/mimetypes.list` + `share/extensions.list`, `tests/fixtures/make_fixtures.sh` | — |
| 2 | Helper: parsing de CLI, config whitelist, detecção de binário e UI, `doctor`, log, normalização de caminhos (§3.1–3.5), modo `none` | 1 |
| 3 | Helper: `compress` (7z/zip/tar + tar.gz/xz/bz2 em pipeline), `unique_path`, limpeza de parcial (§3.6) | 2 |
| 4 | Helper: `extract-here`, `extract-to`, tarballs, multivolume, não-arquivos (§3.8–3.9) | 2, 3 (`unique_path`) |
| 5 | Helper: `test`, `list` (§3.10) | 2 |
| 6 | Helper: senhas (§3.11) | 4, 5 |
| 7 | Camada de UI: zenity → yad → kdialog → notify; progresso + cancelamento; resumo (§3.4, 3.12, 3.13) | 3–6 |
| 8 | `compress-dialog` (§3.7) | 3, 7 |
| 9 | Templates das 6 integrações (§4) | 2 (CLI estável) |
| 10 | `install.sh` completo (§5), incluindo mescla do Thunar | 9 |
| 11 | *(Opcional)* extensão `nautilus-python` (API 4.0, `MenuProvider.get_file_items(files)`), instalada só se `libnautilus-python` existir; `--nautilus-mode auto|scripts|python` | 10 |
| 12 | Suíte de testes completa + README final (instalação, uso, desinstalação, limitações) | todos |

---

## 7. Critérios de aceite

### 7.1 Helper (automatizáveis em modo `CTX7Z_DIALOG=none`)
- **H1** `doctor` imprime binário escolhido, versão e UI; com `CTX7Z_BIN=/nao/existe` sai ≠0 com mensagem clara.
- **H2** `compress 7z` de uma pasta `Minha Pasta` gera `Minha Pasta.7z` ao lado; `7z l` mostra `Minha Pasta/...`; rodar de novo gera `Minha Pasta (2).7z`.
- **H3** `compress zip|tar|tar.gz|tar.xz|tar.bz2` com 3 itens gera `<pai>.<ext>`; `tar -tf` (para tar.*) lista os 3 itens; arquivo tar.gz é gzip válido (`gzip -t`).
- **H4** Fixture com nomes: `com espaço.txt`, `ação ✓.txt`, `-começa-com-traço.txt`, `as*te?risco.txt`, `aspas'"$x.txt`, `quebra\nlinha.txt` → compactar e extrair preserva todos os nomes byte a byte (comparar `find -print0 | sort -z`).
- **H5** `extract-here` com destino contendo arquivo de mesmo nome não sobrescreve (aparece cópia renomeada; conteúdo original intacto, checado por hash).
- **H6** `extract-to` de `Backup 2024.tar.gz` cria `Backup 2024/` com o conteúdo (não um `.tar`); se a pasta existir, cria `Backup 2024 (2)/`.
- **H7** Seleção de 3 arquivos compactados + 1 `.txt` comum: os 3 são extraídos, o `.txt` aparece no resumo como não suportado; saída 2.
- **H8** Multivolume `x.7z.001/.002/.003` todos selecionados → extração ocorre **uma vez**.
- **H9** `test` em arquivo íntegro → 0; em arquivo corrompido (bytes alterados no meio) → 2 e mensagem de erro de dados.
- **H10** Arquivo com senha (conteúdo e, separado, com `-mhe=on`): sem `CTX7Z_PASSWORD` → falha limpa, **sem travar** (timeout do teste 20 s); com senha certa → extrai; senha errada → falha e não deixa pasta criada para trás (extract-to).
- **H11** O log nunca contém a senha (grep).
- **H12** Caminho relativo + `PWD` (simula Nautilus): `cd dir && helper extract-here arq.7z` funciona.
- **H13** `shellcheck -x bin/7z-context-helper install.sh` sem avisos (exceções só com `# shellcheck disable=` justificado).

### 7.2 UI (manual com zenity nesta máquina; kdialog/yad em VM ou instalando o pacote)
- **U1** Extrair arquivo de ~500 MB mostra barra de progresso que avança; ao terminar fecha sozinha e aparece notificação de sucesso.
- **U2** Cancelar no meio para o 7z em ≤ 2 s (`pgrep 7z` vazio) e remove saída parcial.
- **U3** Senha: diálogo de senha aparece, 3 tentativas erradas → mensagem e fim.
- **U4** `compress-dialog`: todos os campos com padrão; cancelar não cria nada; formato tar.gz + senha → bloqueado com mensagem.
- **U5** `list` mostra o conteúdo em janela rolável.
- **U6** Sem zenity/kdialog/yad (PATH reduzido) → só notificações; ações que exigem entrada avisam o motivo.

### 7.3 Instalador
- **I1** `HOME=$(mktemp -d) ./install.sh install --fm all` cria exatamente os arquivos do manifesto; ServiceMenus do Dolphin são executáveis; `desktop-file-validate` sem **erros** nos `.desktop` do Dolphin; `xmllint --noout` no `uca.xml`.
- **I2** `uca.xml` pré-existente com 2 ações do usuário → após install continua com elas + as nossas; após uninstall fica idêntico ao original (comparação semântica do XML).
- **I3** `install` duas vezes → nenhum arquivo duplicado, `uca.xml` sem ações repetidas.
- **I4** `uninstall` em HOME temporário → nenhum arquivo `7zctx`/helper restante; arquivos do usuário nas mesmas pastas intactos.
- **I5** `--dry-run` não altera nada (`find $HOME -newer marcador` vazio).
- **I6** `install --fm auto` nesta máquina instala só Dolphin (único explorador presente) e informa os demais como "não detectado".
- **I7** Caminho do prefixo com espaço (`--prefix "$HOME/meu prefixo"`) → integrações ainda executam o helper (Exec corretamente escapado).

### 7.4 Integração real (por explorador)
Para cada explorador: o submenu "7-Zip" aparece em (a) um arquivo comum, (b) uma pasta, (c) seleção múltipla, (d) um `.7z` — com os itens corretos da tabela §2 — e cada item executa a operação certa em um caminho com espaço e acento.

---

## 8. Riscos, casos de borda e mitigação

| Risco / borda | Mitigação |
|---|---|
| Nomes com `*`/`?` expandidos pelo 7z como curinga | `-spd` sempre (verificado: suportado no 7-Zip 26.06 local). |
| Nome começando com `-` lido como switch | `--` antes dos nomes (suportado). |
| 7z trava esperando senha num processo sem terminal | stdin `</dev/null` sempre + detecção prévia (§3.11). |
| `.tar.gz` extraído só até `.tar` | pipeline de dois estágios + fallback `tar` (§3.8). |
| Extração sobrescreve dados | `-aou` e `unique_path` como padrão. |
| Senha visível em `ps` | Limitação do 7z CLI; documentar no README. |
| `PATH` sem `~/.local/bin` na sessão gráfica | caminho absoluto em todas as integrações (D4). |
| Thunar regrava `uca.xml` ao sair, perdendo a mescla | instruir/rodar `thunar -q` antes; `doctor` verifica se nossas ações estão lá. |
| Duplicação Caja (scripts + caja-actions) | detecção e escolha de um só (§4.5). |
| Dolphin ignora service menu sem bit executável | `chmod +x` + verificação em `doctor`. |
| Ark já oferece "Extrair" no Dolphin | coexistência; não alterar o Ark. |
| `all/allfiles` em KF6 | verificado como padrão em KIO; se o QA não vir o menu em arquivos, trocar por `application/octet-stream;` (todos os tipos herdam dele). |
| Nemo: ações de compactar não aparecerem em pastas | QA testa; plano B descrito em §4.3. |
| Locais remotos (sftp/smb/MTP) | fora do escopo; helper diz "somente arquivos locais". |
| Nomes iguais vindos de pastas diferentes num mesmo arquivo | aviso no resumo; documentado. |
| Disco cheio / sem permissão de escrita no destino | mensagem traduzida + limpeza do parcial. |
| Muitos arquivos selecionados (milhares) | arrays Bash (sem limite prático de ARG_MAX dentro do helper); se o 7z estourar ARG_MAX, usar listfile `@arquivo` gerado com `-scsUTF-8` — **cuidado**: com listfile, `-spd` continua necessário. Implementar só se o teste com 5.000 arquivos falhar. |
| Diferenças p7zip 16.02 × 7-Zip oficial | testar também com `p7zip` (container Debian) se possível; não depender de switch que só exista no oficial sem checar `7z` versão. |

---

## 9. Plano de QA (para o @QA)

1. **Automatizado (obrigatório, roda nesta máquina):** `tests/` cobre H1–H13 e I1–I7 em `HOME` temporário, modo `CTX7Z_DIALOG=none`. Comando único: `make test` ou `./tests/run.sh`.
2. **Manual com zenity nesta máquina:** U1–U6 e §7.4 para **Dolphin** (único explorador instalado; sessão Hyprland).
3. **Outros exploradores (não instalados aqui):** testar em container/VM — sugestão: `distrobox` (Fedora/Debian) com o explorador instalado e exportado para a sessão, ou VMs live (Linux Mint Cinnamon → Nemo, Xubuntu → Thunar, Ubuntu MATE → Caja, Lubuntu → PCManFM-Qt, Ubuntu → Nautilus). Enquanto isso não for feito, essas integrações ficam marcadas **"não verificadas em ambiente real"** no relatório.
4. kdialog e yad: instalar temporariamente (`kdialog`, `yad`) ou forçar `CTX7Z_DIALOG=` para validar cada backend de UI.
5. Relatório do QA: tabela explorador × caso (a–d de §7.4) × ação, com OK/FALHA e captura de tela das falhas.

---

## 10. Fora de escopo (MVP)
Instalação system-wide (`/usr/share`), empacotamento (AUR/deb/rpm), extração inteligente sem pasta dupla, arquivos remotos, interface gráfica própria (gerenciador de arquivos compactados), "Compactar e enviar por e-mail", SFX, hashes (CRC/SHA) no menu. Podem virar tickets futuros.
