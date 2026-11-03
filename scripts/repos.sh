# update.sh と publish.sh が共通で使う設定と関数（source して使う）
PROJECTS="$(cd "$(dirname "$0")/../.." && pwd)"
FEATURES=(GlassDock ShelfTabs MissionView)
# 公開する順。Shoji は各機能の公開済みのタグを参照するので最後
REPOS=($FEATURES Shoji)
OWNER="Ryuto42"
typeset -A DESCRIPTIONS=(
  GlassDock   "A Liquid Glass Dock replacement with widgets and window previews for macOS 26"
  ShelfTabs   "Tabs for any app's windows on macOS 26"
  MissionView "A Liquid Glass replacement for Mission Control on macOS 26"
  Shoji       "GlassDock, ShelfTabs and MissionView in one macOS menu-bar app"
)

repo_dir() { echo "$PROJECTS/$1"; }

# CHANGELOG.md の最初の「## X.Y.Z」見出しを、そのリポジトリの次（または現在）のバージョンとする
changelog_version() { awk '/^## [0-9]+(\.[0-9]+)+/ { print $2; exit }' "$(repo_dir $1)/CHANGELOG.md"; }

# そのバージョンの CHANGELOG の本文（リリースノートに使う）
changelog_notes() {
  awk -v v="$2" '$0 ~ "^## " { if (found) exit; if ($2 == v) { found = 1; next } } found' "$(repo_dir $1)/CHANGELOG.md"
}

has_tag() { git -C "$(repo_dir $1)" rev-parse -q --verify "refs/tags/v$2" >/dev/null; }

# .gitignore を守ったうえでの作業ツリー全体のハッシュ（ビルドした内容とコミットする内容が同じか確かめるため）
tree_hash() {
  local idx="$(mktemp -u)"
  ( cd "$(repo_dir $1)" && GIT_INDEX_FILE="$idx" git add -A && GIT_INDEX_FILE="$idx" git write-tree )
  rm -f "$idx"
}

# 前回のリリース（タグ）から何か変わっているか。タグがなければ未公開なので変更ありとする
changed_since_release() {
  local dir="$(repo_dir $1)" last
  last="$(git -C "$dir" describe --tags --abbrev=0 --match 'v*' 2>/dev/null)" || return 0
  [[ "$(tree_hash $1)" != "$(git -C "$dir" rev-parse "$last^{tree}")" ]]
}
