# BestTerminal

面向 macOS 的 Ghostty + Starship + zsh 终端环境。它既能在一台全新的 Mac 上完成一键安装，也能识别并保留已有的 Ghostty、Oh My Zsh、字体、插件和用户配置，只补齐真正缺少的部分。

核心目标不是简单复制 dotfiles，而是提供一套可检查、可重复执行、可升级、可恢复的安装流程。

## 主要能力

- 自动检测 Apple Silicon / Intel Homebrew；全新系统可自动安装 Homebrew
- 只安装缺失的应用、命令和插件，支持识别手动安装内容
- 保留已有 `.zshrc` 和 Oh My Zsh，不重复加载已经启用的插件
- Ghostty 只补充用户尚未定义的配置键，不覆盖已有字体、字号、颜色等设置
- Starship 区分项目托管配置和用户修改，升级时不会覆盖用户定制
- 使用明确的托管标记，重复运行不会重复追加配置
- 每次修改前建立时间戳备份，写入过程使用同目录原子替换
- 内置 dry run、健康检查、卸载和旧版本配置迁移
- 安装批次失败后逐包重试，降低网络波动造成的整体失败概率

## 安装内容

默认安装以下组件。安装器会逐项检测，已经存在的组件会直接跳过。

| 组件 | 用途 |
| --- | --- |
| Ghostty | GPU 加速终端模拟器 |
| Starship | shell 提示符 |
| Maple Mono NF | 支持中文与 Nerd Font 图标的等宽字体 |
| fzf | `Ctrl+R` 历史搜索、`Ctrl+T` 文件搜索 |
| zoxide | 智能目录跳转，提供 `z` / `zi` |
| eza | 带图标的 `ls` 替代工具 |
| bat | 带语法高亮的 `cat` 替代工具 |
| Yazi | 终端文件管理器，提供退出后自动跳转的 `y` |
| zsh-autosuggestions | 历史命令建议 |
| zsh-syntax-highlighting | 命令语法高亮 |
| zsh-completions | 扩展 zsh 补全定义 |

项目不会安装 Oh My Zsh。已有 Oh My Zsh 会被保留；没有 Oh My Zsh 的用户也可以直接使用。

## 系统要求

- macOS，Apple Silicon 或 Intel
- 系统自带的 `/bin/bash`、`zsh`、`curl` 和 `tar`
- 能访问 GitHub 与 Homebrew 下载源
- 全新系统安装 Homebrew 时，当前账户需要具备管理员权限

## 一键安装

交互式安装会先显示计划并等待确认：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/EasyXdc/BestTerminal/main/install.sh)
```

非交互式安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/EasyXdc/BestTerminal/main/install.sh) --yes
```

建议在执行网络脚本前先查看内容，或先运行 dry run：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/EasyXdc/BestTerminal/main/install.sh) --dry-run
```

也可以克隆后本地执行：

```bash
git clone git@github.com:EasyXdc/BestTerminal.git
cd BestTerminal
./install.sh
```

安装完成后重启 Ghostty，或者执行：

```zsh
exec zsh
```

## 不同环境下的行为

| 用户现状 | 默认处理方式 |
| --- | --- |
| 什么都没有安装 | 安装 Homebrew、全部组件和完整默认配置 |
| Ghostty 是手动安装的 | 识别 `/Applications/Ghostty.app`，不会用 Homebrew 重装 |
| 字体是手动安装的 | 扫描用户和系统字体目录，存在 Maple Mono NF 时跳过 |
| 某些命令已经存在 | 根据 PATH 和 Homebrew 状态判断，只安装缺少的命令 |
| zsh 插件来自 Oh My Zsh 或手动 clone | 识别常用插件目录，不重复安装或 source |
| 已有 `.zshrc` | 保留原内容，只加入一个 BestTerminal 托管入口 |
| 已有 Ghostty 配置 | 保留已有键，只在托管块中补齐未定义的键 |
| 已有 Starship 配置 | 默认视为用户配置并保留；使用 `--force-config` 才替换 |
| 重复运行安装器 | 更新托管文件，不重复追加标记或别名 |
| 使用旧版安装器 | 自动移除旧的 `ghostty-terminal-config` 托管块后迁移 |

## 安装选项

```text
-y, --yes             无交互确认
    --dry-run         只显示检测结果，不修改系统
    --minimal         只安装 Ghostty、Starship 和字体
    --config-only     不安装软件包，只配置已有组件
    --force-config    用项目主题替换现有 Starship 配置
    --skip-ghostty    不安装也不配置 Ghostty
    --skip-font       不安装字体
    --no-backup       不创建备份，不建议日常使用
-h, --help            查看帮助
    --version         查看安装器版本
```

示例：保留现有终端，只接入 Starship 和 shell 工具：

```bash
./install.sh --skip-ghostty
```

只使用 Ghostty + Starship 的最小组合：

```bash
./install.sh --minimal
```

## 配置所有权

安装器有意区分“项目托管”与“用户拥有”的配置。

### zsh

`.zshrc` 中只加入以下入口：

```zsh
# >>> BestTerminal >>>
[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/best-terminal/zsh/init.zsh" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/best-terminal/zsh/init.zsh"
# <<< BestTerminal <<<
```

实际集成保存在 `~/.config/best-terminal/zsh/init.zsh`，项目升级时可以安全替换。个人别名和覆盖项请写入：

```text
~/.config/best-terminal/user.zsh
```

该文件在项目别名之后、语法高亮之前加载，不会被安装器覆盖。例如：

```zsh
alias ls='eza -la --icons'
export STARSHIP_LOG=error
```

### Ghostty

目标文件通常是 `~/.config/ghostty/config`。项目默认值位于：

```text
# >>> BestTerminal managed defaults >>>
...
# <<< BestTerminal managed defaults <<<
```

已有配置键永远优先保留。需要覆盖项目默认值时，把自己的赋值写在结束标记之后；下次运行安装器时，该键会被识别为用户配置并从托管块中移除。

### Starship

目标文件通常是 `~/.config/starship.toml`：

- 文件不存在时，安装项目主题并记录校验和
- 文件仍是项目上次安装的版本时，可以安全升级
- 文件被用户修改后，后续安装默认不覆盖
- `--force-config` 会先备份，再安装项目主题

若设置了 `STARSHIP_CONFIG` 或 `XDG_CONFIG_HOME`，安装器会使用相应路径。

## 快捷键与命令

| 操作 | 功能 |
| --- | --- |
| `Ctrl+R` | 使用 fzf 搜索历史命令 |
| `Ctrl+T` | 使用 fzf 搜索文件 |
| `Ctrl+F` | 接受 autosuggestions 当前建议 |
| `z project` | 跳转到最匹配的历史目录 |
| `zi project` | 交互选择匹配目录 |
| `y` | 打开 Yazi，退出后进入最后浏览目录 |
| `ll` | 显示带图标的详细文件列表 |
| `lt` | 显示两层目录树 |

## 备份与恢复

备份保存在：

```text
~/.local/state/best-terminal/backups/<时间戳>/
```

每份备份可能包含 `.zshrc`、`.zprofile`、Ghostty 配置、Starship 配置、安装状态和 `manifest`。恢复单个文件时，从目标时间戳目录复制回 `manifest` 中记录的位置即可。

安装器使用同目录临时文件和原子重命名，避免中断时留下只写入一半的配置。若发现托管块缺少结束标记，安装器会报错退出，不会猜测或改写文件。

## 健康检查

克隆仓库后执行：

```bash
./doctor.sh
```

检查内容包括核心命令、可选工具、zsh 语法、托管入口、Starship 配置解析和 Ghostty 配置解析。缺少核心组件时返回非零退出码，便于脚本或 CI 使用。

## 卸载

```bash
./uninstall.sh
```

或直接运行远程卸载器：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/EasyXdc/BestTerminal/main/uninstall.sh)
```

卸载器只移除 BestTerminal 托管的配置：

- 删除 `.zshrc`、`.zprofile` 和 Ghostty 中的托管块
- 删除项目安装的 shell 集成文件
- Starship 未被修改时，恢复安装前备份或删除项目创建的文件
- 用户修改过的 Starship 配置会被保留
- Homebrew、Ghostty、字体和命令行工具不会被卸载

使用 `--keep-starship` 可以始终保留当前 Starship 配置。卸载前同样会建立备份。

## 项目结构

```text
.
├── install.sh                 # 本地入口与远程引导脚本
├── uninstall.sh               # 本地入口与远程卸载引导脚本
├── doctor.sh                  # 健康检查入口
├── config/
│   ├── ghostty/config         # Ghostty 默认配置模板
│   ├── starship/starship.toml # Starship Catppuccin Powerline 主题
│   └── zsh/init.zsh           # 可独立于 Oh My Zsh 使用的 shell 集成
├── scripts/
│   ├── install.sh             # 检测、安装、合并、备份和验证
│   ├── uninstall.sh           # 安全移除托管配置
│   ├── doctor.sh              # 诊断逻辑
│   └── lib.sh                 # 原子写入、标记处理等公共函数
└── tests/test-install.sh      # 隔离 HOME 的集成场景测试
```

## 开发与测试

项目兼容 macOS 自带 Bash 3.2，不使用 Bash 4 专属关联数组。

```bash
for file in install.sh uninstall.sh doctor.sh scripts/*.sh tests/*.sh; do
  /bin/bash -n "$file"
done

/bin/bash tests/test-install.sh
shellcheck install.sh uninstall.sh doctor.sh scripts/*.sh tests/*.sh
```

测试在隔离的临时 HOME 中运行，覆盖 Homebrew 自举与全量安装、已有配置增量合并、幂等重跑、强制配置恢复、损坏标记保护和符号链接 dotfiles，不会修改开发机器的真实配置。

## License

[MIT](LICENSE)。改造所基于项目及主题的归属信息见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
