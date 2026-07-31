config() {
  local git_dir="${DOTFILES_GIT_DIR:-$HOME/.config/.dotfiles}"
  local work_tree="${DOTFILES_WORK_TREE:-/}"

  if [[ $# -eq 0 ]]; then
    echo "The function is a alias to \"git --git-dir=\"$git_dir\" --work-tree=\"$work_tree\"\""
    echo "Aiming to maintain a bare repo(dotfile). Using it as a \"git\" command normally"
    return 0
  fi

  local a
  case "$1" in
    add|rm|restore)
      # 根路径/通配符会命中整个 work tree（/），直接拦截
      for a in "${@:2}"; do
        _config_blocked_pathspec "$a" && return 1
      done
      ;;
    checkout)
      # checkout 只有 "--" 之后是路径，之前可能是分支名/选项
      local in_path=0
      for a in "${@:2}"; do
        if [[ "$a" == "--" ]]; then in_path=1; continue; fi
        [[ $in_path -eq 1 ]] && _config_blocked_pathspec "$a" && return 1
      done
      ;;
    clean)
      for a in "${@:2}"; do
        # 短选项组合含 f/d/x/X 即破坏性（-f -d -x -X -fd -fdx ...）
        if [[ "$a" == -[^-]* && "$a" == *[fdxX]* ]]; then
          echo "⛔ blocked: destructive clean on /"; return 1
        fi
        # 长选项只拦确定破坏性的 --force；--dry-run/--quiet/--interactive 放行
        if [[ "$a" == "--force" ]]; then
          echo "⛔ blocked: destructive clean on /"; return 1
        fi
      done
      ;;
  esac

  git --git-dir="$git_dir" --work-tree="$work_tree" "$@"
}

# 返回 0 = 拦截该 pathspec（config 内部使用）
_config_blocked_pathspec() {
  local p="$1"
  if [[ "$p" == "." || "$p" == "./" || "$p" == "/" || "$p" == "//" \
     || "$p" == ":/" || "$p" == ":(top)" || "$p" == ":(top)/" \
     || "$p" == "-A" || "$p" == "--all" ]]; then
    echo "⛔ blocked: root pathspec '$p' targets the whole work tree"
    return 0
  fi
  if [[ "$p" == *\** || "$p" == *\?* || "$p" == *\[* ]]; then
    echo "⛔ blocked: wildcard in pathspec"
    return 0
  fi
  return 1
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

  if [[ $# -gt 2 ]]; then
    echo "❌ Error: too many arguments (expected <file_path> [mode])." >&2
    return 1
  fi

  local file_path="$1"
  local mode="${2:-}"  # 空表示自动检测

  # 展开 ~ 为实际路径，再转成绝对路径（解析 . 和 ..，不解析符号链接）
  file_path="${file_path/#\~/$HOME}"
  local abs="${file_path:a}"

  # 悬空符号链接也算存在（-L）
  if [[ ! -e "$abs" && ! -L "$abs" ]]; then
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

  # 自动检测：保留索引模式或从文件系统识别（文件类型优先于过期的索引模式）
  local old_entry old_mode old_hash
  if [[ -z "$mode" ]]; then
    old_entry=$(git -C "$work_tree" --git-dir="$git_dir" ls-files --stage -- "$rel")
    old_mode=${old_entry%% *}
    if [[ -n "$old_mode" ]]; then
      mode="$old_mode"
      echo "ℹ️  Using existing tracked mode: $mode"
    fi
    if [[ -L "$abs" ]]; then
      if [[ "$mode" != "120000" ]]; then
        echo "ℹ️  '$abs' is a symlink; using mode 120000."
        mode="120000"
      fi
    elif [[ "$mode" == "120000" ]]; then
      echo "ℹ️  '$abs' is no longer a symlink; re-detecting mode."
      mode=""
    fi
    if [[ -z "$mode" ]]; then
      if [[ -x "$abs" ]]; then
        mode="100755"
      else
        mode="100644"
      fi
      echo "ℹ️  Auto-detected from filesystem: $mode"
    fi
  fi

  # mode 与文件类型一致性（显式与最终模式都校验）
  if [[ "$mode" == "120000" && ! -L "$abs" ]]; then
    echo "❌ Error: mode 120000 requires a symlink: '$abs' is not a symlink." >&2
    return 1
  fi
  if [[ "$mode" != "120000" && -L "$abs" ]]; then
    echo "❌ Error: '$abs' is a symlink; use mode 120000 (got '$mode')." >&2
    return 1
  fi

  # 计算 blob 哈希并写入对象库：符号链接必须用链接文本
  # （git hash-object 对链接路径会读目标内容，因此用 readlink -n 走 stdin）
  local blob_hash
  if [[ -L "$abs" ]]; then
    blob_hash=$(readlink -n "$abs" | git --git-dir="$git_dir" hash-object -w --stdin) || {
      echo "❌ Failed to store blob." >&2; return 1
    }
  else
    blob_hash=$(git --git-dir="$git_dir" hash-object -w "$abs") || {
      echo "❌ Failed to store blob." >&2; return 1
    }
  fi

  # 内容与模式都没变 -> 跳过写索引
  if [[ -n "$old_mode" ]]; then
    old_hash=${old_entry#* }; old_hash=${old_hash%% *}
    if [[ "$old_hash" == "$blob_hash" && "$old_mode" == "$mode" ]]; then
      echo "✅ Already up to date: '$rel' (mode $mode)."
      return 0
    fi
  fi

  # 添加到索引（强制绕过 .gitignore）
  if git -C "$work_tree" --git-dir="$git_dir" update-index --add --cacheinfo "$mode" "$blob_hash" "$rel"; then
    echo "✅ Successfully added '$rel' (mode $mode) to the index."
  else
    echo "❌ Failed to add to index. Please check the path and mode." >&2
    return 1
  fi
}
