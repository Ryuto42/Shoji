#!/bin/zsh
# GlassDock・ShelfTabs・MissionView・Shoji のうち、変更のあるものをまとめてリリース用にビルドする
#   scripts/update.sh          dist/ に配布用の zip と appcast.xml を作る
#   scripts/update.sh --check  何がリリース対象かを表示するだけ
#
# 各リポジトリの CHANGELOG.md の先頭の「## X.Y.Z」が次のバージョンになる。
# 変更があるのに先頭のバージョンが公開済み（タグあり）なら、CHANGELOG を書くよう止める。
# ここではコミット・タグ・公開はしない。確認後に scripts/publish.sh で公開する
#
# 環境変数
#   SIGN_IDENTITY   署名に使う証明書（未指定なら Developer ID、なければ Apple Development）
#   NOTARY_PROFILE  公証に使う notarytool のプロファイル（あれば公証する）
set -euo pipefail
source "$(dirname "$0")/repos.sh"

CHECK_ONLY=0
[[ "${1:-}" == --check ]] && CHECK_ONLY=1

# Shoji が使う各機能のバージョンを、各機能の CHANGELOG の先頭に合わせる
sync_shoji_dependencies() {
  local manifest="$(repo_dir Shoji)/Package.swift" name v
  for name in $FEATURES; do
    v="$(changelog_version $name)"
    sed -i '' -E "s/^(    \"$name\": \")[0-9.]+(\",)$/\1$v\2/" "$manifest"
    grep -q "\"$name\": \"$v\"," "$manifest" || { echo "Package.swift の $name のバージョンを書き換えられませんでした" >&2; exit 1; }
  done
}

typeset -a targets=()
errors=0
for repo in $REPOS; do
  [[ "$repo" == Shoji && $CHECK_ONLY == 0 ]] && sync_shoji_dependencies
  v="$(changelog_version $repo)"
  [[ -n "$v" ]] || { echo "✗ $repo: CHANGELOG.md に「## X.Y.Z」の見出しがありません" >&2; errors=1; continue; }
  if ! has_tag $repo $v; then
    echo "● $repo $v をリリースします"
    targets+=($repo)
  elif changed_since_release $repo; then
    echo "✗ $repo: v$v 以降に変更があります。CHANGELOG.md の先頭に新しいバージョンを書いてください" >&2
    errors=1
  else
    echo "  $repo $v は変更なし"
  fi
done
(( errors == 0 )) || exit 1
(( ${#targets} )) || { echo "リリースするものはありません"; exit 0; }
(( CHECK_ONLY == 0 )) || exit 0

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  ids="$(security find-identity -v -p codesigning)"
  SIGN_IDENTITY="$(awk -F'"' '/Developer ID Application/ {print $2; exit}' <<< "$ids")"
  [[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY="$(awk -F'"' '/Apple Development/ {print $2; exit}' <<< "$ids")"
fi
[[ -n "$SIGN_IDENTITY" ]] || { echo "署名に使う証明書が見つかりません（SIGN_IDENTITY で指定してください）" >&2; exit 1; }
export SIGN_IDENTITY
echo "署名: $SIGN_IDENTITY"

# 各機能の単体アプリが統合用の変更で壊れていないか、リリース対象でなくてもビルドして確かめる
for repo in $FEATURES; do
  echo "==> $repo をビルドして確認"
  ( cd "$(repo_dir $repo)" && swift build -c release >/dev/null )
done

for repo in $targets; do
  v="$(changelog_version $repo)"
  echo "==> $repo $v"
  ( cd "$(repo_dir $repo)" && ./scripts/release.sh "$v" )
  # publish.sh が、ビルドした内容のままコミットされるか確かめる
  tree_hash $repo > "$(repo_dir $repo)/dist/.tree"
done

echo
echo "準備ができました。dist/ の中身と各リポジトリの差分を確認してから公開してください:"
for repo in $targets; do echo "  $repo $(changelog_version $repo): $(repo_dir $repo)/dist"; done
echo "  公開: $(dirname "$0")/publish.sh"
