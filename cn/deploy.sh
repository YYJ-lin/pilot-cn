#!/usr/bin/env bash
# cn/deploy.sh —— 把 pilot-cn 源码同步到正在运行的 Pilot 实例。
#
# 为什么需要它：Pilot 跑在 /home/erpnext/pilot，而我们的仓库在 /home/linxiansheng/pilot-cn。
# 改完代码要同步过去才能生效——前端产物（admin/backend/static/*）被 .gitignore 忽略，
# 也必须一起同步，否则界面还是旧的。
#
# 用法:
#   sudo cn/deploy.sh              # 只同步源码 + 构建产物
#   sudo cn/deploy.sh --restart    # 同步后重启 bench
#
# 环境变量（一般不用改）:
#   PILOT_CN_TARGET   部署目录     默认 /home/erpnext/pilot
#   PILOT_CN_OWNER    属主         默认 erpnext:erpnext
#   PILOT_CN_BENCH    bench 名     默认 main
#   PILOT_CN_RUNTIME  XDG_RUNTIME  默认 /run/user/1001
set -euo pipefail

CN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${PILOT_CN_TARGET:-/home/erpnext/pilot}"
OWNER="${PILOT_CN_OWNER:-erpnext:erpnext}"
BENCH="${PILOT_CN_BENCH:-main}"
RUNTIME="${PILOT_CN_RUNTIME:-/run/user/1001}"
RESTART=0
[[ "${1:-}" == "--restart" ]] && RESTART=1

log()  { printf '\033[36m[deploy]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[deploy]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "请用 sudo 运行：sudo cn/deploy.sh"
[[ -d "$TARGET" ]] || die "找不到部署目录 $TARGET"

log "源:   $CN_ROOT"
log "目标: $TARGET"

# 前端产物没构建就提醒一声：同步过去也只是旧界面
if [[ ! -d "$CN_ROOT/admin/backend/static/dashboard/assets" ]]; then
  warn "源码里没有前端构建产物（admin/backend/static/dashboard/assets）"
  warn "先构建：cd admin/frontend/dashboard && npm install && npm run build"
fi

# --delete 清理目标端旧文件；static/ 用 P(protect) 保护，避免误删已部署的前端产物
RSYNC_ARGS=(
  -a --delete
  --exclude '.git/' --exclude 'node_modules/' --exclude '__pycache__/'
  --exclude '*.pyc' --exclude '.venv/' --exclude '.admin-venv/' --exclude 'benches/'
  --filter 'P admin/backend/static/***'
  # sync_dir 是按子目录逐个 rsync 的，传输根就是 admin/ —— 那时 admin/backend/static/***
  # 永远匹配不上，静态产物会被 --delete 删掉（表现为面板 503）。必须再写一条相对根的规则。
  --filter 'P backend/static/***'
)

sync_dir() {
  local rel="$1"
  [[ -e "$CN_ROOT/$rel" ]] || return 0
  log "同步 $rel/"
  if command -v rsync >/dev/null 2>&1; then
    rsync "${RSYNC_ARGS[@]}" "$CN_ROOT/$rel/" "$TARGET/$rel/"
  else
    warn "未找到 rsync，改用 cp -r（不会清理目标端旧文件）"
    cp -r "$CN_ROOT/$rel/." "$TARGET/$rel/"
  fi
}

for rel in pilot admin cn config; do sync_dir "$rel"; done
if [[ -f "$CN_ROOT/install-cn.sh" ]]; then
  log "同步 install-cn.sh"
  cp "$CN_ROOT/install-cn.sh" "$TARGET/"
fi

log "修正属主：$OWNER"
chown -R "$OWNER" "$TARGET/pilot" "$TARGET/admin" "$TARGET/cn" "$TARGET/config" 2>/dev/null || true

log "清理 __pycache__"
find "$TARGET" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

# 生产模式下服务由 systemd 托管，pilot start 不适用，要用 pilot restart。
is_production() {
  local toml="$TARGET/benches/$BENCH/bench.toml"
  [[ -f "$toml" ]] || return 1
  sed -n '/^\[production\]/,/^\[/p' "$toml" 2>/dev/null \
    | grep -qE '^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true'
}

if [[ "$RESTART" -eq 1 ]]; then
  RUN_USER="${OWNER%%:*}"
  # runuser 从 root 降权不会像嵌套 sudo 那样等待密码或 tty
  as_user() { runuser -u "$RUN_USER" -- "$@"; }

  if is_production; then
    log "检测到生产模式（systemd + nginx），用 pilot restart ..."
    as_user env XDG_RUNTIME_DIR="$RUNTIME" "$TARGET/bin/pilot" -b "$BENCH" restart \
      || warn "pilot restart 失败，请手动检查 systemctl 状态"
    sleep 8
    log "端口检查："
    ss -tlnH 2>/dev/null | grep -E ':7000|:8000|:11000|:13000' | awk '{print "  " $4}' || true
    log "完成。"
    exit 0
  fi

  log "停止 bench '$BENCH' ..."
  pkill -u "$RUN_USER" -f "bin/pilot -b $BENCH start" 2>/dev/null || true
  pkill -u "$RUN_USER" -f 'redis-server 127.0.0.1:1[13]000' 2>/dev/null || true
  pkill -u "$RUN_USER" -f 'bench_helper' 2>/dev/null || true
  pkill -u "$RUN_USER" -f 'admin.backend.run_server' 2>/dev/null || true
  pkill -u "$RUN_USER" -f 'socketio.js' 2>/dev/null || true
  sleep 5

  log "启动 bench '$BENCH' ..."
  as_user env XDG_RUNTIME_DIR="$RUNTIME" bash -c \
    "cd '$TARGET' && setsid nohup ./bin/pilot -b $BENCH start > benches/$BENCH/bench-start.log 2>&1 < /dev/null &" \
    > /dev/null 2>&1 < /dev/null
  sleep 20

  log "端口检查："
  ss -tlnH 2>/dev/null | grep -E ':7000|:8000|:11000|:13000' | awk '{print "  " $4}' || true
fi

log "完成。"
