#!/usr/bin/env bash
# ============================================================================
#  pilot-cn 预检（阶段 0）
#
#  零副作用：只读探测，不修改系统、不安装任何东西。
#  输出四级结果，并决定三个 GitHub 钉死依赖走哪条路线。
#
#  用法：
#    sudo bash cn/preflight.sh              # 完整预检
#    sudo bash cn/preflight.sh --quiet      # 只输出结论与硬伤
#    sudo bash cn/preflight.sh --json FILE  # 额外写出机器可读结果
#
#  退出码：0 可以继续 / 1 有硬伤 / 2 环境异常
# ============================================================================

set -uo pipefail

CN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "${CN_SCRIPT_DIR}/lib/core.sh"

QUIET=0
JSON_OUT=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet) QUIET=1 ;;
      --json)  JSON_OUT="${2:?--json 需要文件名}"; shift ;;
      -h|--help)
        sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
      *) die "未知参数：$1" ;;
    esac
    shift
  done
}

# ===========================================================================
#  1. 系统与资源
# ===========================================================================
check_system() {
  banner "1/6  系统与资源"

  detect_os
  detect_arch
  log "系统：${CN_OS_PRETTY:-未知}（ID=${CN_OS_ID} 版本=${CN_OS_VERSION} 代号=${CN_OS_CODENAME}）"
  log "架构：$(uname -m)（Python 资产=${CN_GIT_ARCH}  Node=${CN_NODE_ARCH}）"

  case "$CN_OS_ID" in
    ubuntu)
      [[ "${CN_OS_VERSION%%.*}" -ge 24 ]] \
        && report_ok "操作系统" "Ubuntu ${CN_OS_VERSION}" \
        || report_block "操作系统" "Ubuntu ${CN_OS_VERSION} 低于要求的 24.04，请换系统"
      ;;
    debian)
      [[ "${CN_OS_VERSION%%.*}" -ge 12 ]] \
        && report_ok "操作系统" "Debian ${CN_OS_VERSION}" \
        || report_block "操作系统" "Debian ${CN_OS_VERSION} 低于要求的 12，请换系统"
      ;;
    *)
      report_yellow "操作系统" "未在官方支持列表（Ubuntu 24.04+ / Debian 12+），继续但风险自负"
      ;;
  esac

  local mem swap disk
  mem="$(mem_total_mb)"; swap="$(swap_total_mb)"; disk="$(disk_free_gb /)"
  log "内存 $((mem/1024))GB · 交换 $((swap/1024))GB · 根分区可用 ${disk}GB"

  if [[ "$mem" -lt 3500 ]]; then
    if [[ "$swap" -lt 1024 && "$disk" -ge 6 ]]; then
      report_green "内存不足 4GB" "环境层会创建 2GB swapfile 兜底"
    else
      report_red "内存不足 4GB" "前端构建可能 OOM；建议升配到 4核8G"
    fi
  else
    report_ok "内存" "$((mem/1024))GB"
  fi

  # 面板模式只装环境层 + Pilot，不克隆 frappe/erpnext、不装 node_modules；
  # 完整安装（--full）才需要把两套源码和依赖都放下，所以阈值分开。
  local disk_min=25
  [[ "${INSTALL_MODE:-panel}" == "panel" ]] && disk_min=10
  if [[ "$disk" -ge "$disk_min" ]]; then
    report_ok "磁盘" "根分区可用 ${disk}GB（本次需要 ${disk_min}GB）"
    if [[ "$disk_min" -eq 10 && "$disk" -lt 25 ]]; then
      report_yellow "磁盘余量偏紧" "面板里装 frappe+erpnext 还要约 15GB；当前 ${disk}GB，建议先清理"
    fi
  else
    report_block "磁盘" "仅 ${disk}GB，至少需要 ${disk_min}GB（推荐 50GB）"
  fi

  local missing=()
  for t in curl git python3; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    report_ok "基础工具" "curl / git / python3 就绪"
  else
    report_green "基础工具缺失" "缺少 ${missing[*]}，环境层会补装"
  fi
}

# ===========================================================================
#  2. 环境层的目标源（全部可自动修）
# ===========================================================================
check_mirrors() {
  banner "2/6  国内源可达性"

  probe_one() {  # name url [method]
    if probe_url "$2" "${3:-GET}"; then
      report_ok "$1" "$2"
    else
      report_green "$1 不通" "环境层会换源或提示你改 config/mirrors.conf"
    fi
  }

  probe_one "apt 源"          "${APT_MIRROR}/dists/${CN_OS_CODENAME}/Release" HEAD
  probe_one "pip 源"          "${PIP_INDEX_URL}/" HEAD
  probe_one "npm 源"          "${NPM_REGISTRY}/" HEAD
  probe_one "Node 二进制源"   "${NODE_BINARY_MIRROR}/index.json" HEAD

  if [[ -n "${MARIADB_REPO:-}" ]]; then
    probe_one "MariaDB 源"    "${MARIADB_REPO}/dists/${MARIADB_REPO_CODENAME}/Release" HEAD
  else
    report_yellow "MariaDB 源" "未配置，将用发行版自带版本（可能低于 ${MARIADB_VERSION}）"
  fi

  if [[ -n "${PYTHON_STANDALONE_BASE:-}" ]]; then
    probe_one "Python 预编译包源" "${PYTHON_STANDALONE_BASE}/" HEAD
  else
    report_yellow "Python 预编译包源" "未配置，uv 会去 GitHub 下载（国内多半不通）"
  fi
}

# ===========================================================================
#  3. 源码仓库（走 Gitee / 内网 / 本地）
# ===========================================================================
check_sources() {
  banner "3/6  源码仓库可达性"

  probe_gitee_repo() {  # name repo_url branch
    local name="$1" url="$2" branch="$3" slug info
    [[ -n "$url" ]] || { report_block "$name" "未配置仓库地址"; return; }
    slug="$(gitee_slug "$url")"

    if [[ "$url" == /* || "$url" == file://* ]]; then
      local p="${url#file://}"
      [[ -d "$p" ]] && report_ok "$name" "本地路径存在：$p" \
                    || report_block "$name" "本地路径不存在：$p"
      return
    fi

    if [[ "$url" == *gitee.com* ]]; then
      # PIN_VERSIONS=0 时没有分支可查：只确认仓库本身可达（版本在面板里选）。
      if [[ -z "$branch" ]]; then
        info="$(gitee_repo_info "$slug")"
        if [[ -n "$info" ]]; then
          report_ok "$name" "${slug} 可达（未钉版本，${info}）"
        else
          report_block "$name" "${slug} 不存在或 Gitee 不可达"
        fi
        return
      fi
      info="$(gitee_branch_info "$slug" "$branch")"
      if [[ -n "$info" ]]; then
        report_ok "$name" "${slug}@${branch}  ${info:0:60}"
      else
        report_block "$name" "${slug}@${branch} 不存在或 Gitee 不可达"
      fi
      return
    fi

    probe_git "$url" && report_ok "$name" "$url" \
                     || report_block "$name" "$url 无法克隆"
  }

  probe_gitee_repo "frappe 框架"  "${FRAPPE_REPO:-}"  "$FRAPPE_BRANCH"
  probe_gitee_repo "erpnext 应用" "${ERPNEXT_REPO:-}" "$ERPNEXT_BRANCH"

  if [[ "${#EXTRA_APPS[@]}" -gt 0 ]]; then
    local app
    for app in "${!EXTRA_APPS[@]}"; do
      probe_gitee_repo "附加应用 $app" "${EXTRA_APPS[$app]}" "$FRAPPE_BRANCH"
    done
  else
    report_yellow "附加应用" "config/mirrors.conf 的 EXTRA_APPS 为空，只会装 frappe + erpnext"
  fi

  if [[ "${#LOCAL_APP_PATHS[@]}" -gt 0 ]]; then
    local p found=0
    for p in "${LOCAL_APP_PATHS[@]}"; do
      if [[ -d "$p" ]]; then
        found=$((found+1))
        [[ -f "${p}/pyproject.toml" ]] \
          && report_ok "自建应用 $(basename "$p")" "$p" \
          || report_yellow "自建应用 $(basename "$p")" "$p 缺少 pyproject.toml，可能不是 Frappe 应用"
      else
        report_block "自建应用路径" "不存在：$p"
      fi
    done
    [[ "$found" -gt 0 ]] || report_block "自建应用" "LOCAL_APP_PATHS 里没有可用的目录"
  fi
}

# ===========================================================================
#  4. 三个钉死 GitHub 的依赖 —— 路线决策
# ===========================================================================
check_pinned_dependencies() {
  banner "4/6  三个钉死 GitHub 的依赖"

  local route_a_ok=0 route_b_ok=0 chosen_proxy=""

  # --- 路线 A：Gitee 服务端导入的自建镜像 ---
  if [[ -n "${GITEE_OWNER:-}" ]]; then
    local all_ok=1 r
    for r in "${PYPIKA_REPO:-$GITEE_OWNER/pypika}" \
             "${GUNICORN_REPO:-$GITEE_OWNER/gunicorn}" \
             "${AIR_DATEPICKER_REPO:-$GITEE_OWNER/air-datepicker}"; do
      r="$(gitee_slug "$r")"
      curl -fsS -o /dev/null --max-time "$PROBE_TIMEOUT" \
        "https://gitee.com/api/v5/repos/${r}" 2>/dev/null || all_ok=0
    done
    if [[ "$all_ok" -eq 1 ]]; then
      route_a_ok=1
      report_ok "路线 A" "Gitee 自建镜像三个仓库都在（保留 fork 与 pinned SHA）"
    else
      report_yellow "路线 A" "GITEE_OWNER 已填但仓库校验失败，改用其他路线"
    fi
  else
    report_yellow "路线 A" "GITEE_OWNER 为空；建议按 README 第 6 节导入三个仓库后启用"
  fi

  # --- 路线 B：GitHub 加速代理（实测 git 协议，不只看首页）---
  local p
  for p in "${GITHUB_PROXY_CANDIDATES[@]}"; do
    if probe_git_proxy "$p"; then
      chosen_proxy="$p"; route_b_ok=1
      report_ok "路线 B" "$p 能代理 git 协议"
      break
    fi
  done
  [[ "$route_b_ok" -eq 1 ]] || report_red "路线 B" "所有候选代理都不可用（第三方代理不稳定）"

  # --- 路线 C：兜底 ---
  local route
  if   [[ "$route_a_ok" -eq 1 ]]; then route="A"
  elif [[ "$route_b_ok" -eq 1 ]]; then route="B"
  else                                 route="C"; fi

  case "$route" in
    A) ok "选定路线 A —— 版本与官方完全一致" ;;
    B) ok "选定路线 B —— 经代理 ${chosen_proxy}" ;;
    C) report_red "选定路线 C" "改写为 PyPI/npm 官方版本；会丢掉 frappe 的 fork 补丁，版本偏离官方" ;;
  esac

  CN_ROUTE="$route"
  CN_CHOSEN_PROXY="$chosen_proxy"
  mkdir -p /var/lib/pilot-cn
  {
    echo "CN_ROUTE=$CN_ROUTE"
    echo "CN_CHOSEN_PROXY=$CN_CHOSEN_PROXY"
    echo "CN_ROUTE_A_OK=$route_a_ok"
    echo "CN_ROUTE_B_OK=$route_b_ok"
  } > /var/lib/pilot-cn/route.env
  log "路线决策已写入 /var/lib/pilot-cn/route.env"
}

# ===========================================================================
#  5. 运行时依赖
# ===========================================================================
check_runtime() {
  banner "5/6  运行时依赖"

  # 中文字体：不装的话打印中文 PDF 是方块
  if command -v fc-list >/dev/null 2>&1 && fc-list :lang=zh 2>/dev/null | grep -q .; then
    report_ok "中文字体" "已安装"
  else
    report_green "中文字体" "缺失，环境层会安装 ${CJK_FONT_PACKAGES[*]}"
  fi

  # PDF 引擎：wkhtmltopdf 是 frappe v16 的默认路径
  local pdf_ok=0
  if command -v wkhtmltopdf >/dev/null 2>&1; then
    pdf_ok=1; report_ok "PDF 引擎" "$(wkhtmltopdf --version 2>&1 | head -1)"
  fi
  if command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1; then
    pdf_ok=1; report_ok "PDF 引擎(Chromium)" "已安装（用于较新的打印功能）"
  fi
  if [[ "$pdf_ok" -eq 0 ]]; then
    report_red "PDF 引擎" "wkhtmltopdf 与 chromium 都没有，报表/发票打印会失败（不阻塞安装）"
  fi

  # 公网 IP 探测：pilot-cn 已把端点换成国内可达服务（上游用 8.8.8.8 + ifconfig.me，
  # 后者在国内要么不通、要么返回 IPv6，导致配域名时误报"域名没指过来"）
  # 注意 set -u：未定义变量直接报错，所以先给默认值再取第一个
  local probes="${PILOT_CN_IP_PROBE_URLS:-https://ip.3322.net,https://ipv4.icanhazip.com}"
  local ip_probe="${probes%%,*}"
  ip_probe="${ip_probe:-https://ip.3322.net}"
  local got_ip
  got_ip="$(curl -fsS --max-time 8 "$ip_probe" 2>/dev/null | tr -d '[:space:]' | head -c 40)"
  if [[ -n "$got_ip" ]]; then
    report_ok "公网 IP 探测" "${ip_probe} → ${got_ip}"
  else
    report_yellow "公网 IP 探测" "${ip_probe} 不可达；配域名时 A 记录建议可能为空（不阻塞安装）"
  fi

  # 数据库与缓存：Pilot 在 Linux 上不自己装 MariaDB/Redis（它要免密 sudo），
  # 上游靠 install.sh 装；pilot-cn 由环境层第 8 节负责，漏了就会 init 失败
  local pkg missing=()
  for pkg in mariadb-server redis-server; do
    dpkg -l 2>/dev/null | grep -q "^ii  $pkg " || missing+=("$pkg")
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    report_ok "数据库与缓存" "mariadb-server / redis-server 已安装"
  else
    report_green "数据库与缓存" "缺 ${missing[*]}；环境层第 8 节会安装"
  fi

  # 主仓库镜像是否真的加载成功。曾经因为 [[ -v ARRAY ]] 对关联数组恒为假，
  # REPO_MIRRORS 被「补默认值」的分支清空，frappe/erpnext 实际从 GitHub 拉，
  # 而界面上一切正常（路线 B 的代理掩盖了它）。
  local mirror_count=0
  if declare -p REPO_MIRRORS &>/dev/null; then
    mirror_count="${#REPO_MIRRORS[@]}"
  fi
  if [[ "$mirror_count" -gt 0 ]]; then
    report_ok "主仓库镜像" "${mirror_count} 条改写规则（frappe/erpnext → Gitee）"
  else
    report_yellow "主仓库镜像" "REPO_MIRRORS 为空；frappe/erpnext 会走通用代理而不是 Gitee"
  fi

  # systemd 用户服务：Pilot 的 bench 服务（per-user MariaDB / Redis / 进程管理）
  # 全跑在 systemctl --user 里。光有 loginctl 不够 —— 运行用户必须开 linger，
  # 否则没有 /run/user/<uid>，pilot init 会直接失败（Failed to connect to bus）
  if [[ -d /run/systemd/system ]] && command -v loginctl >/dev/null 2>&1; then
    local ru="${RUN_USER:-erpnext}"
    if ! id "$ru" >/dev/null 2>&1; then
      report_green "systemd 用户服务" "运行用户 $ru 尚未创建；建用户时会自动开启 linger"
    elif [[ "$(loginctl show-user "$ru" -p Linger --value 2>/dev/null)" == "yes" ]]; then
      report_ok "systemd 用户服务" "$ru 已开启 linger"
    else
      report_green "systemd 用户服务" "$ru 未开启 linger；建用户时会执行 loginctl enable-linger $ru"
    fi
  else
    report_block "systemd 用户服务" "不可用（容器或裁剪系统）；Pilot 的 bench 服务依赖 systemctl --user"
  fi

  # 已有服务冲突：接管开关为 0 时不应被打挂
  local svc conflicts=()
  for svc in mariadb nginx redis-server; do
    systemctl is-active --quiet "$svc" 2>/dev/null && conflicts+=("$svc")
  done
  if [[ "${#conflicts[@]}" -gt 0 ]]; then
    if [[ "$TAKEOVER_SYSTEM_SERVICES" -eq 0 ]]; then
      report_yellow "已有服务在运行" "${conflicts[*]}；TAKEOVER_SYSTEM_SERVICES=0，不会被打挂"
    else
      report_block "已有服务在运行" "${conflicts[*]} 会被停掉；如不希望，把 TAKEOVER_SYSTEM_SERVICES 设为 0"
    fi
  else
    report_ok "已有服务" "无冲突"
  fi
}

# ===========================================================================
#  6. pilot-cn 自身完整性
# ===========================================================================
check_self() {
  banner "6/6  pilot-cn 自身"

  local missing=()
  for f in bin/pilot pilot/cli.py pyproject.toml; do
    [[ -e "${CN_ROOT}/${f}" ]] || missing+=("$f")
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    report_ok "内置 Pilot 源码" "完整（上游 v0.0.64-pre-alpha）"
  else
    report_block "内置 Pilot 源码" "缺少 ${missing[*]}；仓库不完整，请重新克隆"
  fi

  if [[ -f "${CN_ROOT}/VERSION" ]]; then
    report_block "VERSION 文件" "存在！会让 Pilot 走 GitHub 升级通道。请删除它（见 docs/upstream/PINNED.md）"
  else
    report_ok "版本模式" "dev（pilot admin upgrade 走 git pull，国内可用）"
  fi

  if [[ -n "${PILOT_REPO_URL:-}" ]]; then
    report_ok "pilot-cn 仓库地址" "$PILOT_REPO_URL"
  else
    report_yellow "pilot-cn 仓库地址" "未配置；pilot admin upgrade 需要它"
  fi

  if [[ "$TLS_MODE" == "none" ]]; then
    report_yellow "HTTPS" "TLS_MODE=none，只提供 HTTP（内网够用，公网请改配置）"
  else
    report_ok "HTTPS" "TLS_MODE=$TLS_MODE，证书目录 $CERT_DIR"
  fi
}

# ===========================================================================
#  主流程
# ===========================================================================
main() {
  parse_args "$@"
  load_config
  detect_arch
  detect_os

  printf '\n%b\n' "${c_bold}pilot-cn 预检 —— 零副作用，不修改任何东西${c_reset}"
  printf '%b\n' "配置文件：${CN_CONF_FILE}"

  check_system
  check_mirrors
  check_sources
  check_pinned_dependencies
  check_runtime
  check_self

  banner "结论"
  printf '  可自动修 %d 项 · 需你选择 %d 项 · 可降级 %d 项 · 硬伤 %d 项\n' \
    "$CN_GREEN" "$CN_YELLOW" "$CN_RED" "$CN_BLOCK"
  printf '  依赖路线：%s\n' "${CN_ROUTE:-未决}"

  [[ -n "$JSON_OUT" ]] && write_preflight_result "$JSON_OUT" && log "结果已写入 $JSON_OUT"

  if report_summary; then
    ok "可以做下一步： sudo bash cn/setup-env.sh"
    return 0
  fi
  return 1
}

main "$@"
