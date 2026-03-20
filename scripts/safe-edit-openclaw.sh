#!/bin/bash
# ============================================================
# safe-edit-openclaw.sh
# openclaw.json 安全修改脚本（自动查阅官方文档验证字段）
# 使用方式：
#   bash safe-edit-openclaw.sh check          # 仅校验当前文件
#   bash safe-edit-openclaw.sh backup         # 仅备份
#   bash safe-edit-openclaw.sh set <jq_expr>  # 安全修改某字段（自动验证）
#   bash safe-edit-openclaw.sh restore        # 还原最近一次备份
#   bash safe-edit-openclaw.sh list-backups   # 列出所有备份
#   bash safe-edit-openclaw.sh docs           # 显示官方文档链接
# ============================================================

CONFIG="$HOME/.openclaw/openclaw.json"
BACKUP_DIR="$HOME/.openclaw/backups"
DOCS_URL="https://docs.openclaw.ai/gateway/configuration-reference"
DOCS_CACHE="/tmp/openclaw_docs_cache.txt"
MAX_BACKUPS=7

mkdir -p "$BACKUP_DIR"

# ── 工具函数 ──────────────────────────────────────────────

check_json() {
  if jq empty "$CONFIG" 2>/dev/null; then
    echo "✅ JSON 格式合法"
    return 0
  else
    echo "❌ JSON 格式错误！"
    return 1
  fi
}

do_backup() {
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local dest="$BACKUP_DIR/openclaw.json.bak.$ts"
  cp "$CONFIG" "$dest"
  echo "✅ 已备份：$dest"

  local count
  count=$(ls "$BACKUP_DIR"/openclaw.json.bak.* 2>/dev/null | wc -l)
  if [ "$count" -gt "$MAX_BACKUPS" ]; then
    ls -t "$BACKUP_DIR"/openclaw.json.bak.* | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
    echo "🧹 已清理旧备份，保留最近 $MAX_BACKUPS 份"
  fi
}

do_restore() {
  local latest
  latest=$(ls -t "$BACKUP_DIR"/openclaw.json.bak.* 2>/dev/null | head -1)
  if [ -z "$latest" ]; then
    echo "❌ 没有找到备份文件"
    exit 1
  fi
  cp "$latest" "$CONFIG"
  echo "✅ 已还原：$latest"
  check_json
}

# 从 jq 表达式中提取顶层字段路径，例如 '.gateway.mode = "x"' → 'gateway'
extract_field_path() {
  local expr="$1"
  # 提取 .a.b.c 格式的字段路径
  echo "$expr" | grep -oP '\.([a-zA-Z_][a-zA-Z0-9_.\-]*)' | head -1 | sed 's/^\.//' | cut -d'.' -f1
}

# 获取官方文档内容（带缓存，10分钟内不重复请求）
fetch_docs() {
  # 检查缓存是否新鲜（10分钟内）
  if [ -f "$DOCS_CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$DOCS_CACHE" 2>/dev/null || echo 0) )) -lt 600 ]; then
    cat "$DOCS_CACHE"
    return 0
  fi

  echo "🌐 正在获取官方文档..." >&2
  local content
  content=$(curl -s --max-time 10 "$DOCS_URL" 2>/dev/null)
  if [ -z "$content" ]; then
    echo "⚠️  无法连接官方文档，跳过自动验证" >&2
    return 1
  fi
  echo "$content" > "$DOCS_CACHE"
  echo "$content"
}

# 验证字段是否在官方文档中存在
verify_field_in_docs() {
  local field="$1"
  local full_expr="$2"

  echo ""
  echo "════════════════════════════════════════"
  echo "📋 步骤1：自动查阅官方文档验证字段"
  echo "修改表达式：$full_expr"
  echo "提取字段：$field"

  local docs
  docs=$(fetch_docs)
  if [ $? -ne 0 ]; then
    echo "⚠️  跳过文档验证，请手动确认字段：$DOCS_URL"
    echo "════════════════════════════════════════"
    return 0
  fi

  # 在文档中搜索字段名（不区分大小写）
  if echo "$docs" | grep -qi "$field"; then
    echo "✅ 字段 '$field' 在官方文档中找到，验证通过"
    echo "════════════════════════════════════════"
    return 0
  else
    echo "❌ 警告：字段 '$field' 在官方文档中未找到！"
    echo "   官方文档：$DOCS_URL"
    echo "════════════════════════════════════════"
    echo ""
    read -r -p "⚠️  字段未在文档中找到，确定要继续修改吗？(yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
      echo "❌ 已取消。请先确认字段名称是否正确。"
      exit 1
    fi
    echo "⚠️  用户强制确认，继续执行..."
  fi
}

do_set() {
  local expr="$1"
  if [ -z "$expr" ]; then
    echo "用法：$0 set '<jq表达式>'"
    echo "示例：$0 set '.gateway.mode = \"public\"'"
    exit 1
  fi

  # 提取字段名
  local field
  field=$(extract_field_path "$expr")

  # 步骤1：自动查阅官方文档验证字段
  verify_field_in_docs "$field" "$expr"

  # 步骤2：备份
  echo ""
  echo "📋 步骤2：备份当前配置"
  do_backup

  # 步骤3：执行修改
  echo ""
  echo "📋 步骤3：执行修改"
  local tmp
  tmp=$(mktemp)
  if jq "$expr" "$CONFIG" > "$tmp" 2>&1; then
    mv "$tmp" "$CONFIG"
    echo "✅ 修改已写入"
  else
    echo "❌ jq 表达式执行失败："
    cat "$tmp"
    rm -f "$tmp"
    exit 1
  fi

  # 步骤4：校验 JSON 格式
  echo ""
  echo "📋 步骤4：校验 JSON 格式"
  if ! check_json; then
    echo "⚠️  格式错误，正在自动还原备份..."
    do_restore
    exit 1
  fi

  # 步骤5：预览修改结果
  echo ""
  echo "📋 步骤5：修改结果预览"
  jq "$expr" /dev/null 2>/dev/null || true
  jq ".$(echo $field)" "$CONFIG" 2>/dev/null || jq '.' "$CONFIG" | head -30

  echo ""
  echo "════════════════════════════════════════"
  echo "✅ 修改完成！如需重启服务请手动执行："
  echo "   clawd restart"
  echo "⚠️  涉及 feishu/gateway/agents 核心字段时，请通知 Horse 确认后再重启。"
  echo "════════════════════════════════════════"

  # 步骤6：注册3分钟后的健康检查定时任务
  echo ""
  echo "📋 步骤6：注册健康检查（3分钟后自动验证，失败则自动回滚）"
  local latest_backup
  latest_backup=$(ls -t "$BACKUP_DIR"/openclaw.json.bak.* 2>/dev/null | head -1)
  local check_script="$HOME/.openclaw/workspace/scripts/openclaw-health-check.sh"
  local check_time
  check_time=$(date -d '+3 minutes' '+%H:%M' 2>/dev/null || date -v+3M '+%H:%M')

  # 写入一次性 at 任务（若 at 不可用则用 sleep 后台任务）
  if command -v at &>/dev/null; then
    echo "bash $check_script '$latest_backup' >> /tmp/openclaw-health-check.log 2>&1" | at now + 3 minutes 2>/dev/null
    echo "✅ 已注册 at 定时任务，将在 $check_time 执行健康检查"
  else
    # 降级：后台 sleep 180s 后执行
    nohup bash -c "sleep 180 && bash '$check_script' '$latest_backup' >> /tmp/openclaw-health-check.log 2>&1" &>/dev/null &
    echo "✅ 已注册后台健康检查任务（PID $!），将在3分钟后执行"
  fi
  echo "📄 日志：/tmp/openclaw-health-check.log"
  echo "════════════════════════════════════════"
}

do_docs() {
  echo "📖 OpenClaw 配置官方文档："
  echo "   完整参考：https://docs.openclaw.ai/gateway/configuration-reference"
  echo "   配置示例：https://docs.openclaw.ai/gateway/configuration-examples"
  echo "   主配置页：https://docs.openclaw.ai/gateway/configuration"
}

list_backups() {
  echo "📁 当前备份列表："
  ls -lh "$BACKUP_DIR"/openclaw.json.bak.* 2>/dev/null || echo "（暂无备份）"
}

# ── 主入口 ──────────────────────────────────────────────

case "$1" in
  check)
    check_json
    ;;
  backup)
    do_backup
    ;;
  set)
    do_set "$2"
    ;;
  restore)
    do_restore
    ;;
  list-backups)
    list_backups
    ;;
  docs)
    do_docs
    ;;
  *)
    echo "OpenClaw 配置安全修改工具"
    echo ""
    echo "用法："
    echo "  bash safe-edit-openclaw.sh check            # 校验当前 JSON 格式"
    echo "  bash safe-edit-openclaw.sh backup           # 手动备份"
    echo "  bash safe-edit-openclaw.sh set '<jq表达式>' # 安全修改字段（自动验证+备份+校验）"
    echo "  bash safe-edit-openclaw.sh restore          # 还原最近备份"
    echo "  bash safe-edit-openclaw.sh list-backups     # 列出所有备份"
    echo "  bash safe-edit-openclaw.sh docs             # 查看官方文档链接"
    echo ""
    echo "官方文档：https://docs.openclaw.ai/gateway/configuration-reference"
    ;;
esac
