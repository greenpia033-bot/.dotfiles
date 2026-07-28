### Ubuntu 24.04 WSL2 → Debian（计划中）

### 0. WSL 侧配置

Windows `C:\Users\ASUS\.wslconfig`：

```ini
[wsl2]
memory=10GB
processors=6
swap=2GB

[experimental]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
```

`/etc/wsl.conf`：

```ini
[boot]
systemd=true
command = "ip link set dev eth0 mtu 1200"
[user]
default=greenpia
[network]
hostname = bi7dyv
```

---

### 1. Shell

```bash
# Oh My Zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# 插件
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-completions $ZSH_CUSTOM/plugins/zsh-completions

# ble.sh (bash 增强)
git clone --recursive https://github.com/akinomyoga/ble.sh.git
cd ble.sh && make install PREFIX=~/.local
```

`.zshrc` 用 `ys` 主题，prompt 带 docker 状态指示。

Oh My Zsh 主题参考 (theme): `ys`。备选: powerlevel10k。

---

### 2. 包迁移：Ubuntu → Debian

**全局说明**：标注 ⛔ 的为 Ubuntu/WSL 专有包，Debian 不应安装。

#### 系统基础层
```bash
apt install -y adduser apt aptitude bash-completion bc bzip2 ca-certificates \
  coreutils cron curl dbus debconf debianutils diffutils dmsetup dpkg \
  e2fsprogs file findutils fuse3 gawk gnupg grep gzip hostname init \
  iproute2 iptables iputils-ping kmod less locales login logrotate \
  lsb-release lsof man-db mount nano netbase netcat-openbsd openssh-client \
  openssl passwd perl procps psmisc rsyslog sed sudo systemd \
  systemd-resolved systemd-timesyncd tar tzdata udev usbutils util-linux \
  vim wget whiptail xz-utils zip unzip
```

#### 开发工具链 / 编译
```bash
apt install -y build-essential gcc g++ gdb binutils make cmake cmake-curses-gui \
  ninja-build pkgconf pkg-config autoconf automake autotools-dev libtool \
  m4 bison flex nasm patch linux-libc-dev
```

#### Docker
```bash
# 全部来自 Docker 官方源（非 Ubuntu archive），Debian 添加相同源即可
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
```
`/etc/docker/daemon.json`：数据目录 `/opt/docker`，overlay2，国内 mirror，BuildKit 开，日志 10m×3。

#### Python
```bash
apt install -y python3 python3-dev python3-pip python3-venv python3-numpy \
  python3-setuptools python3-wheel python3-yaml python3-requests \
  python3-certifi python3-chardet python3-cryptography python3-openssl \
  python3-pygments python3-rich python3-click python3-colorama \
  python3-jinja2 python3-jsonschema python3-attrs python3-typing-extensions \
  python3-serial python3-opencv
```

#### Go
```bash
# ⚠️ 当前 Ubuntu 装的是 longsleep PPA (Jammy)，Debian 不可用！
# Debian 方案：手动 tarball（推荐）或 backports
wget https://go.dev/dl/go1.26.4.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.26.4.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.zshrc
```

#### Node.js
```bash
# 来自 NodeSource APT repo（Debian 兼容，添加对应源即可）
apt install -y nodejs npm
# 也推荐 nvm：
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
nvm install --lts
```

#### OpenCV / 视觉
```bash
apt install -y opencv-data python3-opencv libopencv-dev
```

#### 网络 / 系统工具
```bash
apt install -y bind9-dnsutils curl wget git jq rsync lshw pciutils \
  net-tools ethtool nftables bubblewrap gdisk htop pigz tmux
```

#### 字体 / X11
```bash
apt install -y fontconfig fonts-dejavu-core fonts-dejavu-mono \
  fonts-liberation xdg-utils
```

#### ⛔ Ubuntu/WSL 专有包 — Debian 不应安装

| 包 | 原因 |
|------|------|
| `apport*` | Ubuntu 崩溃报告 → Debian 用 `reportbug` |
| `command-not-found` | Ubuntu 专有 |
| `ubuntu-keyring/minimal/mono/pro-client*` | Ubuntu 专有 |
| `ubuntu-release-upgrader-core` | Ubuntu 发行版升级 |
| `ubuntu-wsl, wsl-pro-service, wsl-setup` | WSL 专有 |
| `netplan.io` | Canonical → Debian 用 ifupdown2/NetworkManager |
| `landscape-client/common` | Canonical Landscape |
| `update-manager-core, unattended-upgrades` | Ubuntu 更新管理 |
| `software-properties-common` | Ubuntu PPA 管理 |
| `python3-launchpadlib, python3-lazr.*` | Launchpad API |
| `python3-apport, python3-commandnotfound` | Ubuntu Python 绑定 |

---

### 3. Dotfiles 裸仓库

**创建方式（老机器上）**：

```bash
git init --bare ~/.config/.dotfiles
```

`~/.config/.dotfiles/config` 设 `bare = true`，`status.showUntrackedFiles = no`。

`~/.config/.dotfiles/info/exclude` 排除 `~/.config/.dotfiles/` 自身。

`~/.oh-my-zsh/custom/alias.zsh` 里的 `config` 函数：

```bash
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
```

日常使用：

```bash
config status
config add etc/some/file
config commit -m "..."
config push
```

**换机时恢复**：

```bash
git clone --bare git@github.com:greenpia033-bot/.dotfiles.git ~/.config/.dotfiles
git --git-dir=$HOME/.config/.dotfiles --work-tree=/ checkout
```

> work-tree 是 `/`，所以 `config add .` / `add *` / `clean -fdx` 会被硬拦截。

---

### 4. Git 速查

```bash
# 冲突解决
git stash                           # 暂存未提交修改
git stash pop                       # 恢复最近一次 stash
git reset --hard HEAD               # 强制丢弃所有本地修改
git merge --abort                   # 取消正在进行的合并

# 远程仓库
git remote add origin <url>         # 关联远程仓库
git remote set-url origin <url>     # 修改远程仓库地址
git remote -v                       # 查看所有远程仓库

# 浅克隆 / 子模块
git clone --depth 1 <url>           # 浅克隆（仅最新提交）
git clone --recurse-submodules <url> # 递归克隆子模块
git submodule update --init --recursive

# .gitignore / git rm
git rm --cached <file>              # 从跟踪中移除但保留本地文件
git rm -r --cached .vscode          # 移除已跟踪目录

# 分支与工作树
git checkout -b <branch>
git worktree add ../path <branch>   # 不切换分支检出到另一个目录
git push --force-with-lease         # 安全强制推送（比 --force 安全）
```

---

### 5. CMake / GCC / 构建

```bash
cmake -B build                                  # 指定构建目录
cmake -B build -G Ninja                         # 使用 Ninja 生成器
cmake -B build -DCMAKE_BUILD_TYPE=Release       # 设置构建类型
cmake -B build -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake  # 交叉编译
cmake --build build -j$(nproc)                  # 并行构建

# GCC
gcc -Wall -Werror -O2 -g -o output source.c
```

龙芯交叉编译 toolchain.cmake:

```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR loongarch64)
set(CMAKE_C_COMPILER   /opt/loongarch64-linux-gnu/bin/loongarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER /opt/loongarch64-linux-gnu/bin/loongarch64-linux-gnu-g++)
```

---

### 6. Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

`/etc/docker/daemon.json`：数据目录 `/opt/docker`，overlay2，国内 mirror，BuildKit 开，日志 10m×3。

---

### 7. 龙芯 2K300/301 智能车平台

**工具链**: `/opt/loongson-gnu-toolchain-8.3-x86_64-loongarch64-linux-gnu-rc1.6/`

**SDK 源码结构** (龙邱科技 Loongson_2K300_301_Library):

| 目录 | 内容 |
|------|------|
| `libraries/drv/` | 底层驱动: GPIO/PWM/GTIM/TFT/UART/I2C/ADC/Timer |
| `libraries/common/` | 通用: 限幅函数、毫秒时间戳、基类 |
| `libraries/app/` | 陀螺仪42688等应用驱动 |
| `main/` | main.cpp、toolchain_path.cmake、build.sh |
| `user_app/` | PID、电机/IMU/图像控制 |
| `tools/` | 交叉编译工具链 + 依赖库(ffmpeg/opencv/ncnn) |

**久久派 25 集教程** (UP主: 龙邱科技):

**PID 控制全家**:

| 类型 | 说明 |
|------|------|
| 增量式 PID | 无积分饱和，适用于带积分特性的执行机构 |
| 位置式 PID | 带积分限幅 (`maxIntegral`) 和输出限幅 |
| PD + 前馈 | 含 Kff + Kff_acc，低通滤波微分项 |
| 三环级联 (OOP) | 速度环 → 角速度环(IMU) → 图像环 |
| LADRC | 相对 PID 改进，正在调研 |
| VOFA+ | PID 波形监测 + 串口在线改参 |

源码参考:
- HaoBoost/Smart-Car: `user_app/inc/pid.h`
- hccc1203/RunACCM2025: 国一开源，capture/track/detection

**Debian 迁移注意**:
- 工具链预编译于 x86_64，glibc 兼容性应无问题
- ffmpeg/opencv/ncnn 预编译包基于 Ubuntu，Debian 下可能需重编
- `build.sh` 中 `make -j` 参数在 Debian 上行为一致

---

### 8. 故障排查速查

| 错误 | 原因 | 解决 |
|------|------|------|
| `git merge: Please commit or stash` | 本地有未提交修改 | `git stash` 暂存后再 merge |
| Edge 启动 CDP 后 `netstat` 无 LISTENING | 残留进程没杀 | `taskkill /f /im msedge.exe` 重来 |
| `curl localhost:9222` 返回 502 | Clash 代理劫持 | `curl --noproxy '*'` |
| Hexo deploy GitHub 连接失败 | SSH key 或分支不对 | 检查 `_config.yml` 中 repo 和 branch |
| pip install 路径过长 | Windows 路径限制 | `TMPDIR=/tmp pip install` |
| Moon Bridge `401 unauthorized` | api_key 错误 | 检查 DeepSeek 后台 key |
| Moon Bridge `402 payment required` | 余额不足 | DeepSeek 充值 |
| `apt autoremove` 危险 | 可能误删依赖 | 确认列表后再执行 |
| WSL2 zombie process | systemd 兼容性 | Debian 下行为可能不同，需验证 |

---

### 9. Codex + Moon Bridge

```bash
# codex-cli 已全局安装 (0.145.0)
# Moon Bridge: /opt/moon-bridge/

# mb 别名: 启 Moon Bridge → 等就绪 → 启 Codex → 退出自动关
mb              # 当前目录
mb /some/project
```

Moon Bridge `config.yml` 最小示例：

```yaml
mode: "Transform"
server:
  addr: "127.0.0.1:38440"
models:
  deepseek-chat:
    context_window: 64000
providers:
  deepseek:
    base_url: "https://api.deepseek.com/anthropic"
    api_key: "sk-你的密钥"
    offers:
      - model: deepseek-chat
routes:
  moonbridge:
    model: deepseek-chat
    provider: deepseek
defaults:
  model: moonbridge
  max_tokens: 4096
```

生成 Codex `config.toml`:

```bash
go run ./cmd/moonbridge -print-codex-config "moonbridge" \
  -codex-base-url "http://127.0.0.1:38440/v1" \
  -codex-home "$HOME/.codex" > "$HOME/.codex/config.toml"
```

`codebase-memory-mcp`: `~/.local/bin/`

`.zshrc` 中 `mb` 函数: 启 Moon Bridge → 等就绪 (curl 探 `/v1/models`) → 启动 Codex → 退出时自动 kill。

---

### 10. 软件清单

| 软件 | 安装方式 |
|------|----------|
| build-essential, gcc/g++ 13, cmake, ninja | `apt install` |
| Go 1.26 | Debian: 手动 tarball (`go.dev/dl`) |
| Python 3.12 + numpy + opencv | `apt install python3 python3-dev python3-opencv` |
| Node.js + npm | NodeSource 或 nvm |
| OpenCV 4.10 (full dev) | `apt install libopencv-dev` |
| Docker CE + compose plugin | 官方脚本 `get.docker.com` |
| Oh My Zsh + 4 插件 | curl 安装 + git clone 插件 |
| ble.sh | git clone + make install |
| fastfetch | `apt install fastfetch` |
| google-chrome-stable | deb 包 |
| Chrome for Testing | `/opt/google/chrome/` |
| Loongson 工具链 | `/opt/loongson-gnu-toolchain-8.3-.../` (龙芯交叉编译) |

---

### 11. 新机验证

```bash
wsl --shutdown  # 重启 WSL 后
docker run hello-world
config status
go version && python3 --version && node --version
codex --version
```

---

### 12. Playwright / CDP 连 Windows Edge

WSL 里直接用 Windows 上的 Edge（免装 Chromium，复用登录态）。

**Windows 侧启动 Edge debug 模式**：

```powershell
# 先杀干净（否则 flag 不生效）
taskkill /f /im msedge.exe

# 用独立 user-data-dir 启动，不影响日常 Edge
& "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" `
  --remote-debugging-port=9222 `
  --remote-debugging-address=0.0.0.0 `
  --user-data-dir="C:\tmp\edge-debug"
```

验证端口开了：

```powershell
netstat -ano | findstr 9222
# 应该看到 LISTENING
```

**WSL 侧连接**：

```bash
# 注意：必须绕代理，Clash 会劫持 localhost 请求返回 502
curl --noproxy '*' -s http://127.0.0.1:9222/json
```

**Playwright connect_over_cdp**：

```ts
const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
```

**坑**：

1. `taskkill /f` 必不可少 — Edge 有残留进程时再加 `--remote-debugging-port` 不生效，`netstat` 只会看到 `TIME_WAIT` 没有 `LISTENING`
2. `http_proxy`（Clash 7897）会拦截发往 `localhost:9222` 的请求，返回 502。curl 加 `--noproxy '*'`，Playwright 设 `--proxy-server=''` 或在代码里配 `bypass: 'localhost'`

---

> 此文件在 `~/.config/.dotfiles/` 下，被 `info/exclude` 排除，不会 tracked 到 `/`。
