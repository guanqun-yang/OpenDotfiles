# Anonymize git user info and optionally rewrite history for anonymous repositories
git-anon() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
Usage: git-anon

Anonymize the current repository's git identity.

What it does:
  1. Sets local user.name/user.email to "Anonymous"
  2. Creates .githooks/post-checkout hook (committed into the repo)
     that auto-enforces anonymous identity on every checkout
  3. Sets core.hooksPath = .githooks
  4. Optionally rewrites all historical commits to anonymous

On a new machine after cloning/pulling an already-anonymized repo:
  Just run `git-anon` — it activates the existing .githooks/ hook
  and sets the local config. No hook is recreated.

See also: git-deanon --help
EOF
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository."
    return 1
  fi

  local anon_name="Anonymous"
  local anon_email="anonymous@users.noreply.github.com"

  # Detect if local config already matches (e.g. re-running after pull on new machine)
  local cur_name cur_email
  cur_name=$(git config --local user.name 2>/dev/null)
  cur_email=$(git config --local user.email 2>/dev/null)

  echo "==> Setting local git user to anonymous..."
  git config user.name "$anon_name"
  git config user.email "$anon_email"
  echo "    user.name  = $anon_name"
  echo "    user.email = $anon_email"

  _git_anon_install_hook "$anon_name" "$anon_email"

  # Check if there are commits with non-anonymous authors
  local real_authors
  real_authors=$(git log --format='%an <%ae>' --all 2>/dev/null | sort -u | grep -v "$anon_name <$anon_email>")

  if [[ -z "$real_authors" ]]; then
    echo "==> No historical commits to rewrite. Done."
    return 0
  fi

  echo ""
  echo "==> Found non-anonymous authors in history:"
  echo "$real_authors" | sed 's/^/    /'
  echo ""
  read -r -p "Rewrite all commits to anonymous? This rewrites history. [y/N] " reply

  if [[ "$reply" != [yY] ]]; then
    echo "Skipped history rewrite. Only local config was updated."
    return 0
  fi

  echo "==> Rewriting commit history..."
  git filter-branch -f --env-filter '
    export GIT_AUTHOR_NAME="Anonymous"
    export GIT_AUTHOR_EMAIL="anonymous@users.noreply.github.com"
    export GIT_COMMITTER_NAME="Anonymous"
    export GIT_COMMITTER_EMAIL="anonymous@users.noreply.github.com"
  ' --tag-name-filter cat -- --all

  echo "==> Done. All commits are now anonymous."
  echo "    To push: git push --force --all && git push --force --tags"
}

# Install a committed post-checkout hook in .githooks/ (travels with the repo)
_git_anon_install_hook() {
  local anon_name="$1" anon_email="$2"
  local repo_root
  repo_root=$(git rev-parse --show-toplevel)
  local hook_dir="$repo_root/.githooks"
  local hook_file="$hook_dir/post-checkout"

  # Point git to the committed hooks directory
  git config core.hooksPath .githooks

  if [[ -f "$hook_file" ]]; then
    echo "==> .githooks/post-checkout already exists. Skipped hook install."
    return 0
  fi

  mkdir -p "$hook_dir"
  cat > "$hook_file" <<HOOK
#!/bin/sh
# git-anon: enforce anonymous identity on checkout
# This hook is committed into the repo. Activate with:
#   git config core.hooksPath .githooks
_anon_name="$anon_name"
_anon_email="$anon_email"
_cur_name=\$(git config --local user.name 2>/dev/null)
_cur_email=\$(git config --local user.email 2>/dev/null)
if [ "\$_cur_name" != "\$_anon_name" ] || [ "\$_cur_email" != "\$_anon_email" ]; then
  git config user.name "\$_anon_name"
  git config user.email "\$_anon_email"
  echo "[git-anon] Set local identity to \$_anon_name <\$_anon_email>"
fi
HOOK
  chmod +x "$hook_file"
  echo "==> Created .githooks/post-checkout (commit this to share with other machines)."
  echo "==> Set core.hooksPath = .githooks"
}

# Restore git user info from global config (undo git-anon local override)
git-deanon() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
Usage: git-deanon

Reverse git-anon for the current repository.

What it does:
  1. Removes local user.name/user.email overrides (falls back to global config)
  2. Unsets core.hooksPath
  3. Deletes .githooks/ directory (remember to commit the deletion)

Note: this does NOT rewrite history. If commits were already rewritten
to anonymous, they stay that way.

See also: git-anon --help
EOF
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository."
    return 1
  fi

  git config --unset user.name 2>/dev/null
  git config --unset user.email 2>/dev/null
  echo "Removed local user.name and user.email overrides."
  echo "Git will now use global config:"
  echo "    user.name  = $(git config --global user.name)"
  echo "    user.email = $(git config --global user.email)"

  _git_anon_remove_hook
}

# Remove the committed hook and hooksPath config
_git_anon_remove_hook() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel)
  local hook_dir="$repo_root/.githooks"

  git config --unset core.hooksPath 2>/dev/null

  if [[ -d "$hook_dir" ]]; then
    rm -rf "$hook_dir"
    echo "==> Removed .githooks/ directory (remember to commit the deletion)."
  fi
}
