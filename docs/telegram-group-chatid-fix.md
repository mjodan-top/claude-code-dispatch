# Telegram 群组 ChatId 负数问题修复

## 问题描述

在 Telegram 群组中使用 `/cad` 命令时，任务派发失败，错误信息：

```
❌ 任务派发失败
异常：The "path" argument must be of type string. Received type number (-5164440338)
```

## 原因分析

Telegram 群组的 `chatId` 是**负数**（例如 `-5164440338`），而私聊用户的 `chatId` 是正数。

当代码将 `chatId` 直接用于文件路径时：

```javascript
const userWorkdir = path.join(os.homedir(), 'git/work/claude-dispatch-tasks', chatId);
// 错误：path.join(..., -5164440338) 会抛出类型错误
```

Node.js 的 `path.join()` 要求所有参数都是字符串，但负数会被识别为数字类型。

## 修复方案

在 `~/.openclaw/telegram-task-bot.js` 的 `dispatchTask` 函数中，将 `chatId` 转换为正数字符串：

```javascript
// Normalize chatId: convert negative group IDs to positive string for file paths
// Telegram group chatIds are negative (e.g., -5164440338)
const normalizedChatId = String(Math.abs(chatId));
```

### 修改位置

```javascript
function dispatchTask(prompt, chatId, options = {}) {
  const { agentTeams = false, workdir = null, aliEnv = false } = options;

  // Normalize chatId: convert negative group IDs to positive string for file paths
  const normalizedChatId = String(Math.abs(chatId));

  const taskId = `cad-${normalizedChatId}-${Date.now()}`;
  const userWorkdir = path.join(os.homedir(), 'git/work/claude-dispatch-tasks', normalizedChatId);

  // 但是发送到 Telegram 时仍使用原始 chatId（负数）
  cmd += ` -g "${chatId}"`;  // 保持原始值，因为 Telegram API 需要负数 ID
}
```

## 验证

修复后，群组聊天可以正常使用 `/cad` 命令：

```
群组（chatId: -5164440338）→ 任务 ID: cad-5164440338-1771924000
                           → 工作目录：~/git/work/claude-dispatch-tasks/5164440338/
                           → 通知发送到：-5164440338（原始 ID）
```

## 相关文件

- `~/.openclaw/telegram-task-bot.js` - 需要应用此修复
- `docs/multi-session-support.md` - 多会话架构文档
