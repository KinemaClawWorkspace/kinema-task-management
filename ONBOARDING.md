# Kinema's Task Management Onboarding

> 本文档指导 AI Agent 完成首次环境配置。按顺序执行，遇到问题时参考 Troubleshooting。

## Prerequisites | 前置条件

- OpenClaw 已运行，Agent 可执行文件系统操作
- OpenClaw cron 功能可用
- Bash 可用

## Step 1: 创建目录结构

### 检测

```bash
ls -d ~/.openclaw/workspace/kinema-tasks/active ~/.openclaw/workspace/kinema-tasks/archived ~/.openclaw/workspace/kinema-tasks/snapshots 2>&1
```

期望输出：三个目录路径（无错误）。

### 安装

```bash
mkdir -p ~/.openclaw/workspace/kinema-tasks/{active,archived,snapshots}
```

### 验证

```bash
ls -d ~/.openclaw/workspace/kinema-tasks/{active,archived,snapshots}
```

期望输出：三个目录路径。

## Step 2: 安装辅助脚本

### 检测

```bash
ls ~/.openclaw/workspace/skills/kinema-task-management/scripts/
```

期望输出：`next-id.sh` `create-task.sh` `archive-task.sh` `snapshot.sh` `report.sh`

### 安装

辅助脚本随 skill 一起安装（`clawhub install` 或手动复制到 `skills/kinema-task-management/scripts/`）。

确保脚本可执行：

```bash
chmod +x ~/.openclaw/workspace/skills/kinema-task-management/scripts/*.sh
```

### 验证

```bash
~/.openclaw/workspace/skills/kinema-task-management/scripts/next-id.sh
```

期望输出：`TASK-00001`

## Step 3: 配置 Cron 任务

### 检测

```bash
openclaw cron list 2>&1 | grep -i "kinema-tasks"
```

期望输出：包含三条 cron 记录（archive-check、daily-report、write-snapshot）。

### 安装

**依次创建以下三个 cron 任务：**

#### 3.1 归档检查（每天 09:00 北京时间）

```bash
openclaw cron add \
  --name "kinema-tasks-archive-check" \
  --cron "0 9 * * *" \
  --tz Asia/Shanghai \
  --session isolated \
  --announce \
  --timeout-seconds 120 \
  --message "执行 KinemaTasks 归档检查：读取 ~/.openclaw/workspace/kinema-task-management/SKILL.md 了解规范。扫描 ~/.openclaw/workspace/kinema-tasks/active/ 中所有 TASK-*.md 文件，检查 Metadata 表中'状态'字段。如果状态为 Done 或 Cancelled：1) 更新该文件的'最后更新'为今天日期（YYYY-MM-DD）2) 在 Changelog 追加记录（如 'YYYY-MM-DD 状态变更: Done → 移入 archived'）3) 将文件从 active/ 移动到 archived/。完成后输出归档摘要，如无需归档则输出'无待归档任务'。"
```

#### 3.2 每日早报（每天 09:01 北京时间）

```bash
openclaw cron add \
  --name "kinema-tasks-daily-report" \
  --cron "1 9 * * *" \
  --tz Asia/Shanghai \
  --session isolated \
  --announce \
  --timeout-seconds 180 \
  --message "执行 KinemaTasks 每日早报推送。读取 ~/.openclaw/workspace/kinema-task-management/SKILL.md 了解完整规范。1) 读取 ~/.openclaw/workspace/kinema-tasks/snapshots/ 中最近一次快照文件（按文件名日期倒序取最新的）2) 扫描 ~/.openclaw/workspace/kinema-tasks/active/ 所有 TASK-*.md 读取 Metadata（标题、状态、优先级、领域、截止日期）3) 对比最近快照与当前 active 状态生成 diff（新增、状态变更、字段变更、取消）4) 扫描 ~/.openclaw/workspace/kinema-tasks/archived/ 获取最近 5 条状态为 Done 的任务 5) 按 SKILL.md 中的推送格式生成完整报告。注意：如果没有最近快照则跳过 diff 部分。日期使用北京时间。"
```

#### 3.3 写入快照（每天 09:02 北京时间）

```bash
openclaw cron add \
  --name "kinema-tasks-write-snapshot" \
  --cron "2 9 * * *" \
  --tz Asia/Shanghai \
  --session isolated \
  --timeout-seconds 120 \
  --message "执行 KinemaTasks 快照写入：读取 ~/.openclaw/workspace/kinema-task-management/SKILL.md 了解规范。1) 扫描 ~/.openclaw/workspace/kinema-tasks/active/ 中所有 TASK-*.md 文件 2) 读取每个文件的 Metadata（标题、状态、优先级、领域、截止日期）3) 按 SKILL.md 中的快照格式生成 markdown 4) 写入 ~/.openclaw/workspace/kinema-tasks/snapshots/YYYY-MM-DD.md（使用今天北京时间日期）。输出写入确认和任务摘要统计。"
```

> **注意**：
> - 三个 cron 使用 `--session isolated` 在独立 session 中运行，避免污染主 session 历史
> - `--announce` 将结果推送到对话通道
> - `--tz Asia/Shanghai` 直接使用北京时间（09:00），无需手动计算 UTC
> - 三个 cron 间隔 1 分钟（09:00 → 09:01 → 09:02），确保顺序执行

### 验证

```bash
openclaw cron list 2>&1 | grep -i "kinema-tasks"
```

期望输出：显示三条 cron 记录，标签分别为 `kinema-tasks-archive-check`、`kinema-tasks-daily-report`、`kinema-tasks-write-snapshot`。

## Step 4: 最终验证

```bash
# 检查目录
ls -la ~/.openclaw/workspace/kinema-tasks/

# 检查脚本
~/.openclaw/workspace/skills/kinema-task-management/scripts/next-id.sh

# 检查 cron
openclaw cron list 2>&1 | grep "kinema-tasks"
```

全部通过即可开始使用。

## Troubleshooting | 故障排除

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `next-id.sh: No such file` | Skill 未安装或路径错误 | 确认 skill 已安装到 `~/.openclaw/workspace/skills/kinema-task-management/` |
| `openclaw cron: command not found` | OpenClaw 版本不支持 cron | 升级 OpenClaw 到支持 cron 的版本 |
| `Permission denied` 脚本 | 脚本无执行权限 | `chmod +x scripts/*.sh` |
| cron 未执行 | cron 服务未启动 | 检查 OpenClaw gateway 状态：`openclaw gateway status`，检查 cron 列表：`openclaw cron list` |
| 目录不存在 | Step 1 未执行 | 重新执行 `mkdir -p ~/.openclaw/workspace/kinema-tasks/{active,archived,snapshots}` |
| 推送未到达对话 | 缺少 `--announce` | 重新创建 cron 任务，确保包含 `--announce` 参数 |
| cron 参数格式错误 | 版本差异 | 运行 `openclaw cron add --help` 确认当前版本支持的参数 |
