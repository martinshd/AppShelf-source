#!/usr/bin/env bash
# 回归：DMG 根目录必须同时有 AppShelf.app 和指向 /Applications 的拖放链接。
# 不生成磁盘映像。没有 macOS hdiutil 时，映像创建保持为待 Mac 验证。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/package-dmg.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[[ -x "$SCRIPT" || -f "$SCRIPT" ]] || fail "缺少 $SCRIPT"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/appshelf-dmg-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

app="$tmp/src/AppShelf.app"
mkdir -p "$app/Contents/MacOS"
printf 'payload' > "$app/Contents/MacOS/AppShelf"

stage="$tmp/stage"
"$SCRIPT" --stage-only "$app" "$stage" >/dev/null
"$SCRIPT" --check-root "$stage"

got="$(ls -A "$stage" | sort)"
want="$(printf '%s\n' Applications AppShelf.app)"
[[ "$got" == "$want" ]] || fail "暂存根目录条目不符：[$got]"
[[ -d "$stage/AppShelf.app" && ! -L "$stage/AppShelf.app" ]] || fail "AppShelf.app 不是应用程序包目录"
[[ -L "$stage/Applications" ]] || fail "Applications 不是符号链接"
[[ "$(readlink "$stage/Applications")" == "/Applications" ]] || fail "Applications 目标不正确"
[[ "$(cat "$stage/AppShelf.app/Contents/MacOS/AppShelf")" == "payload" ]] || fail "应用程序包内容未原样复制"
pass "暂存根目录包含 AppShelf.app 和 Applications -> /Applications"

if "$SCRIPT" --stage-only "$tmp/missing/AppShelf.app" "$tmp/missing-stage" >/dev/null 2>&1; then
  fail "接受了不存在的应用程序包"
fi
pass "拒绝不存在的应用程序包"

mkdir -p "$tmp/empty-bundle/AppShelf.app"
if "$SCRIPT" --stage-only "$tmp/empty-bundle/AppShelf.app" "$tmp/empty-stage" >/dev/null 2>&1; then
  fail "接受了缺少 Contents 的目录"
fi
pass "拒绝缺少 Contents 的目录"

mkdir -p "$tmp/other/Other.app/Contents"
if "$SCRIPT" --stage-only "$tmp/other/Other.app" "$tmp/other-stage" >/dev/null 2>&1; then
  fail "接受了错误的包名"
fi
pass "拒绝不是 AppShelf.app 的包名"

mkdir -p "$tmp/linkdir"
ln -s "$app" "$tmp/linkdir/AppShelf.app"
if "$SCRIPT" --stage-only "$tmp/linkdir/AppShelf.app" "$tmp/link-stage" >/dev/null 2>&1; then
  fail "接受了指向应用程序包的符号链接"
fi
pass "拒绝把符号链接当作 AppShelf.app"

mkdir -p "$tmp/busy"
printf 'x' > "$tmp/busy/x"
if "$SCRIPT" --stage-only "$app" "$tmp/busy" >/dev/null 2>&1; then
  fail "接受了非空暂存目录"
fi
[[ "$(cat "$tmp/busy/x")" == "x" ]] || fail "失败时改写了非空暂存目录"
pass "拒绝非空暂存目录"

bad="$tmp/bad-no-link"
mkdir -p "$bad/AppShelf.app/Contents"
if "$SCRIPT" --check-root "$bad" >/dev/null 2>&1; then
  fail "接受了没有 Applications 的根目录"
fi
pass "拒绝只有 AppShelf.app 的根目录"

bad="$tmp/bad-target"
mkdir -p "$bad/AppShelf.app/Contents"
ln -s /tmp "$bad/Applications"
if "$SCRIPT" --check-root "$bad" >/dev/null 2>&1; then
  fail "接受了错误的链接目标"
fi
pass "拒绝不是 /Applications 的链接目标"

bad="$tmp/bad-dir"
mkdir -p "$bad/AppShelf.app/Contents" "$bad/Applications"
if "$SCRIPT" --check-root "$bad" >/dev/null 2>&1; then
  fail "接受了名为 Applications 的真实目录"
fi
pass "拒绝把 Applications 做成真实目录"

bad="$tmp/bad-extra"
mkdir -p "$bad/AppShelf.app/Contents"
ln -s /Applications "$bad/Applications"
printf 'note' > "$bad/Notes.txt"
if "$SCRIPT" --check-root "$bad" >/dev/null 2>&1; then
  fail "接受了多余文件"
fi
pass "拒绝根目录中的多余文件"

bad="$tmp/bad-meta"
mkdir -p "$bad/AppShelf.app/Contents"
ln -s /Applications "$bad/Applications"
printf 'store' > "$bad/.DS_Store"
"$SCRIPT" --check-root "$bad"
pass "挂载元数据 .DS_Store 不代替拖放入口"

if awk '
  /^[[:space:]]*#/ { next }
  { print }
' "$SCRIPT" | grep -E -n '(^|[^[:alnum:]_])(codesign|xattr|spctl|notarytool|stapler|xcodebuild|productbuild|security|csrutil)([^[:alnum:]_]|$)'; then
  fail "打包脚本包含签名、隔离标记或 Gatekeeper 相关命令"
fi
pass "打包脚本不签名、不清除隔离标记、不修改 Gatekeeper"

grep -q 'hdiutil create' "$SCRIPT" || fail "缺少 hdiutil create"
grep -q -- '-format UDZO' "$SCRIPT" || fail "DMG 格式不再是 UDZO"
grep -q -- '-volname "$VOLUME_NAME"' "$SCRIPT" || fail "卷名不再使用 AppShelf"
grep -q -- '-readonly' "$SCRIPT" || fail "生成后应只读挂载检查"
pass "映像命令仍是卷名为 AppShelf 的 UDZO，并在只读挂载后检查根目录"

out="$tmp/should-not-exist.dmg"
if command -v hdiutil >/dev/null 2>&1; then
  echo "PENDING_MAC: 当前环境有 hdiutil，但本回归只验证暂存布局；请在 macOS 上运行 scripts/package-dmg.sh 生成并检查实际 DMG。"
else
  set +e
  msg="$("$SCRIPT" "$app" "$out" 2>&1)"
  code=$?
  set -e
  [[ "$code" -eq 2 ]] || fail "没有 hdiutil 时退出码应为 2，实际是 $code（$msg）"
  [[ ! -e "$out" ]] || fail "没有 hdiutil 时写出了 DMG"
  printf '%s\n' "$msg" | grep -q 'hdiutil' || fail "缺少 hdiutil 说明：$msg"
  pass "没有 hdiutil 时停止，并且不写出磁盘映像"
  echo "PENDING_MAC: 当前环境没有 macOS hdiutil，未创建、挂载或检查实际 DMG。这一步待在 Mac 上验证。"
fi

echo "结果：拖放根目录回归通过。实际 DMG 构建未在本环境宣称通过。"
