#!/usr/bin/env bash
set -Eeuo pipefail
set -x
: "${MANUAL:=""}"
: "${DETECTED:=""}"
: "${VERSION:="beige"}"

# 去掉双引号或者单引号
if [[ "${VERSION}" == \"*\" || "${VERSION}" == \'*\' ]]; then
  VERSION="${VERSION:1:-1}"
fi

declare -A version_map
version_map=(
  ["v23"]="deepin-beige"
  ["beige"]="deepin-beige"
  ["v20"]="deepin-apricot"
  ["apricot"]="deepin-apricot"
)

VERSION=${version_map[${VERSION,,}]}

# 定义镜像地址关联数组
declare -A iso_map
iso_map=(
  ["deepin-beige"]="https://cdimage.deepin.com/releases/23-Beta3/deepin-desktop-community-23-Beta3-amd64.iso"
  ["deepin-apricot"]="https://cdimage.deepin.com/releases/20.9/deepin-desktop-community-20.9-amd64.iso"
)

DETECTED=$VERSION
VERSION=${iso_map[${VERSION,,}]}

CUSTOM=$(find "$STORAGE" -maxdepth 1 -type f -iname custom.iso -printf "%f\n" | head -n 1)

MACHINE="q35"
TMP="$STORAGE/tmp"
VGA="cirrus"

printVersion() {
  local id="$1"
  local desc=""

  desc=${version_map[${id,,}]}

  echo "$desc"
  return 0
}

getName() {
  local file="$1"
  local desc=""

  desc=${version_map[${file,,}]}

  echo "$desc"
  return 0
}

getVersion() {
  local name="$1"
  local detected=""

  detected=${version_map[$name]}

  echo "$detected"
  return 0
}

hasDisk() {

  [ -b "${DEVICE:-}" ] && return 0

  if [ -f "$STORAGE/data.img" ] || [ -f "$STORAGE/data.qcow2" ]; then
    return 0
  fi

  return 1
}

skipInstall() {

  if hasDisk; then
    return 0
  fi

  return 1
}

finishInstall() {

  local iso="$1"

  # Mark ISO as prepared via magic byte
  printf '\x16' | dd of="$iso" bs=1 seek=0 count=1 conv=notrunc status=none

  cp /run/version "$STORAGE/deepin.ver"

  rm -rf "$TMP"
  return 0
}

abortInstall() {
  local iso="$1"

  if [[ "$iso" != "$STORAGE/$BASE" ]]; then
    mv -f "$iso" "$STORAGE/$BASE"
  fi

  finishInstall "$STORAGE/$BASE"
  return 0
}

startInstall() {

  html "Starting deepin..."

  if [ -f "$STORAGE/$CUSTOM" ]; then
    EXTERNAL="Y"
    BASE="$CUSTOM"
  else
    CUSTOM=""
    if [[ "${VERSION,,}" == "http"* ]]; then
      EXTERNAL="Y"
    else
      EXTERNAL="N"
    fi

    if [[ "$EXTERNAL" != [Yy1]* ]]; then
      BASE="$VERSION.iso"
    else
      BASE=$(basename "${VERSION%%\?*}")
      : "${BASE//+/ }"; printf -v BASE '%b' "${_//%/\\x}"
      BASE=$(echo "$BASE" | sed -e 's/[^A-Za-z0-9._-]/_/g')
    fi
  fi

  [ -z "$MANUAL" ] && MANUAL="N"

  if [ -f "$STORAGE/$BASE" ]; then
    # 检查镜像是否经过脚本处理
    local magic=""
    magic=$(dd if="$STORAGE/$BASE" seek=0 bs=1 count=1 status=none | tr -d '\000')
    magic="$(printf '%s' "$magic" | od -A n -t x1 -v | tr -d ' \n')"

    if [[ "$magic" == "16" ]]; then
      if hasDisk || [[ "$MANUAL" = [Yy1]* ]]; then
        return 1
      fi
    fi

    EXTERNAL="Y"
    CUSTOM="$BASE"
  else
    if skipInstall; then
      BASE=""
      return 1
    fi
  fi

  mkdir -p "$TMP"

  if [ ! -f "$STORAGE/$CUSTOM" ]; then
    CUSTOM=""
    ISO="$TMP/$BASE"
  else
    ISO="$STORAGE/$CUSTOM"
  fi

  rm -f "$TMP/$BASE"
  return 0
}

downloadImage() {
  local iso="$1"
  local url="$2"
  local file="$iso"
  local desc rc progress

  rm -f "$iso"

  desc=$(getName "$BASE")
  [ -z "$desc" ] && desc="$BASE"

  local msg="Downloading $desc..."
  info "$msg" && html "$msg"
  /run/progress.sh "$file" "Downloading $desc ([P])..." &

  if [[ "$EXTERNAL" != [Yy1]* ]]; then

    cd /run

    fKill "progress.sh"

    if (( rc == 0 )); then
      [ ! -f "$iso" ] && return 1
      html "Download finished successfully..."
      return 0
    fi
  fi

  # Check if running with interactive TTY or redirected to docker log
  if [ -t 1 ]; then
    progress="--progress=bar:noscroll"
  else
    progress="--progress=dot:giga"
  fi

  { wget "$url" -O "$iso" -q --no-check-certificate --show-progress "$progress"; rc=$?; } || :

  fKill "progress.sh"
  (( rc != 0 )) && error "Failed to download $url , reason: $rc" && exit 60

  [ ! -f "$iso" ] && return 1

  html "Download finished successfully..."
  return 0
}

######################################

if ! startInstall; then
  return 0
fi

if [ ! -f "$ISO" ]; then
  if ! downloadImage "$ISO" "$VERSION"; then
    error "Failed to download $VERSION"
    exit 61
  fi
fi

abortInstall "$ISO"

html "Successfully prepared image for installation..."
return 0
