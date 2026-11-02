#!/usr/bin/env bash
# 这里只放假数据构建出来的页面。main 放在根目录，其他分支放在 branch/<分支名>/。
# 源码仓库是私有的，用只读的部署密钥取代码；.built/ 记着每个分支构建到哪个提交。
set -euo pipefail

source_repo=git@github.com:keynary/kinawatch-web.git
site=$PWD

mkdir -p ~/.ssh .built
printf '%s\n' "$SOURCE_DEPLOY_KEY" > ~/.ssh/source_key
chmod 600 ~/.ssh/source_key
export GIT_SSH_COMMAND='ssh -i ~/.ssh/source_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new'

seen=' '
while read -r sha ref <&3; do
  branch=${ref#refs/heads/}
  slug=$(printf '%s' "$branch" | tr -c 'a-zA-Z0-9._-' '-')
  seen="$seen$slug "
  [ "$(cat ".built/$slug" 2>/dev/null)" != "$sha" ] || continue
  # 先记下来：构建失败的提交不用每 5 分钟重试一次。
  echo "$sha" > ".built/$slug"
  work=$(mktemp -d)
  git clone -q --depth 1 --branch "$branch" "$source_repo" "$work"
  if ! (cd "$work" && npm ci && npm run build:demo); then
    echo "::warning::$branch 构建失败，预览保持原样"
    continue
  fi
  if [ "$branch" = main ]; then
    find . -mindepth 1 -maxdepth 1 ! -name .git ! -name .github ! -name .built ! -name branch -exec rm -rf {} +
    cp -R "$work/dist-demo"/. .
  else
    rm -rf "branch/$slug"
    mkdir -p "branch/$slug"
    cp -R "$work/dist-demo"/. "branch/$slug"/
  fi
done 3< <(git ls-remote --heads "$source_repo")

# 分支删掉了，它的预览也删掉。
for file in .built/*; do
  slug=${file#.built/}
  case "$seen" in *" $slug "*) ;; *) rm -rf "$file" "branch/$slug" ;; esac
done

touch .nojekyll
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add -A
if git diff --cached --quiet; then
  echo '没有变化'
  exit 0
fi
git commit -q -m 'Update previews'
git push -q
gh api -X POST "repos/$GITHUB_REPOSITORY/pages/builds" --silent || true
