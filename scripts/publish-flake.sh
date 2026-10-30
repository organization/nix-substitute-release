#!/usr/bin/env bash
set -euo pipefail

directory=$NSR_FLAKE_DIRECTORY
repository="${GITHUB_SERVER_URL:-https://github.com}/$GH_REPO.git"
git init "$directory"
git -C "$directory" symbolic-ref HEAD "refs/heads/$NSR_FLAKE_BRANCH"
git -C "$directory" add .

tree=$(git -C "$directory" write-tree)
parent=()

if git -C "$directory" -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
  fetch "$repository" "refs/heads/$NSR_FLAKE_BRANCH"; then
  parent=(-p "$(git -C "$directory" rev-parse FETCH_HEAD)")
fi

export GIT_AUTHOR_NAME='github-actions[bot]'
export GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

commit=$(git -C "$directory" commit-tree "$tree" "${parent[@]}" -m "Release $NSR_TAG")

git -C "$directory" -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
  push "$repository" "$commit:refs/heads/$NSR_FLAKE_BRANCH"
