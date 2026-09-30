# 同学使用指南：从安装到第一次代码任务

这份指南面向第一次使用本仓库的同学。OpenCode 是终端里的代码助手；本仓库
负责把它连接到课题组的 SAGE Qwen 服务，**不需要在自己的机器上部署模型，
也不需要 GPU / NPU**。

## 1. 安装前准备

- 使用 macOS、Linux 或 Windows 的 WSL 终端；不要在原生 PowerShell 中执行以下命令。
- 准备好课题组单独发给你的**个人 API Key**。仓库不提供 Key，请勿借用或转发他人的 Key。
- 需要 Git、Bash，以及 `curl` 或 `wget`。Node.js 和 OpenCode 由安装器处理。
- 机器需要能访问 GitHub、npm 软件源、SAGE 服务；自动安装 Node.js 时还需访问 Node.js 官网。
- 在共享服务器上使用自己的账户安装，**不要加 `sudo`，不要使用共用的 root 账户保存个人 Key**。

这是远程模型服务：提问和工具读取的相关代码可能作为上下文发送给 SAGE。
只在你有权使用该服务处理的项目中运行，勿让助手读取密码、密钥或未获授权的资料。

## 2. 下载并安装

在终端依次执行：

```bash
git clone https://github.com/intellistream/sage-qwen-opencode.git
cd sage-qwen-opencode
./install.sh
```

看到 `Paste your personal SAGE API key (input is hidden):` 时，粘贴个人 Key，
然后按回车。**输入时没有字符或星号显示是正常现象**。不要把 Key 写到命令后面，
否则可能留在 shell 历史中。

看到 `Installation complete.` 表示本地安装完成；是否能访问模型，还需下面的实际验证。
已有密钥文件时安装器会复用，不会再次询问。更换 Key 请在仓库目录执行：

```bash
./install.sh --replace-key
```

安装会更改 OpenCode 的默认模型和 Agent，并备份已有配置、保留其他设置。
软件安装在当前用户的 `~/.local` 中。请不要另行执行 `opencode upgrade`：本仓库的
OpenCode、provider 和兼容适配器按固定版本配套验证。

## 3. 先验证一次工具调用

在临时目录运行一个只执行 `pwd` 的小任务：

```bash
mkdir -p "$HOME/sage-opencode-demo"
cd "$HOME/sage-opencode-demo"
~/.local/bin/opencode run --agent sage-qwen \
  --model 'sage-qwen38/Qwen/Qwen3.8-27B' \
  --variant xhigh \
  '请调用 shell 工具执行一次 pwd，然后只返回它输出的绝对路径。不要读取其他文件。'
```

成功时，应当同时看到工具执行 `pwd` 的记录，以及助手最终返回的目录绝对路径。
**仅看到一句文字回复，不代表工具调用已经验证通过。** 若出现权限确认，先检查
请求确实只是执行 `pwd`，再批准。

## 4. 打开交互界面

进入你想处理的项目目录，然后启动：

```bash
cd /你的/项目目录
~/.local/bin/opencode
```

这里的 `/你的/项目目录` 是占位符，请换成实际路径。正常启动后，应看到输入框及
`Sage-Qwen` / `Qwen3.8-27B` 模型标识。新开终端后通常也可以直接输入 `opencode`；
使用上面的完整路径可以避免误启动其他旧安装。

第一次可以输入：

> 请先阅读项目说明，概括目录结构与测试入口。先不要修改文件，也不要启动服务。

熟悉后，再交给它一个小而明确的任务，例如：

> 请定位这个报错的原因，先说明你的判断和计划，等我确认后再修改代码。

它能执行命令、修改文件，不只是聊天。重要项目先提交或备份自己的改动；执行前
留意权限提示，完成后检查 diff 和测试结果。共享服务器上不要让它停止他人的进程，
或未经分配就启动占用加速卡的任务。

### 常用切换

- **Shift+Tab**：循环切换 `low → medium → xhigh` 推理档位，默认 `xhigh`。
- **Ctrl+T**：切换 Agent；使用本服务时选 `sage-qwen`。
- `low` 适合简单问答，`medium` 适合一般任务，`xhigh` 适合复杂排查。

## 5. 更新与故障排查

更新时回到安装仓库目录（不是正在开发的项目目录）：

```bash
cd /你保存仓库的位置/sage-qwen-opencode
git pull --ff-only
./install.sh
```

退出旧界面，再启动 `~/.local/bin/opencode`。普通更新不需要重新输入 Key。

| 现象 | 先做什么 |
| --- | --- |
| `opencode: command not found` | 使用 `~/.local/bin/opencode`，或重新打开终端。 |
| `401` / `403` | 检查个人 Key，必要时用 `./install.sh --replace-key` 重录；若仍失败，把不含 Key 的错误发给助教，403 也可能来自服务访问限制。 |
| 能回答，但工具调用报错 | 更新仓库并重跑安装器，不要单独升级依赖。 |
| `EMFILE ... watch ...` | 更新并重新安装；Linux 修复不需要修改系统 `sysctl`。 |
| TUI 空白、一直不出输入框 | 先用完整路径启动；若以前装过 V2，按下一段排查数据库兼容性。 |

### 曾经用过 OpenCode V2 的同学

V2 数据库与本仓库固定的 `1.18.33` 版本不兼容，可能导致空白界面；命令行运行
可能提示 `Database is not empty and has no session table`。

**Linux 安装器已处理这个问题**：启动器默认使用独立的 `sage-opencode-1.db`。
原数据库及旧历史不会删除或迁移，但不会显示在新数据库中；不要为排障删除数据库。
如果自己设置过 `OPENCODE_DB`，该设置会优先于启动器默认值，请确认没有指向 V2 数据库。

macOS 没有这个 Linux 启动器；若遇到同样的数据库错误，可以显式使用独立数据库启动：

```bash
OPENCODE_DB=sage-opencode-1.db ~/.local/bin/opencode
```

此 macOS 路径未在本次 Linux 实机验证中测试。更完整的配置位置及排障说明见
[README](README.md)。

## 6. 向助教反馈时带什么

说明操作系统、是否通过 SSH/WSL 使用、卡在安装还是启动阶段，以及去除敏感信息的
错误文字或截图。可以附上：

```bash
command -v opencode
~/.local/bin/opencode --version
```

Linux 还可以附上：

```bash
~/.local/bin/opencode --sage-opencode-doctor
```

**不要发送 API Key、密钥文件内容、完整配置转储或带鉴权头的网络日志。**
默认密钥文件是 `~/.config/sage/qwen38-api-key`，权限为 `0600`；同一 Unix 账户下
的其他程序仍可能读取它，因此共享机器上要使用各自独立的账户。
