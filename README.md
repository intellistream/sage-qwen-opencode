# IntelliStream SAGE Qwen × OpenCode

一键把课题组的 SAGE `Qwen/Qwen3.8-27B` 服务配置成 OpenCode 中可直接使用的
`sage-qwen` 主 Agent，并设为新会话的默认 Agent 与模型。

> 服务地址：`https://openai.sage.org.ai/v1`  
> 上下文窗口：`262144`  
> 推理强度：`low` / `medium` / `xhigh`（默认 `xhigh`）
> 验证版本：OpenCode V2 `2.0.20`（2026-09-30）

仓库**不包含任何 API Key**。请使用课题组单独发给你的个人 Key，不要互相
转发，也不要把 Key 提交到 Git、粘贴到群聊或写进项目文件。

## 支持的系统

- macOS；
- Linux；
- Windows 用户请使用 WSL。

原生 Windows PowerShell 暂不在验证范围内。

## 一键安装

```bash
git clone https://github.com/intellistream/sage-qwen-opencode.git
cd sage-qwen-opencode
./install.sh
```

脚本会询问个人 API Key。粘贴后按回车；输入过程不显示字符或星号，这是正常
现象。

安装脚本会自动：

1. 缺少 Node.js 时，从 Node.js 官方站下载并校验固定的 LTS 版本；
2. 在用户目录 `~/.local` 安装固定版本的 OpenCode V2；
3. 配置 SAGE Responses provider；
4. 创建 `sage-qwen` 主 Agent，并将它与 SAGE 模型设为新会话默认项；
5. 配置三档推理强度、默认 `xhigh` 和 `262144` 上下文窗口；
6. 把个人 API Key 保存为权限 `0600` 的独立文件；
7. 应用当前 SAGE 工具调用所需的窄兼容修正；
8. 保留原有 OpenCode 配置，并在修改前创建备份。

Node.js、OpenCode 和配置都安装在当前用户目录，不使用系统包管理器，也不需要
`sudo`。已经有 Node.js 20 或更高版本时，脚本会直接使用现有版本。

若当前终端还找不到 `opencode`，关闭并重新打开终端即可。

## 开始使用

进入自己的代码目录并启动：

```bash
cd /你的/项目目录
opencode
```

新会话会默认使用 `sage-qwen` 与 SAGE Qwen 模型。若当前会话已经选过其他
Agent 或模型，请新建会话，或按 **Tab** 选择 `sage-qwen` 并在 `/models` 中选择
`sage-qwen38/Qwen/Qwen3.8-27B`。

也可以直接运行单次任务：

```bash
opencode run --agent sage-qwen \
  --model 'sage-qwen38/Qwen/Qwen3.8-27B#xhigh' \
  "请阅读当前项目并说明目录结构"
```

## 切换推理档位

在 OpenCode 交互界面中按 **Shift+Tab**，可以依次切换：

```text
low → medium → xhigh
```

- `low`：简单问答、小修改，响应更快；
- `medium`：一般代码阅读和开发任务；
- `xhigh`：宽搜索、复杂排障和测试任务，安装后的默认档位。

OpenCode V2 原本把 Shift+Tab 用于切换 Agent；安装脚本会把它改成推理档位
切换，并把 Agent 循环切换移到 **Ctrl+T**。也可以按 **Ctrl+X**，再按 **A**
打开 Agent 列表。

## 验证工具调用

在一个无关紧要的目录中运行：

```bash
opencode run --standalone --auto --agent sage-qwen \
  --model 'sage-qwen38/Qwen/Qwen3.8-27B#xhigh' \
  '请调用 shell 工具执行一次 pwd，然后只返回它输出的绝对路径。'
```

若最后返回当前目录的绝对路径，说明 API Key、provider 路由、Responses 输出和
OpenCode 工具调用闭环均已正常工作。

## 密钥与配置位置

```text
~/.config/sage/qwen38-api-key
~/.config/opencode/opencode.jsonc
~/.config/opencode/agents/sage-qwen.md
~/.config/opencode/cli.json
```

密钥文件仅允许当前用户读写。OpenCode 配置中只有密钥文件的路径，不含密钥
本身。原有配置的备份位于：

```text
~/.local/state/sage-opencode/backups/<时间戳>/
```

## 更换个人 API Key

在仓库目录重新运行：

```bash
./install.sh --replace-key
```

## 常见问题

### `opencode: command not found`

关闭并重新打开终端，或者临时执行：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 鉴权失败 / 401 / 403

运行 `./install.sh --replace-key` 重新录入个人 Key。仍有问题时，只把报错文字
发给助教，**不要发送完整 Key**。

### 能回答问题，但调用工具时报 stream 错误

重新运行 `./install.sh`。脚本会重新安装锁定版本并应用兼容修正。不要单独升级
OpenCode 或 `@opencode/ai`。

### Node.js 下载失败

确认服务器能够访问 `https://nodejs.org`，并且已经安装 `curl` 或 `wget`。
脚本会校验锁定发行包的官方 SHA-256；校验不一致时不会继续安装。

### npm 提示没有权限

脚本安装到用户目录，正常情况下不需要管理员权限。不要加 `sudo`。若仍失败，
把完整报错文字（不含 Key）发给助教。

### 切换回其他模型

在 OpenCode 里按 Tab 选择其他主 Agent，并在 `/models` 中选择其他已经配置的
模型。切换只影响当前会话，不会改写配置；如果希望永久更换默认项，可编辑
`~/.config/opencode/opencode.jsonc` 中的 `default_agent` 和 `model`。安装前的原始
配置也保存在备份目录中。

## 安全排障信息

以下命令不会打印 API Key，可以把输出发给助教：

```bash
opencode --version
opencode debug paths
opencode debug agents
ls -l ~/.config/sage/qwen38-api-key
```

请勿运行或发送 `cat ~/.config/sage/qwen38-api-key` 的输出。

## License

[MIT](LICENSE)
