config() {
  local git_dir="$HOME/.config/.dotfiles"
  local work_tree="/"

  # 拦截: config add .  /  config add /  /  config add *  /  config clean -fdx
  if [[ "$1" == "add" ]]; then
    [[ "$2" == "." || "$2" == "/" ]] && { echo "⛔ blocked: would stage /"; return 1; }
    [[ "$2" == "-A" || "$2" == "--all" ]] && { echo "⛔ blocked: --all on /"; return 1; }
    [[ $# -gt 20 ]] && { echo "⛔ blocked: wildcard expansion"; return 1; }
  fi
  if [[ "$1" == "clean" ]]; then
    # 检测 -f -d -x 同时出现就拦
    [[ "$*" == *f* && "$*" == *d* && "$*" == *x* ]] && { echo "⛔ blocked: clean -fdx on /"; return 1; }
  fi

  git --git-dir="$git_dir" --work-tree="$work_tree" "$@"
}

