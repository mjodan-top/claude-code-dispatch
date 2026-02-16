# Claude Code Dispatch 🚀

**一键派发开发任务给 Claude Code，完成后自动通知。** 零轮询，零 token 浪费。

把编码任务丢给 Claude Code → 它在后台自动构建 → 完成后你收到一条 Telegram 通知，包含测试结果、文件列表、耗时等详细信息。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> 📺 **YouTube**: [AISuperDomain](https://www.youtube.com/@AIsuperdomain) — AI 编程教程和演示

## ✨ 特性

- 🔥 **Fire-and-forget** — 派发任务后走人，完成时自动通知你
- 🤖 **Agent Teams** — 自动拆分任务，Dev Agent 和 Testing Agent 并行工作
- 📱 **Telegram 通知** — 丰富的完成报告（测试结果、文件列表、耗时、Agent 分工）
- 🔄 **三重回调保障** — Telegram 消息 → webhook 唤醒 → 心跳兜底
- 🎯 **自动回调检测** — 在 workspace 放一个 `dispatch-callback.json`，无需传参
- 🛡️ **实战验证** — 经过 100+ 次真实任务考验，所有边界情况都已处理

## 📐 架构

```
dispatch.sh
  → 写入 task-meta.json（任务元数据）
  → 通过 claude_code_run.py（PTY wrapper）启动 Claude Code
  → [Agent Teams 模式: Lead 拆分任务 → Dev + Testing Agent 并行执行]
  → Claude Code 完成 → Stop Hook 自动触发
    → notify-hook.sh 读取 meta + output
    → 写入 latest.json
    → 发送 Telegram 通知
    → 通过 webhook 唤醒 AGI
    → 写入 pending-wake.json（心跳兜底）
```

## 🚀 快速开始

### 1. 安装

```bash
git clone https://github.com/win4r/claude-code-dispatch.git
cd claude-code-dispatch
chmod +x scripts/*.sh scripts/*.py
```

### 2. 配置 Hook

把 hook 脚本路径写入 Claude Code 配置：

```bash
# 编辑 ~/.claude/settings.json
# 完整配置见 docs/hook-setup.md
```

### 3. 派发任务

```bash
# 简单任务
bash scripts/dispatch.sh \
  -p "用 Click 构建一个 Python CLI 计算器" \
  -n "calc-cli" \
  -w /path/to/project \
  --permission-mode bypassPermissions

# 带 Telegram 通知
bash scripts/dispatch.sh \
  -p "用 FastAPI 构建一个 REST API" \
  -n "my-api" \
  -g "<你的Telegram群组ID>" \
  -w /path/to/project \
  --permission-mode bypassPermissions

# Agent Teams（并行开发+测试）
bash scripts/dispatch.sh \
  -p "构建一个天气 CLI 工具：支持 API 查询、缓存、彩色输出" \
  -n "weather-cli" \
  -g "<你的Telegram群组ID>" \
  --agent-teams \
  --permission-mode bypassPermissions \
  -w /path/to/project
```

## 📋 参数说明

| 参数 | 缩写 | 必填 | 说明 |
|------|------|------|------|
| `--prompt` | `-p` | ✅ | 任务描述 |
| `--name` | `-n` | | 任务名（用于追踪） |
| `--group` | `-g` | | Telegram 群组 ID（接收通知） |
| `--workdir` | `-w` | | 工作目录（默认：当前目录） |
| `--agent-teams` | | | 启用 Agent Teams（并行开发+测试） |
| `--teammate-mode` | | | 显示模式：`auto` / `in-process` / `tmux` |
| `--permission-mode` | | | `bypassPermissions` / `plan` / `acceptEdits` |
| `--allowed-tools` | | | 工具白名单（如 `"Read,Bash"`） |
| `--model` | | | 模型覆盖 |
| `--callback-group` | | | 回调 Telegram 群组 |
| `--callback-dm` | | | 回调 Telegram 用户 ID（DM） |
| `--callback-account` | | | 回调 bot 账号名 |

## 🤖 Agent Teams

启用 `--agent-teams` 后，dispatch 脚本会自动注入指令让 Lead Agent：

1. 将任务拆分为多个并行的 sub-agent
2. 分配一个专门的 **Testing Agent**（写测试、跑测试、检查边界情况）
3. Testing Agent 和 Dev Agent **并行工作**
4. 所有测试通过后才算任务完成

每个 sub-agent 是**独立的 Claude Code 进程**，共享同一个文件系统。

### 实战成果

| 项目 | Agent 数量 | 测试 | 耗时 |
|------|-----------|------|------|
| 天气 CLI | 4 (api, formatter, testing, lead) | 42 通过 | 5m34s |
| 计算器 CLI | 3 (dev, testing, lead) | 18 通过 | 3m12s |
| REST API | 4 (routes, db, testing, lead) | 31 通过 | 7m45s |

## 🔄 自动回调检测

在 workspace 根目录放一个 `dispatch-callback.json`：

**DM 机器人：**
```json
{
  "type": "dm",
  "dm": "<Telegram用户ID>",
  "account": "<bot账号名>"
}
```

**群组 Agent：**
```json
{
  "type": "group",
  "group": "<Telegram群组ID>"
}
```

**仅 webhook 唤醒：**
```json
{
  "type": "wake"
}
```

然后直接 dispatch 即可 —— 自动检测回调配置，无需传参。

## 📁 结果文件

所有结果存储在 `data/claude-code-results/`：

| 文件 | 内容 |
|------|------|
| `latest.json` | 完整结果（输出、任务名、群组、时间戳） |
| `task-meta.json` | 任务元数据（prompt、工作目录、状态、耗时） |
| `task-output.txt` | Claude Code 原始输出 |
| `pending-wake.json` | 心跳兜底通知 |
| `hook.log` | Hook 执行日志 |

## ⚠️ 注意事项

1. **必须使用 PTY wrapper** — 直接 `claude -p` 在非 TTY 环境会挂起。`claude_code_run.py` 通过 `script(1)` 解决了这个问题。
2. **Hook 对所有 Claude Code 运行都会触发** — 不只是 dispatch 的任务。Hook 会校验 meta 文件时效（<2小时）避免误发旧通知。
3. **Hook 会触发两次** — Stop + SessionEnd。内置 `.hook-lock` 去重（30秒窗口）。
4. **tee 管道竞态** — Hook 等待 1 秒让 tee 管道刷新完再读取输出。
5. **务必设置 `-w`** — 不指定工作目录可能跑在错误路径下。

## 🔧 与 OpenClaw 集成

本工具可独立使用，但为 [OpenClaw](https://github.com/openclaw/openclaw) 深度设计：

- 通过 `openclaw message send` 发送 Telegram 通知
- 通过 `/hooks/wake` webhook 唤醒 AGI
- 通过 OpenClaw 的 Agent 系统实现多 Agent 协作

## 📖 文档

- [Hook 配置指南](docs/hook-setup.md)
- [Agent Teams Prompt 指南](docs/prompt-guide.md)

## 📺 更多内容

- **YouTube**: [@AISuperDomain](https://www.youtube.com/@AIsuperdomain)
- **OpenClaw**: [openclaw.ai](https://docs.openclaw.ai)

## 开源协议

[MIT](LICENSE)
