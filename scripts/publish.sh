#!/bin/zsh
# scripts/update.sh で作ったリリースを公開する（コミット・タグ・push・GitHub リリース）
# GitHub にリポジトリがなければ公開リポジトリとして作る。リポジトリごとに確認してから進む
#   scripts/publish.sh        確認しながら公開
#   scripts/publish.sh --yes  確認せずに公開
set -euo pipefail
source "$(dirname "$0")/repos.sh"

YES=0
[[ "${1:-}" == --yes ]] && YES=1

for repo in $REPOS; do
  dir="$(repo_dir $repo)"
  v="$(changelog_version $repo)"
  has_tag $repo $v && { echo "  $repo $v は公開済み"; continue; }
  zip="$dir/dist/$repo-$v.zip"
  [[ -f "$zip" && -f "$dir/dist/appcast.xml" ]] || { echo "$repo $v の配布物がありません。先に scripts/update.sh を実行してください" >&2; exit 1; }
  [[ "$(cat "$dir/dist/.tree" 2>/dev/null)" == "$(tree_hash $repo)" ]] \
    || { echo "$repo はビルドした後に変更されています。scripts/update.sh をやり直してください" >&2; exit 1; }

  echo
  echo "=== $repo $v"
  git -C "$dir" status --short | head -30
  changelog_notes $repo $v
  if (( ! YES )); then
    read -q "?$repo $v を公開しますか？ [y/N] " || { echo; echo "中止しました"; exit 1; }
    echo
  fi

  (
    cd "$dir"
    git add -A
    git diff --cached --quiet || git commit -q -m "Release $v"
    [[ "$(git rev-parse 'HEAD^{tree}')" == "$(cat dist/.tree)" ]] || { echo "コミットした内容がビルドした内容と違います" >&2; exit 1; }
    git tag "v$v"
    if ! git remote get-url origin >/dev/null 2>&1; then
      gh repo create "$OWNER/$repo" --public --description "${DESCRIPTIONS[$repo]}" --source . --remote origin
    fi
    git push -u origin HEAD:main
    git push origin "v$v"
    gh release create "v$v" "dist/$repo-$v.zip" dist/appcast.xml --repo "$OWNER/$repo" \
      --title "$repo $v" --notes "$(changelog_notes $repo $v)"
  )
  echo "公開しました: https://github.com/$OWNER/$repo/releases/tag/v$v"
done
