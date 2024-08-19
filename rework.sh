#! /usr/bin/env bash

set -euo pipefail

command=${1:-}

usage="$(cat <<EOF

Usage: $(basename "$0") [--continue | --abort] [-h | --help]

Split a commit into multiple commits by working backwards

Options:
  --continue  Split the commit further
  --abort     Abort the process and return to the original commit
  -h, --help  Print this usage information
EOF
)"

for var in "$@"; do
  case "$var" in
    -h|--help)
      echo "$usage"
      exit 0
    ;;
  esac
done

# Iterate through options and respond accordingly
for var in "$@"; do
  case "$var" in
    --continue)
      git clean -f
      git restore .

      count="$(cat .git/rework/COUNT)"
      git commit -m "Rework $count"
      echo "$(($count + 1))" > .git/rework/COUNT

      branch="$(cat .git/rework/BRANCH)"
      commit="$(git rev-parse HEAD)"

      # If the diff is empty, this is the last (first) commit
      if [ -z "$(git diff git/rework "$commit" --binary)" ]; then
        echo $(git rev-list "$branch..git/rework")

        count=1
        git commit --amend -m "Rework $((count++))"

        # Apply the reverse of all the commits as a replacement to the original commit
        for tempCommit in $(git rev-list "$branch..git/rework"); do
          git revert "$tempCommit" --no-commit
          git commit -m "Rework $((count++))"
        done
        final="$(git rev-parse HEAD)"

        git branch -f "$branch" "$final"
        git checkout "$branch"

        git branch -D git/rework
        rm -rf .git/rework

        exit 0
      fi

      # Take the commit and apply to to the temporary branch
      git checkout git/rework -q
      git diff git/rework "$commit" --binary | git apply --index
      git commit -C "$commit"

      # Checkout the base commit again
      base="$(git rev-parse "$commit^")"
      git checkout "$base" -q

      # Apply remaining changes by cherry picking the original large commit,
      # and all subsequent removals as one diff
      git cherry-pick "..git/rework" -n

      exit 0
    ;;
    --abort)
      echo "Aborting"

      if [ ! -d ".git/rework" ]; then
        echo "Git rework not in progress"
        exit 1
      fi

      git clean -f
      git reset --hard

      commit="$(cat .git/rework/BRANCH)"
      git checkout .
      git checkout "$commit" -q
      git branch -D git/rework
      rm -rf .git/rework

      exit 0
    ;;
    -*|--*)
      echo "Unknown option: '$1'"
      echo "$usage"

      exit 1
    ;;
  esac
done

if [ -d ".git/rework" ]; then
  branch="$(cat .git/rework/BRANCH)"
  echo "Git rework already in progress on $branch ($(git rev-parse --short $branch))"
  exit 1
fi

echo "Starting git rework on $(git symbolic-ref --short HEAD -q) ($(git rev-parse --short HEAD))"

if ! git symbolic-ref --short HEAD -q; then
  echo "Error: Git rework only works on a branch, you are in detatched HEAD state"
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo 'Error: uncommitted changes, Git rework requires a clean branch'
  exit 1
fi

mkdir -p .git/rework

branch="$(git symbolic-ref --short HEAD -q)"
echo "$branch" > .git/rework/BRANCH
echo "1" > .git/rework/COUNT

git branch git/rework $(git rev-parse HEAD)

base="$(git rev-parse "$branch^")"
git checkout "$base" -q
git cherry-pick "..$branch" -n

