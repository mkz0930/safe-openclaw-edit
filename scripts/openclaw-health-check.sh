#!/bin/bash
# ============================================================
# openclaw-health-check.sh
# 修改 openclaw.json 后的健康验证脚本
# 用法：bash openclaw-health-check.sh <backup_file>
# 若验证失败，自动回滚到指定备份文件
# ============================================================

BACKUP_FILE="$1"
CONFIG="$HOME/.openclaw/openclaw.json"
LOG_DIR="$HOME/.openclaw/logs"
FEISHU_SCRIPT="$HOME/.openclaw/workspace/scripts/send-feishu.sh"
HORSE_ID="ou_2cf905e306a287382df58f01e8b6799e"

send_alert() {
  local msg="$1"
  echo "[health-check] $msg"
  # 通过 clawd 发飞书消息给 Horse
  if command -v clawd &>/dev/null; then
    clawd message --to "$HORSE_ID" --text "$msg" 2>/dev/null || true
  fi
}

rollback() {
  echo "[health-check] ⚠️  开始自动回滚..."
  if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$CONFIG"
    echo "[health-check] ✅ 已回滚至：$BACKUP_FILE"
    send_alert "⚠️ openclaw.json 修改后健康检查失败，已自动回滚至备份：$(basename $BACKUP_FILE)\n请检查配置后重新修改。"
  else
    echo "[health-check] ❌ 备份文件不存在，无法回滚：$BACKUP_FILE"
    send_alert "❌ openclaw.json 健康检查失败且备份文件丢失，请立即手动检查！"
  fi
}

echo "[health-check] 开始健康检查 ($(date '+%Y-%m-%d %H:%M:%S'))"
echo "[health-check] 备份文件：$BACKUP_FILE"

FAILED=0
REASONS=()

# ── 检查1：systemd 服务是否在运行 ──────────────────────
echo "[health-check] 检查1：OpenClaw 服务状态"
SVC_STATUS=$(systemctl --user is-active openclaw-gateway.service 2>/dev/null)
if [ "$SVC_STATUS" = "active" ]; then
  echo "[health-check] ✅ openclaw-gateway.service 运行正常"
else
  # 降级：检查进程
  if pgrep -f "openclaw\|clawd\|nanobot" > /dev/null 2>&1; then
    echo "[health-check] ✅ OpenClaw 相关进程运行正常"
  else
    echo "[health-check] ❌ openclaw-gateway.service 状态：$SVC_STATUS"
    FAILED=1
    REASONS+=("服务未运行(${SVC_STATUS})")
  fi
fi

# ── 检查2：command-log.txt 近期是否有活跃记录 ──────────────────────
echo "[health-check] 检查2：运行日志活跃检查"
CMD_LOG="$LOG_DIR/command-log.txt"
if [ -f "$CMD_LOG" ]; then
  # 检查最后修改时间是否在10分钟内
  LAST_MOD=$(( $(date +%s) - $(stat -c %Y "$CMD_LOG") ))
  if [ "$LAST_MOD" -lt 600 ]; then
    echo "[health-check] ✅ command-log.txt 活跃（${LAST_MOD}秒前更新）"
    # 检查近期日志中是否有严重错误
    RECENT_ERRORS=$(tail -100 "$CMD_LOG" | grep -i "fatal\|crash\|ECONNREFUSED\|unhandled\|SyntaxError" | tail -5)
    if [ -n "$RECENT_ERRORS" ]; then
      echo "[health-check] ❌ 日志发现严重错误："
      echo "$RECENT_ERRORS"
      FAILED=1
      REASONS+=("日志严重错误: $(echo $RECENT_ERRORS | head -c 100)")
    else
      echo "[health-check] ✅ 近期日志无严重错误"
    fi
  else
    echo "[health-check] ❌ command-log.txt 超过10分钟未更新（${LAST_MOD}秒前），服务可能挂起"
    FAILED=1
    REASONS+=("日志超时未更新(${LAST_MOD}s)")
  fi
else
  echo "[health-check] ⚠️  未找到 command-log.txt，跳过日志检查"
fi

# ── 检查3：JSON 格式是否合法 ──────────────────────
echo "[health-check] 检查3：JSON 格式"
if jq empty "$CONFIG" 2>/dev/null; then
  echo "[health-check] ✅ JSON 格式合法"
else
  echo "[health-check] ❌ JSON 格式错误"
  FAILED=1
  REASONS+=("JSON格式错误")
fi

# ── 检查4：journalctl 判断服务运行质量 ──────────────────────
echo "[health-check] 检查4：journalctl 服务日志"
JNL=$(journalctl --user -u openclaw-gateway.service --no-pager -n 50 2>/dev/null)
if [ -z "$JNL" ]; then
  echo "[health-check] ⚠️  无法读取 journalctl 日志，跳过"
else
  # 检查是否有严重错误（排除已知非致命错误：API业务错误、FTS查询、session visibility等）
  JNL_ERRORS=$(echo "$JNL" | grep -i "fatal\|crash\|ECONNREFUSED\|unhandledRejection\|Cannot find module\|SyntaxError\|SIGTERM\|service.*failed" | grep -v "FTS query\|returning empty\|session visibility\|Important rule\|status code\|block not match\|\[Object\]\|plugins.*debug" | tail -3)
  # 检查 Feishu/plugins 是否有近期活动
  JNL_ACTIVE=$(echo "$JNL" | grep -i "plugins\|feishu\|message\|connected" | tail -3)

  if [ -n "$JNL_ERRORS" ]; then
    echo "[health-check] ❌ journalctl 发现错误："
    echo "$JNL_ERRORS"
    FAILED=1
    REASONS+=("服务日志有错误")
  elif [ -n "$JNL_ACTIVE" ]; then
    echo "[health-check] ✅ 服务运行正常，有近期活动记录"
  else
    echo "[health-check] ⚠️  服务日志无近期活动，可能空闲"
  fi
fi

# ── 最终判断 ──────────────────────
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "[health-check] ✅ 所有检查通过，配置修改生效正常！"
  send_alert "✅ openclaw.json 配置修改健康检查通过，服务运行正常。"
else
  REASON_STR=$(IFS=", "; echo "${REASONS[*]}")
  echo "[health-check] ❌ 健康检查失败：$REASON_STR"
  rollback
  exit 1
fi
