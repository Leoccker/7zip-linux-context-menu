#!/usr/bin/env bash
# Gera, em tempo de teste, os arquivos usados pela suíte (nada binário no git).
#
# Uso: make_fixtures.sh DIRETORIO_DESTINO
#
# Cria em DESTINO:
#   names/            arquivos com nomes difíceis (espaço, acento, aspas, *, ?, -, \n ...)
#   plain/            árvore pequena com conteúdo conhecido
#   a.7z  b.zip       arquivos simples (a partir de plain/)
#   Backup 2024.tar.gz  tarball comprimido
#   vol.7z.001 .002 .003  conjunto multivolume
#   enc_content.7z    conteúdo criptografado (senha: secret)
#   enc_header.7z     nomes + conteúdo criptografados (senha: secret)
#   corrupt.7z        arquivo com bytes alterados no meio
#   notarchive.txt    arquivo comum
set -eu

dest=${1:?usage: make_fixtures.sh DIR}
bin7z=${CTX7Z_BIN:-}
if [[ -z $bin7z ]]; then
  for c in 7zz 7z 7za; do
    if command -v "$c" >/dev/null 2>&1; then bin7z=$(command -v "$c"); break; fi
  done
fi
[[ -n $bin7z ]] || { echo "7-Zip not found" >&2; exit 1; }

mkdir -p "$dest"
cd "$dest"

# --- nomes difíceis ---------------------------------------------------------
mkdir -p names
(
  cd names
  printf 'espaco\n' >'com espaço.txt'
  printf 'acao\n' >'ação ✓.txt'
  printf 'traco\n' >'-começa-com-traço.txt'
  printf 'asterisco\n' >'as*te?risco.txt'
  # shellcheck disable=SC2016  # o "$x" literal no nome é intencional
  printf 'aspas\n' >'aspas'\''"$x.txt'
  printf 'quebra\n' >$'quebra\nlinha.txt'
  printf 'colchete\n' >'cole[ch]e.txt'
  printf 'barra\n' >'back\slash.txt'
)

# --- árvore simples ---------------------------------------------------------
mkdir -p plain/sub
printf 'um\n' >plain/um.txt
printf 'dois\n' >plain/sub/dois.txt
head -c 200000 /dev/zero | tr '\0' 'x' >plain/grande.txt

"$bin7z" a -t7z -spd -bso0 -bsp0 a.7z -- "$dest/plain" </dev/null
"$bin7z" a -tzip -spd -bso0 -bsp0 b.zip -- "$dest/plain" </dev/null

# --- tarball comprimido (nome com espaço) ----------------------------------
(
  cd plain
  tar -czf "$dest/Backup 2024.tar.gz" um.txt sub
)

# --- multivolume: dados incompressíveis para gerar 3 volumes ----------------
mkdir -p volsrc
head -c 1500000 /dev/urandom >volsrc/random.bin
"$bin7z" a -t7z -mx=0 -v500k -spd -bso0 -bsp0 vol.7z -- "$dest/volsrc" </dev/null
rm -rf volsrc

# --- senhas -----------------------------------------------------------------
"$bin7z" a -t7z -psecret -spd -bso0 -bsp0 enc_content.7z -- "$dest/plain" </dev/null
"$bin7z" a -t7z -psecret -mhe=on -spd -bso0 -bsp0 enc_header.7z -- "$dest/plain" </dev/null

# --- corrompido: sobrescreve bytes no meio de um arquivo sem compressão -----
mkdir -p corruptsrc
head -c 400000 /dev/urandom >corruptsrc/data.bin
"$bin7z" a -t7z -mx=0 -spd -bso0 -bsp0 corrupt.7z -- "$dest/corruptsrc" </dev/null
rm -rf corruptsrc
size=$(stat -c %s corrupt.7z)
printf 'CORRUPTCORRUPTCORRUPT' | dd of=corrupt.7z bs=1 seek=$((size / 2)) conv=notrunc 2>/dev/null

printf 'isto não é um arquivo compactado\n' >notarchive.txt
