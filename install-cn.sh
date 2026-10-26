#!/usr/bin/env bash
# ============================================================================
#  pilot-cn 安装入口（root 阶段）
#
#  这是用户唯一需要跑的命令。它把整套流程串起来：
#    预检 → 环境层 → 装 uv → 建运行用户 → 内置 Pilot → 拉起 7000 面板（默认到此为止）
#    加 --full 才继续：建 bench、建站点、装 erpnext 应用
#
#  用法（先克隆仓库，再以 root 运行）：
#    git clone https://gitee.com/<账号>/pilot-cn ~/pilot
#    cd ~/pilot && sudo bash install-cn.sh
#
#  也可以一条命令（curl 引导，脚本会自己克隆完整仓库）：
#    curl -fsSL https://gitee.com/<账号>/pilot-cn/raw/main/install-cn.sh | sudo bash
#
#  选项：
#    --skip-preflight   跳过预检（已有结论时）
#    --skip-env         跳过环境层（已配好时）
#    --skip-bench       只装 Pilot，不建 bench/站点
#    --full            命令行装到底：建 bench、建站点、装 erpnext（默认只装到面板）
#    --gui             等价于默认行为（装到面板为止），保留以向后兼容
#    --bench-user USER  运行用户（覆盖 mirrors.conf 里的 RUN_USER）
# ============================================================================

set -euo pipefail

# 脚本可能在仓库里（正常克隆），也可能被 curl 单独拉下来（一条命令）。
# 先定位仓库根，再加载共用库。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 仓库 URL（引导模式用；能被环境变量覆盖）
PILOT_REPO_URL="${PILOT_REPO_URL:-https://gitee.com/linxiansheng0409/pilot-cn}"
PILOT_BRANCH="${PILOT_BRANCH:-main}"

SKIP_PREFLIGHT=0
SKIP_ENV=0
SKIP_BENCH=0
GUI_MODE=0
INSTALL_MODE_CLI=""
BENCH_USER_OVERRIDE=""

# ---------------------------------------------------------------------------
# 定位仓库：若当前脚本在完整仓库里则直接用；否则克隆一份。
# ---------------------------------------------------------------------------
resolve_repo_root() {
  if [[ -f "$SCRIPT_DIR/config/mirrors.conf" && -d "$SCRIPT_DIR/pilot" ]]; then
    CN_ROOT="$SCRIPT_DIR"
    return 0
  fi
  # curl 单独拉下来的情况：没有 pilot/ 与 config/，克隆完整仓库
  echo "[信息] 检测到裸脚本，从 $PILOT_REPO_URL 克隆完整仓库..."
  local tmp; tmp="$(mktemp -d)"
  git clone --depth 1 --branch "$PILOT_BRANCH" "$PILOT_REPO_URL" "$tmp/pilot-cn" \
    || { echo "[错误] 克隆仓库失败。请先手动： git clone $PILOT_REPO_URL ~/pilot"; exit 1; }
  CN_ROOT="$tmp/pilot-cn"
  echo "[信息] 仓库已克隆到 $CN_ROOT"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-preflight) SKIP_PREFLIGHT=1 ;;
      --skip-env)       SKIP_ENV=1 ;;
      --skip-bench)     SKIP_BENCH=1 ;;
      --full)           INSTALL_MODE_CLI="full" ;;
      --gui)            INSTALL_MODE_CLI="panel" ;;
      --bench-user)     BENCH_USER_OVERRIDE="${2:?--bench-user 需要用户名}"; shift ;;
      -h|--help)
        sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
      *) echo "[错误] 未知参数：$1"; exit 1 ;;
    esac
    shift
  done
}

# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  [[ "${EUID}" -eq 0 ]] || { echo "[错误] 请用 root 运行： sudo bash install-cn.sh"; exit 1; }

  resolve_repo_root
  # shellcheck source=cn/lib/core.sh
  source "${CN_ROOT}/cn/lib/core.sh"
  CN_CONF_FILE="${CN_ROOT}/config/mirrors.conf"

  load_config
  detect_arch
  detect_os

  # 命令行显式指定优先于 mirrors.conf 里的 INSTALL_MODE。
  # panel（默认）= 装到面板为止；full = 命令行装到底。
  [[ -n "$INSTALL_MODE_CLI" ]] && INSTALL_MODE="$INSTALL_MODE_CLI"
  if [[ "${INSTALL_MODE:-panel}" == "full" ]]; then
    GUI_MODE=0
  else
    GUI_MODE=1
  fi

  [[ -n "$BENCH_USER_OVERRIDE" ]] && RUN_USER="$BENCH_USER_OVERRIDE"
  resolve_passwords

  mkdir -p "$CN_STATE_DIR"

  banner "pilot-cn 安装（上游 Pilot v0.0.64-pre-alpha）"
  printf '  运行用户：%s\n  站点：%s\n  数据库模式：%s\n  依赖路线：由预检决定\n' \
    "$RUN_USER" "$SITE_NAME" "$DB_MODE"

  # ---- 阶段 1：预检 ----
  if [[ "$SKIP_PREFLIGHT" -ne 1 ]]; then
    if ! bash "${CN_ROOT}/cn/preflight.sh"; then
      die "预检未通过。修复后重跑，或用 --skip-preflight 强制继续（不推荐）。"
    fi
  fi

  # ---- 阶段 2：环境层 ----
  if [[ "$SKIP_ENV" -ne 1 ]]; then
    bash "${CN_ROOT}/cn/setup-env.sh" || die "环境层配置失败。"
  fi

  # ---- 阶段 3：装 uv（用 pip 镜像，不走 astral.sh）----
  install_uv
  # 环境层可能刚装好 uv 配置，确保立刻可读
  export PATH="/usr/local/bin:/usr/bin:$PATH"

  # ---- 阶段 4：建运行用户 ----
  create_run_user

  # ---- 阶段 5：把 Pilot 内置到运行用户目录 ----
  local pilot_home
  pilot_home="$(getent passwd "$RUN_USER" | cut -d: -f6)"
  local pilot_dir="${pilot_home}/pilot"
  vendor_pilot "$pilot_dir"

  # ---- 阶段 6：建 bench + 站点（以运行用户执行）----
  if [[ "$GUI_MODE" -eq 1 ]]; then
    gui_setup "$RUN_USER" "$pilot_dir"
  elif [[ "$SKIP_BENCH" -ne 1 ]]; then
    sudo -u "$RUN_USER" -H \
      env PILOT_HOME="$pilot_dir" \
          SITE_ADMIN_PASSWORD="$SITE_ADMIN_PASSWORD" \
          PILOT_ADMIN_PASSWORD="$PILOT_ADMIN_PASSWORD" \
          DB_ROOT_PASSWORD="$DB_ROOT_PASSWORD" \
          CC=gcc CXX=g++ \
          PATH="/usr/local/bin:/usr/bin:/bin:${pilot_dir}/bin" \
          XDG_RUNTIME_DIR="/run/user/$(id -u "$RUN_USER")" \
      bash "${pilot_dir}/cn/install-bench.sh"
  fi

  # ---- 阶段 7：验收（确认真的装好了，而不是只看"下一步"提示）----
  if [[ "${AUTO_VERIFY:-1}" -ne 1 ]]; then
    warn "已按 AUTO_VERIFY=0 跳过验收"
  elif [[ "$GUI_MODE" -eq 1 ]]; then
    verify_panel "$RUN_USER" "$pilot_dir" || warn "面板验收有异常项，请看上面的逐项结果"
  elif [[ "$SKIP_BENCH" -eq 1 ]]; then
    log "只装 Pilot（--skip-bench），跳过验收"
  else
    verify_install "$RUN_USER" "$pilot_dir" || warn "验收有异常项，请看上面的逐项结果"
  fi

  banner "安装完成"
  printf '  Pilot 目录：%s\n' "$pilot_dir"
  printf '  bench：%s\n' "$BENCH_NAME"
  printf '  站点：%s\n' "$SITE_NAME"
  if [[ "$GUI_MODE" -eq 1 ]]; then
    ok "已装到面板为止。打开 http://<服务器IP>:7000 继续"
    print_panel_credentials
  elif [[ "$SKIP_BENCH" -eq 1 ]]; then
    ok "只装了 Pilot。下一步： sudo -u $RUN_USER -H bash $pilot_dir/cn/install-bench.sh"
  else
    ok "下一步启动： sudo -u $RUN_USER -H bash -lc 'cd $pilot_dir && bin/pilot -b $BENCH_NAME start'"
    print_login_credentials
  fi
}

# ---------------------------------------------------------------------------
# GUI 模式：只把环境 + Pilot 准备好，建一个【未初始化】的 bench 并启动。
# 面板检测到 bench 未初始化会自动进入安装向导，用户可以在界面上自由选择：
#   · 数据库引擎与连接方式
#   · Frappe 仓库（GitHub / Gitee / 任意 Git 地址）
#   · Frappe 分支或 tag（列表来自你填的那个仓库）
# 向导的默认值取自 bench.toml 里 frappe 那条 [[apps]]，所以先预填成国内友好的值。
# ---------------------------------------------------------------------------
gui_setup() {
  local run_user="$1" pilot_dir="$2"
  local run_uid bench_dir i ip
  run_uid="$(id -u "$run_user")"
  bench_dir="${pilot_dir}/benches/${BENCH_NAME}"

  banner "准备面板安装向导（装到面板为止）"

  if [[ -f "${bench_dir}/bench.toml" ]]; then
    log "bench ${BENCH_NAME} 已存在，跳过 pilot new"
  else
    log "创建 bench ${BENCH_NAME}（不初始化，留给面板向导）"
    sudo -u "$run_user" -H env \
      XDG_RUNTIME_DIR="/run/user/${run_uid}" \
      PATH="/usr/local/bin:/usr/bin:/bin:${pilot_dir}/bin" \
      "${pilot_dir}/bin/pilot" new "$BENCH_NAME" --admin-password "$PILOT_ADMIN_PASSWORD" \
      || die "pilot new 失败"
  fi

  prefill_framework_defaults "${bench_dir}/bench.toml"
  disable_js_watching "${bench_dir}/bench.toml"

  log "启动 Pilot（未初始化的 bench 会自动进入安装向导）"
  sudo -u "$run_user" -H env XDG_RUNTIME_DIR="/run/user/${run_uid}" \
    bash -c "cd '${pilot_dir}' && setsid nohup ./bin/pilot -b '${BENCH_NAME}' start \
      > 'benches/${BENCH_NAME}/bench-start.log' 2>&1 < /dev/null &" \
    > /dev/null 2>&1 < /dev/null

  for i in $(seq 1 30); do
    sleep 2
    ss -tlnH "sport = :7000" 2>/dev/null | grep -q . && break
  done

  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if ss -tlnH "sport = :7000" 2>/dev/null | grep -q .; then
    ok "面板已就绪：http://${ip}:7000"
    printf '\n  打开上面的地址，在向导里选：\n'
    printf '    · 数据库引擎与连接方式\n'
    printf '    · Frappe 仓库（已预填 %s）\n' "${FRAPPE_REPO:-官方 GitHub}"
    if [[ -n "${FRAPPE_BRANCH:-}" ]]; then
      printf '    · Frappe 版本（已预填 %s）\n' "$FRAPPE_BRANCH"
    else
      printf '    · Frappe 版本（不预设，向导会列出该仓库的分支与 tag 让你选）\n'
    fi
    printf '\n  选 GitHub 也能装通：环境层已把 github.com 改写到国内可达的代理。\n\n'
  else
    warn "面板 60 秒内没起来，请看 ${bench_dir}/bench-start.log"
  fi
}

# 把 mirrors.conf 的仓库与版本预填进 bench.toml 的 frappe 条目，
# 向导打开时默认就是国内友好的选择（用户仍可改成 GitHub 或别的版本）。
prefill_framework_defaults() {
  local toml="$1"
  [[ -f "$toml" ]] || return 0
  local repo="${FRAPPE_REPO:-}" branch="${FRAPPE_BRANCH:-}"
  [[ -n "$repo$branch" ]] || return 0

  python3 - "$toml" "$repo" "$branch" <<'PY' || warn "预填向导默认值失败"
import sys
path, repo, branch = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
in_app = False
seen = []
for i, line in enumerate(lines):
    s = line.strip()
    if s.startswith("[[apps]]"):
        in_app = False
    elif s == 'name = "frappe"':
        in_app = True
    elif in_app and (s.startswith("repo =") or s.startswith("branch =")):
        indent = line[: len(line) - len(line.lstrip())]
        key = s.split("=", 1)[0].strip()
        val = repo if key == "repo" else branch
        if val:
            lines[i] = f'{indent}{key} = "{val}"\n'
            seen.append(f"{key}={val}")
if seen:
    open(path, "w", encoding="utf-8").write("".join(lines))
    print("  预填: " + ", ".join(seen))
PY
  ok "向导默认值已预填"
}

# ---------------------------------------------------------------------------
# 面板模式验收：只确认「面板真的起来了」。站点与应用交给向导，这里没有站点可验。
# ---------------------------------------------------------------------------
verify_panel() {
  local run_user="$1" pilot_dir="$2"
  local fails=0 code ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"

  banner "验收（面板）"

  if ss -tlnH "sport = :7000" 2>/dev/null | grep -q .; then
    ok "端口 7000 在监听（管理面板）"
  else
    warn "端口 7000 没在监听（管理面板）"; fails=$((fails + 1))
  fi

  if pgrep -u "$run_user" -f "bin/pilot -b ${BENCH_NAME} start" >/dev/null 2>&1; then
    ok "bench 进程在运行"
  else
    warn "bench 进程不在运行"; fails=$((fails + 1))
  fi

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:7000/" 2>/dev/null || echo 000)"
  if [[ "$code" == "200" ]]; then
    ok "管理面板应答 HTTP 200"
  else
    warn "管理面板应答 HTTP ${code}"; fails=$((fails + 1))
  fi

  printf '\n  面板地址：http://%s:7000\n' "${ip:-<服务器IP>}"
  if [[ "$fails" -eq 0 ]]; then
    ok "验收全部通过"
    return 0
  fi
  warn "面板验收有 ${fails} 项异常（日志：${pilot_dir}/benches/${BENCH_NAME}/bench-start.log）"
  return 1
}

# ---------------------------------------------------------------------------
# 面板模式的凭据：站点和 Administrator 密码要等向导建站时才有，这里只给面板入口。
# ---------------------------------------------------------------------------
print_panel_credentials() {
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  [[ -n "$ip" ]] || ip="<服务器IP>"

  printf '\n%b\n' "${c_bold}================ 面板入口 ================${c_reset}"
  printf '  %-22s %s\n' "Pilot 管理面板" "http://${ip}:7000"
  printf '  %-22s %s\n' "面板密码"       "$PILOT_ADMIN_PASSWORD"
  printf '\n  %s\n' "站点名、Administrator 密码在向导建站时由你自己设置。"
  printf '  %s\n' "密码也存于 $CN_SECRETS_FILE（600）。"
  printf '%b\n' "${c_bold}=========================================${c_reset}"
}

# ---------------------------------------------------------------------------
# 装完真验一遍：服务在跑、端口在听、站点在列、面板能应答、数据库能连。
# 之前只打印"下一步启动"，装成什么样全靠用户自己看；AUTO_VERIFY 这个开关
# 在配置里存在却从未被使用。
# ---------------------------------------------------------------------------
verify_install() {
  local run_user="$1" pilot_dir="$2"
  local run_uid bench_dir fails=0
  run_uid="$(id -u "$run_user")"
  bench_dir="${pilot_dir}/benches/${BENCH_NAME}"

  banner "验收（实际检查安装结果）"

  # 1) 关键端口
  local pair port label
  for pair in "7000:管理面板" "8000:站点 HTTP" "11000:Redis 队列" "13000:Redis 缓存"; do
    port="${pair%%:*}"; label="${pair#*:}"
    if ss -tlnH "sport = :${port}" 2>/dev/null | grep -q .; then
      ok "端口 ${port} 在监听（${label}）"
    else
      warn "端口 ${port} 没在监听（${label}）"; fails=$((fails + 1))
    fi
  done

  # 2) bench 进程
  if pgrep -u "$run_user" -f "bin/pilot -b ${BENCH_NAME} start" >/dev/null 2>&1; then
    ok "bench 进程在运行"
  else
    warn "bench 进程不在运行"; fails=$((fails + 1))
  fi

  # 3) 站点与应用
  local apps=""
  apps="$(sudo -u "$run_user" -H env XDG_RUNTIME_DIR="/run/user/${run_uid}" \
            PATH="/usr/local/bin:/usr/bin:/bin:${pilot_dir}/bin" \
            "${pilot_dir}/bin/pilot" -b "$BENCH_NAME" list-site-apps "$SITE_NAME" 2>/dev/null \
          | tr '\n' ' ' || true)"
  if [[ "$apps" == *erpnext* ]]; then
    ok "站点 ${SITE_NAME} 已装应用：${apps}"
  else
    warn "站点 ${SITE_NAME} 上看不到 erpnext（当前：${apps:-空}）"; fails=$((fails + 1))
  fi

  # 4) 管理面板应答
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:7000/" 2>/dev/null || echo 000)"
  if [[ "$code" == "200" ]]; then
    ok "管理面板应答 HTTP 200"
  else
    warn "管理面板应答 HTTP ${code}"; fails=$((fails + 1))
  fi

  # 5) 站点能应答
  # 必须带站点名做 Host：Frappe 按 Host 路由，用 127.0.0.1 访问会因为找不到站点而 404，
  # 极易被误判成"站点坏了"。
  local http_port
  http_port="$(sed -n 's/^http_port[[:space:]]*=[[:space:]]*//p' "${bench_dir}/bench.toml" 2>/dev/null | head -1)"
  http_port="${http_port:-8000}"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: ${SITE_NAME}" "http://127.0.0.1:${http_port}/" 2>/dev/null || echo 000)"
  if [[ "$code" == "200" ]]; then
    ok "站点 ${SITE_NAME} 应答 HTTP 200（端口 ${http_port}）"
  else
    warn "站点 ${SITE_NAME} 应答 HTTP ${code}（端口 ${http_port}）"; fails=$((fails + 1))
  fi

  # 6) 数据库能连
  # 注意：root 密码已被 write_db_config 设成强随机，必须带 -p；
  # 生成的密码只含 [A-Za-z0-9@]，直接拼在 -p 后面是安全的（-p 与密码之间不能有空格）。
  local sock="${pilot_dir}/databases/mariadb/run/mysqld.sock"
  if [[ -S "$sock" ]] \
     && mariadb --socket="$sock" -u root -p"${DB_ROOT_PASSWORD}" -e 'SELECT 1' >/dev/null 2>&1; then
    ok "MariaDB 可连接"
  else
    warn "MariaDB 连不上（socket: ${sock}）"; fails=$((fails + 1))
  fi

  # 7) 版本是否等于配置里钉的
  # 「钉版本」如果没生效，装完根本看不出来 —— 这里直接比对代码里的 __version__。
  local pair app want got
  for pair in "frappe:${FRAPPE_BRANCH:-}" "erpnext:${ERPNEXT_BRANCH:-}"; do
    app="${pair%%:*}"; want="${pair#*:}"
    [[ -n "$want" ]] || continue
    got="$(sed -n 's/^__version__[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
           "${bench_dir}/apps/${app}/${app}/__init__.py" 2>/dev/null | head -1)"
    if [[ -z "$got" ]]; then
      warn "读不到 ${app} 的版本号"; fails=$((fails + 1)); continue
    fi
    if [[ "$want" == "v${got}" || "$want" == "$got" ]]; then
      ok "${app} 版本符合配置（v${got}）"
    else
      warn "${app} 装的是 v${got}，但配置钉的是 ${want}"; fails=$((fails + 1))
    fi
  done

  if [[ "$fails" -eq 0 ]]; then
    ok "验收全部通过"
    return 0
  fi
  warn "验收有 ${fails} 项异常，可对照上面的提示逐个排查"
  return 1
}

# ---------------------------------------------------------------------------
install_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv 已安装：$(uv --version)"
    return 0
  fi
  log "通过 pip 镜像安装 uv（不走 astral.sh）..."
  python3 -m pip install -q --index-url "$PIP_INDEX_URL" --trusted-host "$PIP_TRUSTED_HOST" --break-system-packages uv \
    || die "uv 安装失败"
  # pip --user 装到 ~/.local/bin，root 时是 /usr/local/bin；补一个软链确保在 PATH
  if ! command -v uv >/dev/null 2>&1; then
    local uv_bin
    uv_bin="$(find /usr/local /root/.local -type f -name uv -path '*/bin/uv' 2>/dev/null | head -1 || true)"
    [[ -n "$uv_bin" ]] && ln -sf "$uv_bin" /usr/local/bin/uv || die "uv 装上了但找不到可执行文件"
  fi
  command -v uv >/dev/null 2>&1 || die "uv 安装后仍不可用"
  ok "uv 就绪：$(uv --version)"
}

create_run_user() {
  [[ "$RUN_USER" == "root" ]] && return 0
  if ! id "$RUN_USER" >/dev/null 2>&1; then
    log "创建运行用户 $RUN_USER"
    useradd -m -s /bin/bash "$RUN_USER"
    passwd -l "$RUN_USER" >/dev/null 2>&1 || true
  fi

  # 给运行用户设一个强密码，和站点/面板密码一起固化并打印
  if [[ -n "${RUN_USER_PASSWORD:-}" ]]; then
    echo "$RUN_USER:$RUN_USER_PASSWORD" | chpasswd \
      && ok "已设置 $RUN_USER 的登录密码（见下方登录凭据）"
  fi

  # systemd 用户会话：Pilot 的 bench 服务（per-user MariaDB / Redis / 进程管理）
  # 全部跑在 systemctl --user 里。没有 linger 就没有 /run/user/<uid>，Pilot 会报
  # "Failed to connect to bus: No such file or directory"，init 直接失败。
  if command -v loginctl >/dev/null 2>&1; then
    if loginctl enable-linger "$RUN_USER" 2>/dev/null; then
      ok "已为 $RUN_USER 开启 linger（systemd 用户服务可用）"
    else
      warn "开启 linger 失败；Pilot 可能起不来 per-user 服务"
    fi
  else
    warn "系统没有 loginctl；Pilot 的 bench 服务需要 systemd 用户会话"
  fi

  configure_run_user_registries
  grant_caller_access
  log "运行用户：$RUN_USER（$(getent passwd "$RUN_USER" | cut -d: -f6)）"
}

# 把 npm / yarn 的国内源写进运行用户的家目录。
# 只写 /etc/npmrc 与 /etc/yarnrc 是无效的：yarn 不读 /etc/yarnrc，npm 的全局配置在
# $PREFIX/etc/npmrc 而不是 /etc/npmrc —— 实测运行用户仍会去 registry.npmjs.org 拉包，
# 比 npmmirror 慢约 9 倍（1.1MB/s vs 127KB/s）。
configure_run_user_registries() {
  local rhome
  rhome="$(getent passwd "$RUN_USER" | cut -d: -f6)"
  [[ -n "$rhome" && -d "$rhome" ]] || return 0

  printf 'registry=%s\n' "$NPM_REGISTRY" > "${rhome}/.npmrc"
  printf 'registry "%s"\ndisturl "%s"\n' "$NPM_REGISTRY" "$NODE_BINARY_MIRROR" > "${rhome}/.yarnrc"
  chown "$RUN_USER:$RUN_USER" "${rhome}/.npmrc" "${rhome}/.yarnrc" 2>/dev/null || true
  ok "已为 $RUN_USER 配置 npm/yarn 国内源（~/.npmrc + ~/.yarnrc）"
}

# 让发起安装的人（SSH 登录用户）能在 VSCode 里浏览运行用户的家目录。
# 家目录是 drwxr-x---，是唯一挡住别人的一层；下面的目录本来就是组可读写。
grant_caller_access() {
  local viewer="${SUDO_USER:-${USER:-}}"
  [[ -n "$viewer" && "$viewer" != "root" && "$viewer" != "$RUN_USER" ]] || return 0
  id "$viewer" >/dev/null 2>&1 || return 0

  local home
  home="$(getent passwd "$RUN_USER" | cut -d: -f6)"

  log "授予 $viewer 访问 $home 的权限"
  usermod -aG "$RUN_USER" "$viewer" 2>/dev/null || true
  chmod g+rx "$home" 2>/dev/null || true

  # ACL 立即生效；组变更只对新会话生效，所以两者都做
  command -v setfacl >/dev/null 2>&1 \
    || DEBIAN_FRONTEND=noninteractive apt-get install -y -q acl >/dev/null 2>&1 || true
  if command -v setfacl >/dev/null 2>&1; then
    setfacl -m "u:${viewer}:rx" "$home" 2>/dev/null || true
    ok "$viewer 立即可访问 $home；组变更重登后对终端生效"
  else
    warn "$viewer 已加入 $RUN_USER 组，重新登录后生效"
  fi
}

vendor_pilot() {
  local pilot_dir="$1"
  log "内置 Pilot 到 $pilot_dir"

  if [[ -d "$pilot_dir/.git" ]]; then
    # 已存在且是 git 仓库：把 origin 指回 PILOT_REPO_URL，
    # 保证 `pilot admin upgrade`（git pull）从 Gitee 拉取而不是本地路径。
    log "  $pilot_dir 已是 git 仓库，校正 origin 指向 $PILOT_REPO_URL"
    git -C "$pilot_dir" remote set-url origin "$PILOT_REPO_URL" 2>/dev/null || true

    # 已有仓库不会被重新克隆，但「改完仓库 → 重跑安装脚本」必须立刻生效，
    # 否则跑的还是上一次那份旧代码。这里只在工作区干净时快进到 PILOT_BRANCH
    # 最新；benches/ 在 .gitignore 里，站点与数据不受影响。分叉或本地有改动
    # 时保持现状并提示，用 sudo cn/deploy.sh 自行决定怎么同步。
    if [[ -n "$(git -C "$pilot_dir" status --porcelain 2>/dev/null | head -1)" ]]; then
      warn "  $pilot_dir 有未提交改动，跳过更新（保持现状）"
    elif git -C "$pilot_dir" fetch --quiet --depth 1 "$PILOT_REPO_URL" "$PILOT_BRANCH" 2>/dev/null; then
      if git -C "$pilot_dir" merge --quiet --ff-only FETCH_HEAD 2>/dev/null; then
        log "  已快进到 $PILOT_BRANCH 最新：$(git -C "$pilot_dir" log -1 --format='%h %s' 2>/dev/null)"
      else
        warn "  无法快进（本地有额外提交或已分叉），保持现有代码；需要时用 sudo cn/deploy.sh"
      fi
    else
      warn "  拉取 $PILOT_REPO_URL 失败（离线？），保持现有代码"
    fi
  else
    # 直接从 Gitee 克隆，origin 正确，后续升级走 git pull（国内可用）。
    [[ -d "$pilot_dir" ]] && rm -rf "$pilot_dir"
    cp -a "$CN_ROOT" "$pilot_dir" \
      || die "克隆 pilot-cn 失败：$PILOT_REPO_URL（请确认仓库已上传且地址正确）"
  fi

  # 关键：不能有 VERSION 文件，否则升级会走 api.github.com 那条死路
  rm -f "$pilot_dir/VERSION"

  chown -R "$RUN_USER":"$RUN_USER" "$pilot_dir"
  chmod +x "$pilot_dir/bin/pilot"
  ok "Pilot 就绪于 $pilot_dir（origin=$PILOT_REPO_URL）"
}

main "$@"
