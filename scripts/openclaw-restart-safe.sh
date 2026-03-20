#!/bin/bash
# ============================================================
# openclaw-restart-safe.sh
# 安全重启 openclaw-gateway.service
# 流程：校验JSON → 注册健康检查 → 重启服务 → 3分钟后自动验证
# 用法：bash openclaw-restart-safe.sh [backup_file]
# ============================================================

CONFIG="$HOME/.openclaw/openclaw.json"
BACKUP_DIR="$HOME/.openclaw/backups"
HEALTH_CHECK="$HOME/.openclaw/workspace/scripts/openclaw-health-check.sh"
HEALTH_LOG="/tmp/openclaw-health-check.log"

# 参数：指定备份文件（可选，默认用最新备份）
BACKUP_FILE="$1"
if [ -z "$BACKUP_FILE" ]; then
  BACKUP_FILE=$(ls -t "$BACKUP_DIR"/openclaw.json.bak.* 2>/dev/null | head -1)
fi

if [ -z "$BACKUP_FILE" ]; then
  echo "❌ 没有找到备份文件，请先执行 backup"
  exit 1
fi

echo "════════════════════════════════════════"
echo "🔄 OpenClaw 安全重启流程"
echo "备份文件：$BACKUP_FILE"
echo "════════════════════════════════════════"

# 步骤1：校验 JSON
echo ""
echo "📋 步骤1：校验 JSON 格式"
if ! jq empty "$CONFIG" 2>/dev/null; then
  echo "❌ JSON 格式错误，禁止重启！请先执行 restore"
  exit 1
fi
echo "✅ JSON 格式合法"

# 步骤2：注册健康检查（在重启前注册，重启后独立运行）
echo ""
echo "📋 步骤2：注册3分钟后健康检查"
nohup bash -c "sleep 180 && bash '$HEALTH_CHECK' '$BACKUP_FILE' >> '$HEALTH_LOG' 2>&1" > /dev/null 2>&1 &
HC_PID=$!
echo "✅ 健康检查已注册（PID: $HC_PID），3分钟后自动验证"
echo "📄 日志：$HEALTH_LOG"

# 步骤3：重启服务（此步骤会中断当前 Agent，健康检查独立运行不受影响）
echo ""
echo "📋 步骤3：重启 openclaw-gateway.service"
echo "⚠️  重启后 Agent 会短暂中断，健康检查将在3分钟后独立执行"
systemctl --user restart openclaw-gateway.service 2>&1
SVC_EXIT=$?

if [ "$SVC_EXIT" -eq 0 ]; then
  echo "✅ 服务重启成功"
else
  echo "⚠️  重启命令返回码：$SVC_EXIT（Agent 重启中断属正常现象）"
fi

echo ""
echo "════════════════════════════════════════"
echo "✅ 重启完成，3分钟后查看健康检查结果："
echo "   cat $HEALTH_LOG"
echo "════════════════════════════════════════"
