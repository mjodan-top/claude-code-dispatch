# 多 Telegram 会话支持方案

## 架构现状 (已实现 ✅)

### 已有多会话支持

当前代码**已经支持**多个 Telegram 用户/群组同时使用：

| 组件 | 多会话支持 | 实现方式 |
|------|-----------|---------|
| **Telegram Bot** | ✅ | 每个消息的 `chatId` 被提取并传递 |
| **Dispatch 脚本** | ✅ | `-g` 参数保存 chatId 到 meta |
| **通知 Hook** | ✅ | 从 meta 文件读取 `telegram_group` |
| **任务隔离** | ✅ | 每个任务独立目录 `task-{chatId}-{timestamp}/` |
| **锁文件** | ✅ | 任务级锁 `.hook-lock` 在每个任务目录 |

### 多会话工作流程

```
用户 A (chatId: 123) ──┐
                       ├──→ /cad 任务 A
用户 B (chatId: 456) ──┘
                       │
                       ▼
            dispatch.sh -g "123" -n "cad-123-1234567"
                       │
                       ▼
            创建工作目录：~/git/work/claude-dispatch-tasks/123/cad-123-1234567/
                       │
                       ▼
            写入 task-meta.json {telegram_group: "123", ...}
                       │
                       ▼
            Claude Code 执行 (并行，互不干扰)
                       │
                       ▼
            notify-hook.sh 查找任务目录
                       │
                       ▼
            读取 meta 中的 telegram_group
                       │
                       ▼
            发送到 chatId: 123 ✅
```

## 用户隔离

### 工作目录隔离

每个 Telegram 用户有独立的工作目录：

```
~/git/work/claude-dispatch-tasks/
├── 123/                    # 用户 123 的任务
│   ├── cad-123-1111/
│   └── cad-123-2222/
├── 456/                    # 用户 456 的任务
│   └── cad-456-3333/
└── 789/                    # 用户 789 的任务
    └── cad-789-4444/
```

### 结果文件隔离

```
data/claude-code-results/
├── cad-123-1111/
│   ├── task-meta.json      # {telegram_group: "123"}
│   ├── task-output.txt
│   └── .hook-lock
├── cad-123-2222/
│   └── ...
└── cad-456-3333/
    └── ...                 # 完全隔离
```

## 使用方法

### 多用户同时使用

多个用户可以同时发送命令，互不干扰：

```
# 用户 A 发送
/cad 用 Python 写个计算器

# 用户 B 同时发送
/cad --ali 用 FastAPI 写 API

# 两个任务并行执行，各自收到各自的通知
```

### 查看任务状态

```
# 查询当前运行任务
发送 "任务"

# 查询历史任务
发送 "历史"
```

## 限制

| 限制 | 说明 | 解决方案 |
|------|------|---------|
| **共享 Claude Code 进程** | 同一时间只能运行一个任务 | 使用 `--agent-teams` 并行 |
| **无用户认证** | 任何人都可以使用 bot | 未来添加 `/register` 命令 |
| **无配额管理** | 没有使用限制 | 未来添加 quota 系统 |
| **无任务队列** | 任务立即执行 | 未来添加 Redis 队列 |

## 实现细节

### CLAUDECODE 环境变量处理

为了允许从 Telegram Bot  dispatch 任务，`dispatch.sh` 会 unset `CLAUDECODE` 环境变量：

```bash
# dispatch.sh 第 209-211 行
# Unset CLAUDECODE to allow running from within Claude Code
export CLAUDECODE=""
```

这确保了即使在 Claude Code 会话内运行 bot，也能正常 dispatch 新的 Claude Code 任务。

### 任务 ID 格式

```javascript
// telegram-task-bot.js 第 331 行
const taskId = `cad-${chatId}-${Date.now()}`;
```

任务 ID 包含 chatId，确保每个用户的任务都有唯一标识。

### 工作目录隔离

```javascript
// telegram-task-bot.js 第 343 行
const userWorkdir = path.join(os.homedir(), 'git/work/claude-dispatch-tasks', chatId);
```

每个用户有独立的工作目录，避免文件冲突。

## 未来扩展

### 阶段 2: 用户管理

添加命令：
- `/register` - 注册账户
- `/status` - 查看我的任务
- `/quota` - 查看使用配额

### 阶段 3: 任务队列

```
Telegram Bot → Redis 队列 → Worker 池 → Claude Code
```

### 阶段 4: 权限控制

```json
{
  "users": {
    "123456789": {
      "name": "User A",
      "enabled": true,
      "quota": {"daily": 10, "used": 3},
      "allowed_features": ["ali", "agent-teams"]
    }
  }
}
```
