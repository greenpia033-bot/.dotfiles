config() {
  local git_dir="${DOTFILES_GIT_DIR:-$HOME/.config/.dotfiles}"
  local work_tree="${DOTFILES_WORK_TREE:-/}"

  if [[ $# -eq 0 ]]; then
    echo "The function is a alias to \"git --git-dir="$git_dir" --work-tree="$work_tree"\""
    echo "Aiming to maintain a bare repo(dotfile). Using it as a \"git\" command normally"
    return 0
  fi

  local a
  case "$1" in
    add)
      # 拦截: config add . / ./ / / -A / --all / 任何含通配符的路径
      for a in "${@:2}"; do
        if [[ "$a" == "." || "$a" == "./" || "$a" == "/" || "$a" == "-A" || "$a" == "--all" ]]; then
          echo "⛔ blocked: would stage /"; return 1
        fi
        if [[ "$a" == *\** || "$a" == *\?* || "$a" == *\[* ]]; then
          echo "⛔ blocked: wildcard in pathspec"; return 1
        fi
      done
      ;;
    clean)
      # 拦截: clean 的 -f / -d / -x 组合（clean -fd 同样会删未跟踪文件，甚至裸仓库）
      for a in "${@:2}"; do
        if [[ "$a" == -* && "$a" == *[fdx]* ]]; then
          echo "⛔ blocked: destructive clean on /"; return 1
        fi
      done
      ;;
  esac

  git --git-dir="$git_dir" --work-tree="$work_tree" "$@"
}


configf() {
  local git_dir="${DOTFILES_GIT_DIR:-$HOME/.config/.dotfiles}"
  local work_tree="${DOTFILES_WORK_TREE:-/}"

  # 无参数 -> 显示帮助
  if [[ $# -eq 0 ]]; then
    echo "Usage: configf <file_path> [mode]"
    echo "  <file_path>  : absolute or relative path to the file"
    echo "  [mode]       : optional Git mode (100644, 100755, 120000)"
    echo "                 If not provided, mode is auto-detected:"
    echo "                 1. Preserve existing mode if already tracked"
    echo "                 2. Detect from filesystem (symlink/executable)"
    echo "Examples:"
    echo "  configf /home/greenpia/.oh-my-zsh/custom/alias.zsh"
    echo "  configf /usr/local/bin/myscript 100755   # force executable"
    return 0
  fi

  local file_path="$1"
  local mode="${2:-}"  # 空表示自动检测

  # 展开 ~ 为实际路径，再转成绝对路径（解析 . 和 ..，不解析符号链接）
  file_path="${file_path/#\~/$HOME}"
  local abs="${file_path:a}"

  if [[ ! -e "$abs" ]]; then
    echo "❌ Error: Path '$abs' does not exist." >&2
    return 1
  fi

  if [[ -n "$mode" ]]; then
    # 只保留 blob/链接三种模式；040000/160000 会写坏索引，100664 会被 git 静默降级
    local valid_modes=("100644" "100755" "120000")
    local is_valid=0 m
    for m in "${valid_modes[@]}"; do
      [[ "$mode" == "$m" ]] && { is_valid=1; break; }
    done
    if [[ $is_valid -eq 0 ]]; then
      echo "❌ Error: Invalid mode '$mode'. Valid modes: 100644, 100755, 120000" >&2
      return 1
    fi
  fi

  # 转为相对于工作树根目录的路径（去掉工作树根前缀，而非简单去掉 /）
  local rel="${abs#"${work_tree%/}/"}"
  if [[ "$rel" == "$abs" || -z "$rel" ]]; then
    echo "❌ Error: '$abs' is not inside work tree '$work_tree'." >&2
    return 1
  fi

  # 模式自动检测：已跟踪则保留索引中的模式；否则看符号链接/可执行位
  local old_entry old_mode old_hash
  if [[ -z "$mode" ]]; then
    old_entry=$(git -C "$work_tree" --git-dir="$git_dir" ls-files --stage -- "$rel")
    old_mode=${old_entry%% *}
    if [[ -n "$old_mode" ]]; then
      mode="$old_mode"
      echo "ℹ️  Using existing tracked mode: $mode"
    elif [[ -h "$abs" ]]; then
      mode="120000"   # 符号链接
      echo "ℹ️  Auto-detected from filesystem: $mode"
    elif [[ -x "$abs" ]]; then
      mode="100755"   # 可执行文件
      echo "ℹ️  Auto-detected from filesystem: $mode"
    else
      mode="100644"   # 普通文件
      echo "ℹ️  Auto-detected from filesystem: $mode"
    fi
  fi

  # 计算文件哈希并存入 Git 对象数据库
  local hash
  hash=$(git --git-dir="$git_dir" hash-object -w "$abs")
  if [[ $? -ne 0 || -z "$hash" ]]; then
    echo "❌ Failed to compute hash or store blob." >&2
    return 1
  fi

  # 内容与模式都没变 -> 跳过写索引（省一次子进程）
  if [[ -n "$old_mode" ]]; then
    old_hash=${old_entry#* }; old_hash=${old_hash%% *}
    if [[ "$old_hash" == "$hash" && "$old_mode" == "$mode" ]]; then
      echo "✅ Already up to date: '$rel' (mode $mode)."
      return 0
    fi
  fi

  # 添加到索引（强制绕过 .gitignore）
  if git -C "$work_tree" --git-dir="$git_dir" update-index --add --cacheinfo "$mode" "$hash" "$rel"; then
    echo "✅ Successfully added '$rel' (mode $mode) to the index."
  else
    echo "❌ Failed to add to index. Please check the path and mode." >&2
    return 1
  fi
}
