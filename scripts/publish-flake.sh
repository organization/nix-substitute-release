#!/usr/bin/env bash
set -euo pipefail

git check-ref-format "refs/heads/$NSR_FLAKE_BRANCH"
if [[ -e "$NSR_FLAKE_DIRECTORY/.git" ]]; then
  printf '%s\n' 'flake-directory must not contain .git' >&2
  exit 1
fi

# Use the supplied token without changing the runner's Git configuration.
git_flake() {
  git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
    -C "$NSR_FLAKE_DIRECTORY" "$@"
}

repository_url="${GITHUB_SERVER_URL:-https://github.com}/$GH_REPO.git"
git init "$NSR_FLAKE_DIRECTORY"
git_flake symbolic-ref HEAD "refs/heads/$NSR_FLAKE_BRANCH"
git_flake remote add origin "$repository_url"
git_flake add .
tree=$(git_flake write-tree)
parent=()

if git_flake ls-remote --exit-code origin "refs/heads/$NSR_FLAKE_BRANCH"; then
  git_flake fetch origin "refs/heads/$NSR_FLAKE_BRANCH"
  parent=(-p "$(git_flake rev-parse FETCH_HEAD)")
else
  status=$?
  # ls-remote exits with 2 only when the branch does not exist.
  if [[ "$status" != 2 ]]; then
    exit "$status"
  fi
fi

export GIT_AUTHOR_NAME='github-actions[bot]'
export GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

commit=$(git_flake commit-tree "$tree" "${parent[@]}" -m "Release $NSR_TAG")
git_flake push origin "$commit:refs/heads/$NSR_FLAKE_BRANCH"
