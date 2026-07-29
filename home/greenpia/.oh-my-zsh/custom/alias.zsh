# dotfiles bare repo management with safety guards
config() {
  local git_dir="$HOME/.config/.dotfiles"
  local work_tree="/"

  # Block dangerous add operations that would stage entire filesystem
  if [[ "$1" == "add" ]]; then
    # Block: config add .  or  config add /
    if [[ "$2" == "." || "$2" == "/" ]]; then
      echo "⛔ DANGER: 'config add $2' would stage the ENTIRE filesystem! Operation blocked."
      return 1
    fi
    # Block: config add -A  or  config add --all
    if [[ "$2" == "-A" || "$2" == "--all" ]]; then
      echo "⛔ DANGER: 'config add $2' would stage ALL files in /! Operation blocked."
      return 1
    fi
    # Block: config add * (wildcard expansion — too many args means likely * was used)
    if [[ $# -gt 20 ]]; then
      echo "⛔ DANGER: 'config add' with $# arguments — wildcard expansion (config add *) detected! Operation blocked."
      return 1
    fi
  fi

  # Block: config clean -fdx (would delete ALL untracked files from /)
  if [[ "$1" == "clean" ]]; then
    local has_f=0 has_d=0 has_x=0
    for arg in "$@"; do
      [[ "$arg" == -* ]] || continue
      [[ "$arg" == *f* ]] && has_f=1
      [[ "$arg" == *d* ]] && has_d=1
      [[ "$arg" == *x* ]] && has_x=1
    done
    if [[ $has_f -eq 1 && $has_d -eq 1 && $has_x -eq 1 ]]; then
      echo "⛔ DANGER: 'config clean -fdx' would delete ALL untracked files from /! Operation blocked."
      return 1
    fi
  fi

  # Block: config reset --hard (dangerous in bare repo context)
  if [[ "$1" == "reset" && "$2" == "--hard" ]]; then
    echo "⚠️  WARNING: 'config reset --hard' is destructive. Continue? [y/N]"
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 1
  fi

  git --git-dir="$git_dir" --work-tree="$work_tree" "$@"
}

