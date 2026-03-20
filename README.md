# safe-openclaw-edit — openclaw.json 安全修改工具

> 一句话说明：修改 OpenClaw 配置文件之前，先用这个工具，防止改坏了服务崩溃。

---

## ⚡ 一键安装

在你的 OpenClaw Agent 中发送以下指令：

```
安装这个 skill：https://github.com/mkz0930/safe-openclaw-edit
```

或者手动安装：

```bash
# 克隆到 skills 目录
git clone https://github.com/mkz0930/safe-openclaw-edit.git \
  ~/.openclaw/workspace/skills/safe-openclaw-edit

# 复制脚本到 scripts 目录
cp ~/.openclaw/workspace/skills/safe-openclaw-edit/scripts/* \
  ~/.openclaw/workspace/scripts/

# 添加执行权限
chmod +x ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh \
  ~/.openclaw/workspace/scripts/openclaw-health-check.sh \
  ~/.openclaw/workspace/scripts/openclaw-restart-safe.sh

# 验证安装
bash ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh check
```

安装成功后输出：`✅ JSON 格式合法`

---

## 这个工具解决什么问题？

OpenClaw 的所有设置都存在一个文件里：`~/.openclaw/openclaw.json`

这个文件就像机器的「总控面板」，改错一个字符，整个服务就启动不了——飞书收不到消息，Agent 全部失联。

以前的做法是直接改这个文件，风险很高。这个工具的作用是：
- ✅ 改之前自动存档（备份）
- ✅ 改完自动检查格式有没有出错
- ✅ 改坏了一键恢复，30秒还原

---

## 怎么用？（3种场景）

### 场景1：我想改一个配置

```bash
bash ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh set '.gateway.mode = "public"'
```

脚本会自动做这些事：
1. 问你「官方文档里有这个字段吗？」→ 输入 `yes` 继续
2. 自动备份当前配置
3. 修改指定字段
4. 检查文件格式，有问题自动恢复原样
5. 显示修改后的结果预览

> 💡 不知道字段名怎么写？先看官方文档：
> https://docs.openclaw.ai/gateway/configuration-reference

---

### 场景2：改坏了，我要恢复

```bash
bash ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh restore
```

一条命令，自动还原到上一次备份的状态。

---

### 场景3：我想看看有哪些备份

```bash
bash ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh list-backups
```

会列出所有存档，最多保留7个，旧的自动清理。

---

## 常见问题

**Q：备份存在哪里？**
A：`~/.openclaw/backups/` 文件夹里，文件名带时间戳，比如 `openclaw.json.bak.20260320_165002`。

**Q：`set` 命令里那个奇怪的写法是什么？**
A：那是 `jq` 的语法，用来精准修改 JSON 文件里的某一个字段，不会动其他内容。比如 `.gateway.mode = "public"` 就是把 gateway 下面的 mode 字段改成 public。

**Q：改完要重启吗？**
A：要看改了什么：
- 改了 `feishu`、`gateway`、`agents` 相关的字段 → **需要重启，而且要先告诉 Horse**
- 改了环境变量或小配置 → 通常不需要

重启命令：`clawd restart`

**Q：格式校验失败是什么意思？**
A：JSON 文件有严格的格式要求，少一个引号或多一个逗号都不行。校验失败说明改出了语法错误，脚本会自动帮你恢复备份，不用担心。

---

## 全部命令一览

| 命令 | 作用 |
|------|------|
| `set '<字段表达式>'` | 安全修改一个字段（最常用）|
| `restore` | 还原最近一次备份 |
| `check` | 检查当前文件格式是否正确 |
| `backup` | 手动存一个档 |
| `list-backups` | 查看所有备份 |
| `docs` | 显示官方文档链接 |

所有命令都在这个脚本前面加：
```
bash ~/.openclaw/workspace/scripts/safe-edit-openclaw.sh
```

---

## 官方配置文档

改配置前，先去这里查字段名和允许的值：
https://docs.openclaw.ai/gateway/configuration-reference
