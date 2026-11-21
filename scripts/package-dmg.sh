#!/usr/bin/env bash
# 把已经构建好的 AppShelf.app 打成 DMG。
#
# 根目录固定为两项：
#   AppShelf.app
#   Applications -> /Applications
#
# Applications 是符号链接，供访达把 AppShelf.app 拖进去安装。
# 官方 v0.1.3 映像的卷名是 AppShelf、格式是 UDZO/APFS，根目录只有 app，
# 没有这个链接。本脚本沿用同样的 hdiutil create -srcfolder -format UDZO，
# 只补上链接。
#
# 不编译、不签名、不公证、不清除隔离标记，也不修改 Gatekeeper。
# 链接只提供拖放入口，不能消除未签名或未公证安装包的系统拦截。
#
# 用法：
#   scripts/package-dmg.sh <AppShelf.app> <输出.dmg>
#   scripts/package-dmg.sh --stage-only <AppShelf.app> <暂存目录>
#   scripts/package-dmg.sh --check-root <目录>
#
# 生成映像需要 macOS 的 hdiutil。没有 hdiutil 时只能做 --stage-only。

set -euo pipefail

VOLUME_NAME="AppShelf"
APP_NAME="AppShelf.app"
LINK_NAME="Applications"
LINK_TARGET="/Applications"

usage() {
  cat <<'EOF'
用法：
  scripts/package-dmg.sh <AppShelf.app> <输出.dmg>
  scripts/package-dmg.sh --stage-only <AppShelf.app> <暂存目录>
  scripts/package-dmg.sh --check-root <目录>

DMG 根目录包含 AppShelf.app，以及指向 /Applications 的 Applications 符号链接。
生成映像需要 macOS 的 hdiutil；没有该命令时请使用 --stage-only。
EOF
}

fail() {
  echo "错误：$*" >&2
  exit 1
}

require_app() {
  local app="${1%/}"
  [[ -n "$app" ]] || fail "缺少 AppShelf.app 路径。"
  if [[ ! -e "$app" ]]; then
    fail "找不到 AppShelf.app：$app"
  fi
  if [[ -L "$app" || ! -d "$app" ]]; then
    fail "AppShelf.app 必须是应用程序包目录，不能是符号链接或普通文件。"
  fi
  if [[ "$(basename "$app")" != "$APP_NAME" ]]; then
    fail "需要名为 ${APP_NAME} 的应用程序包，实际是 $(basename "$app")。"
  fi
  if [[ ! -d "$app/Contents" ]]; then
    fail "AppShelf.app 缺少 Contents，不是有效的应用程序包。"
  fi
  printf '%s\n' "$app"
}

copy_app_bundle() {
  local src="$1"
  local dest="$2"
  local copy_mode="$3"
  if command -v ditto >/dev/null 2>&1; then
    ditto "$src" "$dest"
    return
  fi
  if [[ "$copy_mode" == "stage" ]]; then
    mkdir -p "$dest"
    cp -R "$src/." "$dest/"
    return
  fi
  fail "生成 DMG 需要 macOS 的 ditto 来复制 AppShelf.app，以免丢掉现有签名和扩展属性。"
}

populate_dmg_root() {
  local app="$1"
  local root="$2"
  local copy_mode="$3"
  copy_app_bundle "$app" "$root/$APP_NAME" "$copy_mode"
  ln -s "$LINK_TARGET" "$root/$LINK_NAME"
}

check_dmg_root() {
  local root="${1%/}"
  local path name
  local saw_app=0
  local saw_link=0
  [[ -d "$root" && ! -L "$root" ]] || fail "无法检查 DMG 根目录：$root"
  for path in "$root"/* "$root"/.[!.]* "$root"/..?*; do
    [[ -e "$path" || -L "$path" ]] || continue
    name="${path##*/}"
    case "$name" in
      "$APP_NAME")
        if [[ -L "$path" || ! -d "$path/Contents" ]]; then
          fail "AppShelf.app 必须是包含 Contents 的应用程序包，不能是符号链接。"
        fi
        saw_app=1
        ;;
      "$LINK_NAME")
        if [[ ! -L "$path" ]]; then
          fail "Applications 必须是指向 /Applications 的符号链接，不能是真实目录。"
        fi
        if [[ "$(readlink "$path")" != "$LINK_TARGET" ]]; then
          fail "Applications 指向 $(readlink "$path")，应为 ${LINK_TARGET}。"
        fi
        saw_link=1
        ;;
      .DS_Store|.Trashes|.fseventsd|.Spotlight-V100|.TemporaryItems|.VolumeIcon.icns)
        ;;
      *)
        fail "DMG 根目录出现意外条目：$name"
        ;;
    esac
  done
  if [[ "$saw_app" -ne 1 || "$saw_link" -ne 1 ]]; then
    fail "DMG 根目录必须同时包含 AppShelf.app 和指向 /Applications 的 Applications。"
  fi
}

absolute_path() {
  local target="${1%/}"
  if [[ "$target" != /* ]]; then
    target="$PWD/$target"
  fi
  printf '%s\n' "$target"
}

stage_only() {
  local app root
  [[ $# -eq 2 ]] || fail "用法：scripts/package-dmg.sh --stage-only <AppShelf.app> <暂存目录>"
  app="$(require_app "$1")"
  root="${2%/}"
  [[ -n "$root" ]] || fail "缺少暂存目录。"
  if [[ -e "$root" ]]; then
    [[ -d "$root" && ! -L "$root" ]] || fail "暂存路径不是目录：$root"
    if find "$root" -mindepth 1 -maxdepth 1 -print | grep -q .; then
      fail "暂存目录必须为空：$root"
    fi
  else
    mkdir -p "$root"
  fi
  populate_dmg_root "$app" "$root" stage
  check_dmg_root "$root"
  echo "已准备拖放根目录：$root"
  echo "包含 AppShelf.app，以及指向 /Applications 的 Applications 符号链接。"
}

create_dmg() {
  local app output stage tmp_base tmp_dmg mnt
  [[ $# -eq 2 ]] || fail "用法：scripts/package-dmg.sh <AppShelf.app> <输出.dmg>"
  app="$(require_app "$1")"
  output="$(absolute_path "$2")"
  [[ "$output" == *.dmg ]] || fail "输出文件必须以 .dmg 结尾：$output"
  [[ -d "$(dirname "$output")" ]] || fail "输出目录不存在：$(dirname "$output")"
  if ! command -v hdiutil >/dev/null 2>&1; then
    echo "错误：找不到 hdiutil。DMG 要在 macOS 上生成；当前环境不能把磁盘映像视为已构建。可先用 --stage-only 检查拖放根目录。" >&2
    exit 2
  fi
  if ! command -v ditto >/dev/null 2>&1; then
    fail "生成 DMG 需要 macOS 的 ditto 来复制 AppShelf.app，以免丢掉现有签名和扩展属性。"
  fi

  stage=""
  tmp_dmg=""
  mnt=""
  cleanup() {
    local status=$?
    if [[ -n "$mnt" ]]; then
      hdiutil detach "$mnt" >/dev/null 2>&1 || hdiutil detach -force "$mnt" >/dev/null 2>&1 || true
      rm -rf "$mnt"
    fi
    if [[ -n "$stage" ]]; then
      rm -rf "$stage"
    fi
    if [[ -n "$tmp_dmg" && -e "$tmp_dmg" ]]; then
      rm -f "$tmp_dmg"
    fi
    exit "$status"
  }
  trap cleanup EXIT

  stage="$(mktemp -d "${TMPDIR:-/tmp}/appshelf-dmg-stage.XXXXXX")"
  populate_dmg_root "$app" "$stage" package
  check_dmg_root "$stage"

  tmp_base="$(mktemp "${TMPDIR:-/tmp}/appshelf-dmg.XXXXXX")"
  rm -f "$tmp_base"
  tmp_dmg="${tmp_base}.dmg"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$stage" \
    -ov \
    -format UDZO \
    "$tmp_dmg" >/dev/null

  mnt="$(mktemp -d "${TMPDIR:-/tmp}/appshelf-dmg-mnt.XXXXXX")"
  hdiutil attach "$tmp_dmg" -readonly -nobrowse -mountpoint "$mnt" >/dev/null
  check_dmg_root "$mnt"
  hdiutil detach "$mnt" >/dev/null
  rm -rf "$mnt"
  mnt=""

  mv -f "$tmp_dmg" "$output"
  tmp_dmg=""
  trap - EXIT
  rm -rf "$stage"
  stage=""
  echo "已生成 $output"
  echo "根目录包含 AppShelf.app，以及指向 /Applications 的 Applications 符号链接。"
  echo "这只补齐拖放安装入口，不改变签名、公证或 Gatekeeper 行为。"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      ;;
    --stage-only)
      shift
      stage_only "$@"
      ;;
    --check-root)
      [[ $# -eq 2 ]] || fail "用法：scripts/package-dmg.sh --check-root <目录>"
      check_dmg_root "$2"
      ;;
    "")
      usage >&2
      exit 1
      ;;
    -*)
      fail "未知参数：$1"
      ;;
    *)
      create_dmg "$@"
      ;;
  esac
}

main "$@"
