---
name: safe-openclaw-edit
description: >
  Safe protocol for modifying ~/.openclaw/openclaw.json.
  Use when anyone mentions any of these:
  openclaw.json, 修改配置, 改配置, 配置文件, 配置修改, config修改,
  gateway配置, feishu配置, agents配置, 模型配置, channel配置,
  openclaw配置, 改参数, 修改参数, 配置损坏, 配置恢复, 回滚配置,
  json格式错误, 配置备份, backup config, restore config,
  jq修改, 字段修改, 配置字段
---

# Safe openclaw.json Edit Protocol

修改 `~/.openclaw/openclaw.json` 的5步安全协议，防止配置损坏导致服务崩溃。

## 前置要求
- `jq` 已安装（`jq --version` 验证）
- 脚本已存在：`~/.openclaw/workspace/scripts/safe-edit-openclaw.sh`

## 核心规则

**禁止**直接用 `write` 工具全量覆盖 `openclaw.json`。  
**必须**通过脚本执行所有修改。

## 5步强制流程

### 步骤1：查阅官方文档确认字段存在
```
https://docs.openclaw.ai/gateway/configuration-reference
```
- 确认字段名称、类型、允许值
- 未在文档中找到的字段，禁止写入

### 步骤2：自动备份
```bash
bash ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh backup
# 备份至 ~/.openclaw/backups/openclaw.json.bak.YYYYMMDD_HHMMSS
# 自动保留最近7份
```

### 步骤3：jq 精准修改目标字段
```bash
bash ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh set '.gateway.mode = "public"'
# 脚本会：提示文档确认 → 备份 → jq修改 → 格式校验 → 预览结果
```

### 步骤4：JSON 格式校验（脚本自动执行）
```bash
bash ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh check
# 校验失败 → 自动还原最近备份
```

### 步骤5：重启确认门
- 涉及 `feishu` / `gateway` / `agents` 核心字段 → **必须通知 Horse 确认后再重启**
- 非核心字段（env变量、skill等）→ 可静默生效

## 命令速查

```bash
# 校验当前 JSON 格式
bash safe-edit-openclaw.sh check

# 手动备份
bash safe-edit-openclaw.sh backup

# 安全修改字段（含备份+校验+文档确认）
bash safe-edit-openclaw.sh set '<jq表达式>'

# 还原最近备份
bash safe-edit-openclaw.sh restore

# 列出所有备份
bash safe-edit-openclaw.sh list-backups

# 查看官方文档链接
bash safe-edit-openclaw.sh docs
```

## 常见修改示例

| 需求 | jq 表达式 |
|------|-----------|
| 开启公网访问 | `.gateway.mode = "public"` |
| 修改 gateway bind | `.gateway.bind = "0.0.0.0"` |
| 添加环境变量 | `.agents.defaults.env.MY_KEY = "value"` |
| 修改默认模型 | `.agents.defaults.model = "claude-3-5-sonnet"` |

## 故障恢复

```bash
# 还原最近一次备份
bash safe-edit-openclaw.sh restore

# 查看备份列表，选择特定版本还原
bash safe-edit-openclaw.sh list-backups
cp ~/.openclaw/backups/openclaw.json.bak.20260320_165002 ~/.openclaw/openclaw.json
```

## 根本原因（为什么需要此协议）

| 风险 | 后果 |
|------|------|
| `write` 全量覆盖 | 任何疏漏导致整个配置丢失 |
| 无格式校验 | 无效 JSON 导致服务启动失败 |
| 无备份机制 | 出错无法回滚 |
| 写入未知字段 | OpenClaw 拒绝启动 |
| 直接重启核心配置 | 飞书/消息通道中断 |

## 官方文档

- 配置参考：https://docs.openclaw.ai/gateway/configuration-reference
- 配置示例：https://docs.openclaw.ai/gateway/configuration-examples
- 主配置页：https://docs.openclaw.ai/gateway/configuration
