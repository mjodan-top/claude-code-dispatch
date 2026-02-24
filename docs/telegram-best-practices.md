# Telegram + Claude Code 最佳实践

## 为什么 Telegram 任务执行效果不如交互界面？

| 方面 | Telegram dispatch | 直接交互界面 |
|------|------------------|------------|
| **执行模式** | 单次提示词 → 单次响应 | 多轮对话、逐步探索 |
| **工具使用** | 有限（一次性执行） | 完整（搜索、读取、分析） |
| **上下文** | 无后续交互 | 可以追问、纠正 |
| **输出** | 截断的摘要 | 完整分析过程 |

## 改进建议

### 1. 分解复杂任务

❌ **不好的提示词**：
```
/cad 分析 auto/parse-pay-pal-report 的调用链，检查 curl 请求，添加超时检查
```

✅ **好的提示词** - 分步骤：
```
/cad 步骤 1: 在 /Users/fanmengni/git/work/ucool-manage 中找到 auto/parse-pay-pal-report 文件，读取其内容
```

然后逐步发送：
```
/cad 步骤 2: 搜索该文件调用的所有 Auto*.php 文件
```

```
/cad 步骤 3: 检查这些 Auto*.php 文件中是否有 curl 请求
```

```
/cad 步骤 4: 为 curl 请求添加超过 24 小时的超时检查
```

### 2. 使用交互式 Agent Teams

启用 Agent Teams 可以让 Claude Code 进行更深入的分析和自我验证：

```
/cad --agent-teams 分析 parse-pay-pal-report 脚本
```

Agent Teams 会：
- 分配一个分析 Agent 搜索代码
- 分配一个验证 Agent 检查结果
- 分配一个测试 Agent 编写测试

### 3. 指定输出格式

在提示词中指定输出格式可以获得更详细的结果：

```
/cad 找到 parse-pay-pal-report 文件，输出格式：
1. 文件路径
2. 主要函数列表
3. 调用的外部文件
4. curl 请求位置（如有）
```

### 4. 使用 `--ali` 进行快速分析

阿里云 Qwen3.5 Plus 模型对代码分析有较好的支持：

```
/cad --ali 分析这段代码的调用链
```

### 5. 利用任务目录输出

Claude Code 的完整输出保存在任务目录中：

```bash
# 查看完整输出
cat ~/git/work/claude-code-dispatch/data/claude-code-results/cad-*/task-output.txt

# 查看最近任务
cat ~/git/work/claude-code-dispatch/data/claude-code-results/$(ls -t ~/git/work/claude-code-dispatch/data/claude-code-results/ | head -1)*/task-output.txt
```

## 实用命令示例

### 代码分析

```
/cad --ali 在 /path/to/project 中找到所有包含 'curl_init' 的 PHP 文件，列出文件路径
```

```
/cad 读取 /path/to/script.php 文件，分析它调用了哪些外部函数和类
```

```
/cad --agent-teams 为 /path/to/api.php 编写单元测试，确保 curl 请求有超时设置
```

### 文件操作

```
/cad 在 /path/to/project 中搜索所有包含 'parse-pay-pal' 的文件
```

```
/cad 检查 /path/to/script 是否有超过 24 小时未更新的文件
```

### 批量任务

```
/cad --agent-teams 检查所有 Auto*.php 文件，找出没有超时设置的 curl 请求
```

## 查看任务状态

```
# 发送 "任务" 查看运行中的任务
# 发送 "历史" 查看已完成的任务
```

## 调试技巧

1. **查看日志**：`tail -f ~/.claude/logs/telegram-bot.log`
2. **查看 Hook 输出**：`cat ~/git/work/claude-code-dispatch/data/claude-code-results/*/hook.log`
3. **手动运行测试**：`~/git/work/claude-code-dispatch/scripts/dispatch.sh -p "测试" -n test -w /path/to/work`

## 注意事项

1. **路径要完整**：使用绝对路径，如 `/Users/fanmengni/git/work/ucool-manage`
2. **任务要具体**：避免模糊的描述，给出明确的文件路径和目标
3. **一次一件事**：复杂任务分解成多个 `/cad` 命令
4. **检查结果**：Telegram 通知只是摘要，查看详细输出需要看任务目录
