#!/usr/bin/env bash
# ============================================================================
#  pilot-cn 建 bench 阶段（以运行用户身份执行，不要求 root）
#
#  由 install-cn.sh 通过 `sudo -u <运行用户>` 调用。职责：
#    pilot new → pilot init → new-site → get-app(erpnext) → install-app
#    以及 EXTRA_APPS（其他应用）和 LOCAL_APP_PATHS（自建应用本地目录）。
#
#  关键：源码 URL 一律传官方 github.com 地址，由环境层写好的 git insteadOf
#  在传输层改道到 Gitee / 内网 / 本地。Pilot 无需知道仓库实际在哪。
# ============================================================================

set -euo pipefail

CN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "${CN_SCRIPT_DIR}/lib/core.sh"
# shellcheck source=lib/deps.sh
source "${CN_SCRIPT_DIR}/lib/deps.sh"

PILOT_HOME="${PILOT_HOME:-$HOME/pilot}"
export PATH="${PILOT_HOME}/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
# python-build-standalone 的 sysconfig 记录编译器为 clang，系统里只有 gcc；
# 不覆盖会在编译 mysqlclient 等 C 扩展时报找不到 clang。
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"

_env_site_pw="${SITE_ADMIN_PASSWORD-}"
_env_pilot_pw="${PILOT_ADMIN_PASSWORD-}"
_env_db_pw="${DB_ROOT_PASSWORD-}"
load_config
SITE_ADMIN_PASSWORD="${_env_site_pw}"
PILOT_ADMIN_PASSWORD="${_env_pilot_pw}"
DB_ROOT_PASSWORD="${_env_db_pw}"
detect_arch
detect_os

BENCH_DIR="${PILOT_HOME}/benches/${BENCH_NAME}"

# ---------------------------------------------------------------------------
# 已知坏版本护栏：erpnext v16.50.0 ~ v16.52.x 的
#   erpnext/stock/doctype/stock_entry/services/material_transfer.py
# 引用了同目录下不存在的 manufacturing.py / stock_entry_base.py（上游半截重构，
# v16.53.0 才随整个文件删掉）。Pilot 装应用前会逐条核对 import，命中即
# "imports that don't resolve" 并回滚——所以要在这里早失败，别等克隆+构建跑完。
# 面板向导里选版本时由用户自己规避，这里只管命令行钉版本的情况。
# ---------------------------------------------------------------------------
check_known_bad_erpnext_branch() {
  local want="${ERPNEXT_BRANCH:-}"
  [[ -n "$want" ]] || return 0
  if [[ "$want" =~ ^v?16\.(50\.[0-9]+|51\.[0-9]+|52\.[0-9]+)$ ]]; then
    die "erpnext 的 ${want} 有已知坏引用，装不上（会报 imports that don't resolve）：
  erpnext/stock/doctype/stock_entry/services/material_transfer.py
  引用了同目录下不存在的 manufacturing.py / stock_entry_base.py。
请改 config/mirrors.conf 的 ERPNEXT_BRANCH：用 v16.49.0（实测干净）或 v16.53.0+。
不钉版本（PIN_VERSIONS=0，默认）则不会走到这里。"
  fi
}
check_known_bad_erpnext_branch

bench_initialized() {
  [[ -d "${BENCH_DIR}/apps/frappe" ]]
}

# ---------------------------------------------------------------------------
# 把生成的数据库强密码写进 common_config.toml。
# `pilot new` 会先写入默认 root_password="root"，这里覆盖成强随机密码。
# 幂等：只覆盖仍是默认值 "root" 的情况；已经改过就不动。
# ---------------------------------------------------------------------------
write_db_config() {
  local benches_dir="${PILOT_HOME}/benches"
  local common_file="${benches_dir}/common_config.toml"
  mkdir -p "$benches_dir"

  if [[ -f "$common_file" ]] && ! grep -q 'root_password[[:space:]]*=[[:space:]]*"root"' "$common_file" 2>/dev/null; then
    log "common_config.toml 已是自定义数据库密码，跳过"
    return 0
  fi

  if [[ "$DB_MODE" == "existing" ]]; then
    log "接入已有 MariaDB：${DB_EXISTING_HOST}:${DB_EXISTING_PORT}"
    cat > "$common_file" <<EOF
[mariadb]
host = "${DB_EXISTING_HOST}"
port = ${DB_EXISTING_PORT}
root_password = "${DB_ROOT_PASSWORD}"
admin_user = "${DB_ROOT_USER:-root}"
existing = true
EOF
  else
    log "写入数据库强密码到 common_config.toml（Pilot 自管 MariaDB）"
    cat > "$common_file" <<EOF
[mariadb]
root_password = "${DB_ROOT_PASSWORD}"
EOF
  fi
  chmod 600 "$common_file"
  ok "数据库配置已写入 $common_file"
}

# ---------------------------------------------------------------------------
create_bench() {
  if [[ -f "${BENCH_DIR}/bench.toml" ]]; then
    log "bench ${BENCH_NAME} 已存在，跳过 pilot new"
  else
    log "创建 bench ${BENCH_NAME}"
    pilot new "$BENCH_NAME" --admin-password "$PILOT_ADMIN_PASSWORD" \
      || die "pilot new 失败"
  fi

  # 必须在 pilot init 之前：把 frappe 分支钉成配置里的版本
  configure_framework_app

  # 必须在 pilot start 之前：常驻的 JS 监听会在 web 缓存资产清单后再换掉 hash 文件名
  disable_js_watching "${BENCH_DIR}/bench.toml"

  # 必须在 pilot init 之前：让数据库用强密码而不是默认的 root
  write_db_config

  if bench_initialized; then
    log "bench 已初始化，跳过 pilot init"
  else
    log "初始化 bench（克隆 frappe + 装依赖 + 构建，约 20-60 分钟）"
    pilot -b "$BENCH_NAME" init --no-dev || die "pilot init 失败"
  fi
}

# ---------------------------------------------------------------------------
# pilot new 给 frappe 的默认分支是 version-16 —— 这是「移动」的分支，上游一发版
# 就往前走；而 mirrors.conf 钉的 FRAPPE_BRANCH 通常是个 tag。不钉住就会装到比预期
# 新的版本：实测配置写 v16.51.0，装出来是 v16.52.0。
# 必须在 pilot init 之前改，因为 init 就是按 bench.toml 里的分支去克隆的。
# ---------------------------------------------------------------------------
configure_framework_app() {
  local toml="${BENCH_DIR}/bench.toml"
  [[ -f "$toml" ]] || return 0
  [[ -n "${FRAPPE_BRANCH:-}" ]] || return 0

  local current
  current="$(python3 - "$toml" <<'PY'
import sys
in_app = False
for line in open(sys.argv[1], encoding="utf-8"):
    s = line.strip()
    if s.startswith("[[apps]]"):
        in_app = False
    elif s == 'name = "frappe"':
        in_app = True
    elif in_app and s.startswith("branch ="):
        print(s.split("=", 1)[1].strip().strip('"'))
        break
PY
)"

  if [[ "$current" == "$FRAPPE_BRANCH" ]]; then
    log "frappe 分支已钉在 ${FRAPPE_BRANCH}"
    return 0
  fi

  log "把 frappe 分支从『${current:-未知}』钉到『${FRAPPE_BRANCH}』"
  if python3 - "$toml" "$FRAPPE_BRANCH" <<'PY'
import sys
path, branch = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
in_app = done = False
for i, line in enumerate(lines):
    s = line.strip()
    if s.startswith("[[apps]]"):
        in_app = False
    elif s == 'name = "frappe"':
        in_app = True
    elif in_app and s.startswith("branch ="):
        indent = line[: len(line) - len(line.lstrip())]
        lines[i] = f'{indent}branch = "{branch}"\n'
        in_app, done = False, True
        break
if not done:
    sys.exit(1)
open(path, "w", encoding="utf-8").write("".join(lines))
PY
  then
    ok "frappe 分支已钉到 ${FRAPPE_BRANCH}"
  else
    warn "钉 frappe 分支失败；bench.toml 里可能没有 [[apps]] name=\"frappe\" 段"
  fi
}

# ---------------------------------------------------------------------------
create_site() {
  if [[ -d "${BENCH_DIR}/sites/${SITE_NAME}" ]]; then
    log "站点 ${SITE_NAME} 已存在"
  else
    log "创建站点 ${SITE_NAME}（Frappe Administrator 密码用配置值，不再默认 admin）"
    pilot -b "$BENCH_NAME" new-site "$SITE_NAME" --admin-password "$SITE_ADMIN_PASSWORD" \
      || die "new-site 失败"
  fi
  # Frappe 按 HTTP Host 头路由站点：直接访问 IP 时 Host=IP 找不到站点会 404。
  # 写 currentsite.txt（默认站点）并为本机 IP 建软链（幂等）。
  local sites_dir="${BENCH_DIR}/sites"
  echo "$SITE_NAME" > "${sites_dir}/currentsite.txt"
  local ip; ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  if [[ -n "$ip" ]]; then
    ln -sfn "$SITE_NAME" "${sites_dir}/${ip}"
  fi
  log "已设置默认站点 ${SITE_NAME} 与本机 IP 软链（IP 访问不再 404）"
}

# ---------------------------------------------------------------------------
# install-app 的数据库迁移会触发 frappe.enqueue，硬依赖 Redis Queue（11000）在线，
# 否则报 "Error 111 connecting to localhost:11000. Connection refused."。
# 所以 install-app 之前必须先启动 bench。
ensure_bench_running() {
  if ss -tlnH "sport = :11000" 2>/dev/null | grep -q .; then
    return 0
  fi
  cd "$PILOT_HOME"
  setsid nohup "$PILOT_HOME/bin/pilot" -b "$BENCH_NAME" start > "${BENCH_DIR}/bench-start.log" 2>&1 < /dev/null &
  local i=0
  while [[ $i -lt 45 ]]; do
    sleep 2
    ss -tlnH "sport = :11000" 2>/dev/null | grep -q . && return 0
    i=$((i+1))
  done
  warn "90 秒内未等到 Redis Queue（11000）就绪"
  return 1
}

install_apps() {
  # erpnext（源码 URL 走 git insteadOf 改道，这里保持官方 github 地址）
  # 第一步：get-app（克隆源码 + 装依赖 + 构建）
  if pilot -b "$BENCH_NAME" list-apps 2>/dev/null | grep -qx 'erpnext'; then
    log "erpnext 源码已在 bench 中，跳过 get-app"
  else
    log "安装 erpnext（源码经 insteadOf 走镜像）"
    pilot -b "$BENCH_NAME" get-app "${ERPNEXT_REPO:-https://github.com/frappe/erpnext}" --branch "$ERPNEXT_BRANCH" || die "get-app erpnext 失败"
  fi
  # 第二步：启动 bench（install-app 的数据库迁移需要 Redis Queue 11000 在线）
  ensure_bench_running || die "bench 未能在 90 秒内启动，install-app 无法继续"
  # 第三步：install-app（数据库迁移）
  if pilot -b "$BENCH_NAME" list-site-apps "$SITE_NAME" 2>/dev/null | grep -qx 'erpnext'; then
    log "erpnext 已安装到站点，跳过 install-app"
  else
    pilot -b "$BENCH_NAME" install-app "$SITE_NAME" erpnext || die "install-app erpnext 失败"
  fi

  # 其他应用（EXTRA_APPS：名字=仓库地址）
  local app repo
  for app in "${!EXTRA_APPS[@]}"; do
    repo="${EXTRA_APPS[$app]}"
    if pilot -b "$BENCH_NAME" list-apps 2>/dev/null | grep -qx "$app"; then
      log "应用 ${app} 已安装"
      continue
    fi
    log "安装应用 ${app}（${repo}）"
    pilot -b "$BENCH_NAME" get-app "$repo" --branch "$FRAPPE_BRANCH" \
      || die "get-app ${app} 失败"
    pilot -b "$BENCH_NAME" install-app "$SITE_NAME" "$app" \
      || die "install-app ${app} 失败"
  done

  # 自建应用（LOCAL_APP_PATHS：本地目录，符号链接挂载）
  local path app_name
  for path in "${LOCAL_APP_PATHS[@]}"; do
    [[ -d "$path" ]] || { warn "自建应用目录不存在：$path"; continue; }
    app_name="$(basename "$path")"
    if pilot -b "$BENCH_NAME" list-apps 2>/dev/null | grep -qx "$app_name"; then
      log "自建应用 ${app_name} 已安装"
      continue
    fi
    log "挂载自建应用 ${app_name}（本地目录，改动即时生效）"
    link_local_app "$BENCH_DIR" "$path"
    pilot -b "$BENCH_NAME" install-app "$SITE_NAME" "$app_name" \
      || die "install-app ${app_name} 失败"
  done
}

# ---------------------------------------------------------------------------
main() {
  cd "$PILOT_HOME" || die "无法进入 $PILOT_HOME"
  banner "建 bench / 站点 / 应用（运行用户 $USER）"
  create_bench
  create_site
  install_apps

  banner "完成"
  printf '  bench：%s\n' "$BENCH_DIR"
  printf '  站点：%s\n' "$SITE_NAME"
  printf '  已装应用：%s\n' "$(pilot -b "$BENCH_NAME" list-apps 2>/dev/null | tr '\n' ' ')"
  ok "下一步启动： pilot -b $BENCH_NAME start"
}

main "$@"
