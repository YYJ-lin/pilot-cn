# Pilot 国内版（pilot-cn）

> **一句话**：把 Frappe 官方指定的下一代部署工具 Pilot 改造过，让它在**国内网络环境下能一次装成 ERPNext**，装完还能中文、能升级、能装任何来源的应用。

---

## 目录

| 章节 | 你会看到什么 |
|---|---|
| [一、这是什么，有什么用](#一这是什么有什么用) | 它解决什么问题 |
| [二、在新服务器上从零装一套](#二在新服务器上从零装一套) | **怎么装** |
| [三、装完你会得到什么](#三装完你会得到什么) | 地址、密码、文件在哪 |
| [四、终端里怎么用](#四终端里怎么用) | **命令怎么敲** |
| [五、四个密码分别怎么改](#五四个密码分别怎么改) | **密码忘了 / 想换** |
| [六、改了代码之后怎么升级和部署](#六改了代码之后怎么升级和部署) | 开发流程 |
| [七、我们在官方基础上改了什么](#七我们在官方基础上改了什么) | 改动清单 |
| [八、常见问题](#八常见问题) | 出事了怎么办 |
| [九、安装流程与预检](#九安装流程与预检) | 装的时候每步在干什么 |
| [十、多渠道 Git 支持](#十多渠道-git-支持) | 为什么不局限 GitHub |
| [十一、开发与生产一体](#十一开发与生产一体) | 一台机器怎么兼顾两边 |
| [十二、升级与回滚](#十二升级与回滚) | 升级链有多稳 |
| [十三、已知限制](#十三已知限制) | 有哪些坑绕不开 |
| [十四、设计说明](#十四设计说明) | 四条铁律 + 三层架构 |
| [十五、待定问题](#十五待定问题需要拍板) | 还需要你拍板的事 |
| [十六、参考](#十六参考) | 外部链接 |

---

## 一、这是什么，有什么用

### Pilot 是什么

Pilot 是 Frappe **官方指定的下一代部署工具**，是 `frappe/bench` 的继任者（官方 bench 的 README 里就直接指向它，`frappe/bench-cli` 已改名为 `frappe/pilot`）。

它管的事：建运行环境、建站点、装应用、跑开发、部署生产、备份、升级、回滚，还带一个网页管理面板。

### 它原来的问题

Pilot 是给"网络畅通"的环境写的。在国内会卡在这些地方：

| 卡点 | 具体表现 |
|---|---|
| frappe / erpnext 源码在 GitHub | 经常不通，克隆失败 |
| pip / npm / apt 用官方源 | 慢，几十 KB/s |
| 三个钉死在 GitHub 的依赖 | **直接阻塞安装** |
| Python 运行时从 GitHub Releases 下载 | 经常不通 |
| 管理面板只有英文 | 用起来费劲 |

### pilot-cn 做了什么

**一行 frappe / erpnext 代码都不改**，只在外面加一层"国内适配"：

- 所有外部地址**收敛到一个配置文件**，全部换成国内镜像
- 在 **Git 层面做地址改写**，Pilot 自己都不知道仓库其实在 Gitee
- 支持从 **Gitee / 内网 Gitea / 本地目录**装应用
- 管理面板**中文化**（1000+ 条词表）
- 补上了装应用时的几个坑（进程崩溃拖垮全站、导入了却没装到站点）
- 提供**升级机制**，官方更新了也能跟，我们的改动不会丢

### 装完你能得到

| 能力 | 怎么用 |
|---|---|
| 一条命令装到管理面板 | `install-cn.sh`（剩下在面板向导里点） |
| 一条命令装好整套 ERPNext | `sudo bash install-cn.sh --full` |
| 中文管理面板 | 打开面板就是中文 |
| 从 Gitee 装应用 | 面板里粘贴 Gitee 地址 |
| 装自建应用 | 本地目录直接挂进 bench |
| 升级到上游新版本 | `cn/upgrade.sh <版本>` |
| 改了代码一键部署 | `sudo cn/deploy.sh --restart` |

---

## 二、在新服务器上从零装一套

### 前置条件

| 项 | 要求 |
|---|---|
| 操作系统 | **Ubuntu 24.04**（目前只验证过这个；Debian 12/13 理论可用） |
| 配置 | 建议 **4 核 8G**，硬盘 60G 以上 |
| 权限 | root |
| 网络 | **能访问 Gitee 即可，不需要能访问 GitHub** |

### 一条命令装到管理面板（默认）

```bash
curl -fsSL https://gitee.com/linxiansheng0409/pilot-cn/raw/main/install-cn.sh | sudo bash
```

或者先克隆再跑（推荐，方便改配置）：

```bash
git clone https://gitee.com/linxiansheng0409/pilot-cn.git ~/pilot-cn
cd ~/pilot-cn
sudo bash install-cn.sh
```

默认只做「环境层 + Pilot」：把 apt / pip / npm / MariaDB 源换好、装好 uv、建运行用户、
内置 Pilot，最后把管理面板拉在 **`http://<服务器IP>:7000`** 就停。

**frappe / erpnext 的仓库、版本、数据库都不预设**，全部由你在面板向导里现场选 —— 脚本不钉任何版本，
你要 v16.49.0 就是 v16.49.0，要 version-16 就是 version-16。

> GitHub 镜像：<https://github.com/YYJ-lin/pilot-cn>（国内安装请用上面的 Gitee 地址）

### 可用的选项

| 选项 | 作用 |
|---|---|
| （默认） | 装到面板为止：环境层 + Pilot + 拉起 7000 面板，仓库/版本/数据库在向导里选 |
| `--full` | 命令行装到底：建 bench、建站点、装 erpnext 应用（CI / 批量部署用） |
| `--gui` | 等同默认行为，保留以向后兼容 |
| `--skip-preflight` | 跳过环境预检 |
| `--skip-env` | 跳过环境层配置（已经配好了） |
| `--skip-bench` | 只装 Pilot，连面板都不建 bench（极少用） |
| `--bench-user USER` | 换运行用户（默认 `erpnext`） |

### 装完直接进面板

打开 `http://<服务器IP>:7000`，用脚本最后打印的**面板密码**登录（密码同时存在
`/var/lib/pilot-cn/secrets.env`），然后在向导里选三件事：

1. **数据库**：引擎（MariaDB / PostgreSQL）和连接方式（新建 / 复用本机 / 外部）；
2. **Frappe 仓库**：默认已预填 `mirrors.conf` 里配的地址（Gitee 镜像），也可以粘任意 Git 地址；
3. **Frappe 分支或 tag**：列表**直接来自该仓库**（`git ls-remote` 的 heads + tags），所以能选到 `v16.49.0` 这种发布版本。

⚠️ **erpnext 别选 v16.50.0 ~ v16.52.x**：那几版的源码有坏引用，装到一半会失败，
原因和替代版本见下方「已知问题」。

初始化完成后回到面板：建站点、装应用。**单站点 bench 会自动固定站点**，所以建完站点就能用 `http://<IP>:8000` 打开，不需要改 hosts。

### 装之前想改配置：只改一个文件

所有可调的东西都在 **`config/mirrors.conf`**：

| 想改什么 | 改哪个变量 |
|---|---|
| frappe / erpnext 版本 | `FRAPPE_BRANCH` / `ERPNEXT_BRANCH` |
| 站点名 / bench 名 | `SITE_NAME` / `BENCH_NAME` |
| 运行用户 | `RUN_USER` |
| 用哪个镜像源 | `APT_MIRROR` / `PIP_INDEX_URL` / `NPM_REGISTRY` … |
| 拉哪个 Gitee 仓库 | `FRAPPE_REPO` / `ERPNEXT_REPO` |
| 多装哪些应用 | `EXTRA_APPS` / `DEFAULT_SITE_APPS` |
| 默认密码 | `SITE_ADMIN_PASSWORD` / `PILOT_ADMIN_PASSWORD`（留空=随机生成） |
| 公司内网要走代理 | `HTTP_PROXY` / `HTTPS_PROXY` |

### 安装过程会做什么

```
① 预检         检查 7 个网络出口，输出一张健康表（不通过就停，不会装到一半炸）
② 环境层       把 apt / pip / npm / MariaDB 源换成国内镜像，装中文字体
③ 装 uv        走清华 pip 镜像
④ 建运行用户    创建 erpnext 用户（非 root），设密码，并给你（安装者）授权
⑤ 内置 Pilot   源码已经在仓库里，这一步不联网
⑥ 建 bench     建一个【未初始化】的 bench（不拉 frappe、不建站点）
⑦ 验收         检查 7000 端口在听、bench 进程在跑、面板应答 HTTP 200
```

默认流程约 **10-15 分钟**（含装 MariaDB / Node / Python 3.14）。
之后在面板向导里拉 frappe、建站点、装 erpnext，那部分约 20-40 分钟（前端构建最久）。

要命令行一把装完（老行为）：

```bash
sudo bash install-cn.sh --full
```

### 已知问题：装 erpnext 时报 "imports that don't resolve"

在面板里（或 `--full`）装 erpnext 时，如果版本落在 **v16.50.0 / v16.51.x / v16.52.x**，
会卡在 `get-app erpnext` 并回滚源码树，报错类似：

```
'erpnext' has imports that don't resolve:
erpnext.stock.doctype.stock_entry.services.manufacturing: No module named '...'
```

原因：这些版本里的
`erpnext/stock/doctype/stock_entry/services/material_transfer.py`
引用了同目录下的 `manufacturing.py` 和 `stock_entry_base.py`，
而这两个文件在那个 commit 里**根本不存在**（上游半截重构）。
2026-10 实测：当前最新的 **v16.52.1**、以及 `version-16` 分支顶端都还是这样，只有 `develop` 补齐了 ——
也就是说**「选最新版」目前反而装不上**。

Pilot 装应用前会逐条核对 import，命中这种坏引用就直接拒绝并回滚 —— 所以是「装不上」，不是「装坏了」。

**现在不用你动手了**：pilot-cn 会在校验前把这类「引用了不存在同级模块的死代码」
自动重命名为 `<name>.py.disabled-upstream`（见 `pilot/core/app/validator/known_defects.py`），
所以 v16.50.x ~ v16.52.x 也能正常安装 —— **实测 v16.52.1 一次装通**（安装日志里会有一行
`[pilot-cn] 已隔离已知上游缺陷：…`）。文件仍留在源码树里，`git checkout` 可还原，
运行时不受影响（没人 import 它）。

覆盖范围：安装、`pilot update`、切分支三条路径都走同一个 `validate()`，所以升级也不会再被它卡住。
若上游哪天补齐了 `manufacturing.py` / `stock_entry_base.py`，隔离会自动不再介入。

（注意 erpnext **没有 v16.53.0 这个 tag**，那是 frappe 的版本号，别照着 frappe 的版本号去选。）

### 面板「应用市场」里的版本为什么不是最新

面板不实时查 GitHub/Gitee，它读的是一份 **registry 快照**：`MARKETPLACE_REPO_URL`
（默认 `gitee.com/linxiansheng0409/marketplace`）里的 `apps/<app>.json`，克隆到
`/home/erpnext/pilot/system/registry-cache`。每个应用登记几个通道（stable / nightly）
加对应分支与 commit，面板就按这份清单渲染。

快照不会自动更新（没装定时器），要手动刷：

```bash
sudo -u erpnext -H bash /home/erpnext/pilot/cn/marketplace-refresh.sh
```

它会对每个应用跑 `git ls-remote` 取分支顶端与最新 tag，重写 `apps/*.json` 并
`git commit` 回 registry 仓库。**推送回 Gitee 需要凭据** —— 没有凭据时脚本会提示
「已 commit，push 失败」，此时只有本机面板看到新版，别人装不到，下次刷新又会被
`reset --hard` 拽回远端旧值。

### 装完之后

默认（装到面板）只打印**面板地址 + 面板密码**；站点名和 `Administrator` 密码是你在向导建站时自己设的。
所有密码同时存在 `/var/lib/pilot-cn/secrets.env`。

---

## 三、装完你会得到什么

以下用本机举例（把你的 IP 换成你自己的）。

### 访问地址

| 系统 | 地址 | 干什么用 |
|---|---|---|
| **ERPNext** | `http://192.168.1.102:8000` | 日常业务，员工用这个 |
| **ERPNext 账号** | `Administrator` | 密码见下方 |
| **Pilot 管理面板** | `http://192.168.1.102:7000` | 装应用 / 备份 / 看日志 / 改配置 |

> **用 IP 直接能打开，不用改 hosts。**
> Frappe 默认按请求的 `Host` 头选站点，所以直接开 `http://<IP>:8000` 本来会 404（`<IP> does not exist`）。
> Pilot 国内版做了两件事：**bench 里只有一个站点时，自动把它固定为默认站点**（等价于 frappe 的 `bench use`），
> 于是任何 Host 都落到它；面板里的「打开站点 / 一键登录」也会用**你访问面板时的那个地址**，点开就是 desk。
>
> 只有在建了**第二个**站点之后，才需要给每个站点配域名（或临时加 hosts）——多站点必须靠 Host 区分，这是 Frappe 的机制。

### 四个密码

| 密码 | 用途 | 谁能看到 |
|---|---|---|
| **ERPNext 站点管理员** | 每天登录 ERPNext | 你 + root |
| **Pilot 面板密码** | 登录 7000 面板 | 你 + root |
| **数据库 root 密码** | 内部维护，平时不碰 | root |
| **系统用户 erpnext** | SSH / 切用户调试 | root |

**查看命令**：

```bash
sudo cat /var/lib/pilot-cn/secrets.env
```

### 文件和目录都在哪

| 路径 | 是什么 | 能改吗 |
|---|---|---|
| `/home/erpnext/pilot` | **Pilot 本体 + 运行中的 bench** | ⚠️ 别手改，用脚本部署 |
| `/home/erpnext/pilot/benches/main` | 你的 bench（站点/配置/日志都在这） | 配置文件可以改 |
| `/home/erpnext/pilot/benches/main/sites/erp.local` | 站点目录（含 `site_config.json`） | 可以改 |
| `/home/erpnext/pilot/benches/main/logs` | 各进程日志 | 只读 |
| `~/pilot-cn` | **你自己的源码仓库**（改代码在这改） | ✅ 随便改 |
| `/var/lib/pilot-cn/secrets.env` | 所有密码（600） | 可以改，但要同步系统 |
| `~/pilot-cn/config/mirrors.conf` | **所有地址 / 版本 / 开关** | ✅ 主要就改这个 |

### 怎么确认装好了

```bash
ss -tlnH | grep -E ':7000|:8000|:11000|:13000'
```

- **默认（装到面板）**：`7000` 在听就说明装到位了。8000 / 11000 / 13000 要等你在向导里建完站点才会出现。
- **`--full`**：四个端口都在（7000 面板 / 8000 ERPNext / 11000 队列 / 13000 缓存）才算正常。

---

## 四、终端里怎么用

### ⚠️ 第一个要记住的：`bench` 命令没有了

Pilot 取代了老的 `bench`。所有命令改成 `pilot`：

```bash
bench --site erp.local list-apps          # ❌ 报 command not found
pilot -b main list-site-apps erp.local    # ✅ 正确写法
```

### 第二个：每个命令都要带 `-b main`

`-b` 是 bench 名字。可以设成环境变量省事：

```bash
export PILOT_BENCH=main
```

### 第三个：怎么以 erpnext 身份跑命令

`pilot` 装在 `/home/erpnext/pilot`，属于 `erpnext` 用户。完整写法：

```bash
sudo -u erpnext -H env XDG_RUNTIME_DIR=/run/user/1001 \
  /home/erpnext/pilot/bin/pilot -b main <命令>
```

**嫌长就在 `~/.bashrc` 里加个别名**（推荐）：

```bash
cat >> ~/.bashrc <<'EOF'
alias pilot='sudo -u erpnext -H env XDG_RUNTIME_DIR=/run/user/1001 /home/erpnext/pilot/bin/pilot'
EOF
source ~/.bashrc

# 之后直接：
pilot -b main list-site-apps erp.local
```

### 常用命令速查

**启动 / 停止**

```bash
pilot -b main start     # 启动（前台运行，Ctrl+C 停）
pilot -b main stop      # 停止
pilot -b main restart   # 重启（仅生产模式）
```

> 想让它在后台跑，见下方"后台运行的正确姿势"。

**查看**

```bash
pilot -b main list-apps                  # bench 里下载了哪些应用
pilot -b main list-site-apps erp.local   # 站点实际装了哪些应用
pilot ls                                 # 本机有哪几个 bench
```

**装应用（重点：分两步）**

```bash
# 第一步：下载到 bench（Gitee / GitHub / 内网 Gitea / 本地目录都行）
pilot -b main get-app https://gitee.com/linxiansheng0409/YYJ_translate

# 第二步：装到站点（这一步才会建表、才会在 ERPNext 里出现）
pilot -b main install-app erp.local yyj_translate
```

> **只做第一步 = 应用躺在 bench 里，ERPNext 里看不到。**
> 单站点 bench 下，面板里点"导入应用"已经会自动帮你做第二步。

**卸载**

```bash
pilot -b main uninstall-app erp.local yyj_translate   # 从站点卸载
pilot -b main remove-app yyj_translate                # 从 bench 移除
```

**备份 / 迁移**

```bash
pilot -b main frappe --site erp.local backup    # 备份（文件在 sites/erp.local/private/backups）
pilot -b main frappe --site erp.local migrate   # 跑数据库迁移
```

**进控制台 / 用 Frappe 原生命令**

```bash
pilot -b main frappe --site erp.local console          # Python 控制台
pilot -b main frappe --site erp.local --help           # 所有 Frappe 原生命令
pilot -b main frappe --site erp.local execute frappe.ping   # 直接执行函数
```

**建东西**

```bash
pilot -b main new-site newsite.local              # 新建站点
pilot -b main new-app my_custom_app               # 新建自建应用
pilot -b main new otherbench                      # 新建另一个 bench
```

### 后台运行的正确姿势

`pilot -b main start` 是**前台**的，关掉终端就停。要后台跑：

```bash
sudo -u erpnext -H env XDG_RUNTIME_DIR=/run/user/1001 bash -c \
  'cd /home/erpnext/pilot && setsid nohup ./bin/pilot -b main start \
   > benches/main/bench-start.log 2>&1 < /dev/null &'
```

**或者直接用它**（推荐）：

```bash
sudo cn/deploy.sh --restart
```

### 日志在哪

```bash
/home/erpnext/pilot/benches/main/bench-start.log          # 所有进程的合并输出（排错先看这个）
/home/erpnext/pilot/benches/main/logs/                    # web / worker / scheduler 各自的日志
/home/erpnext/pilot/benches/main/sites/erp.local/logs/    # 站点级日志
```

实用命令：

```bash
# 实时看所有输出
tail -f /home/erpnext/pilot/benches/main/bench-start.log

# 看 web 日志最后 50 行
tail -50 /home/erpnext/pilot/benches/main/logs/web.log
```

---

## 五、四个密码分别怎么改

### ① ERPNext 站点管理员密码

**改法一（推荐，界面里改）**

登录 ERPNext → 右上角头像 → **我的设置** → **修改密码**

**改法二（命令行，忘了密码时用）**

```bash
pilot -b main frappe --site erp.local set-admin-password
# 会提示输入新密码
```

### ② Pilot 管理面板密码

```bash
pilot -b main set-admin-password
# 会安全地提示你输入新密码

# 或者一步到位：
pilot -b main set-admin-password --password '新密码'
```

### ③ 数据库 root 密码

Pilot 自己起了一套隔离的 MariaDB：

```
端口:   3310（只监听 127.0.0.1，外网连不上）
socket: /home/erpnext/pilot/databases/mariadb/run/mysqld.sock
```

改法：

```bash
sudo -u erpnext mariadb \
  --socket=/home/erpnext/pilot/databases/mariadb/run/mysqld.sock \
  -u root -p
```

进去之后：

```sql
ALTER USER 'root'@'localhost' IDENTIFIED BY '新密码';
FLUSH PRIVILEGES;
```

> ⚠️ **改完必须同步改 `/var/lib/pilot-cn/secrets.env` 里的 `DB_ROOT_PASSWORD`**，
> 否则下次重跑脚本或某些管理操作会对不上。

### ④ 系统用户 erpnext 的密码

```bash
sudo passwd erpnext
```

（改完同样建议同步 `secrets.env` 里的 `RUN_USER_PASSWORD`）

### 附：`secrets.env` 的规则

`/var/lib/pilot-cn/secrets.env`（权限 600，只有 root 能读）是**所有密码的唯一真相**：

| 情况 | 怎么办 |
|---|---|
| 断点续跑安装 | 以这个文件为准，不会重新生成 |
| 想全部重新随机生成 | 删掉这个文件，重跑安装脚本 |
| 改了这里的登录密码 | **还要按上面 ①②④ 的方法同步改系统里的密码** |
| 改了这里的数据库密码 | 还要按 ③ 的方法改数据库里的 |

内容长这样：

```bash
SITE_ADMIN_PASSWORD='...'    # ERPNext 站点管理员
PILOT_ADMIN_PASSWORD='...'   # Pilot 面板
DB_ROOT_PASSWORD='...'       # 数据库 root
RUN_USER_PASSWORD='...'      # 系统用户 erpnext
```

### 给运行用户的授权（VSCode 看不到文件时）

安装脚本会自动把你（执行安装的 SSH 用户）加进 `erpnext` 组，并设一条 ACL，让你能浏览 `/home/erpnext`。

**如果 VSCode 左侧文件树看不到 `/home/erpnext`**：

```bash
# 确认你在 erpnext 组里
id -nG | tr ' ' '\n' | grep erpnext

# 确认家目录对组可进入
ls -ld /home/erpnext          # 应该形如 drwxr-x---

# 补一条立即生效的 ACL（不用重登）
sudo setfacl -m u:$USER:rx /home/erpnext
```

> 组变更是**重新登录**后才对终端生效；ACL 是**立即**生效的。两个都做了最稳。

---

## 六、改了代码之后怎么升级和部署

### 日常：改了 pilot-cn 的源码

```bash
sudo cn/deploy.sh              # 同步源码到运行实例
sudo cn/deploy.sh --restart    # 顺便重启 bench（改了 Python 代码必须重启）
```

`deploy.sh` 会同步 `pilot/ admin/ cn/ config/ install-cn.sh`，修正属主，并且**保护已部署的前端产物**（不会被 `--delete` 误删）。

### 改了前端（Vue）源码

前端是编译产物，改完**必须重新编译**，否则界面还是旧的：

```bash
cd admin/frontend/dashboard
npm install          # 第一次要装依赖
npm run build        # 编译到 admin/backend/static/dashboard

sudo cn/deploy.sh --restart
```

### 跟随官方 Pilot 升级

```bash
cn/upgrade.sh --list              # 看有哪些上游版本可选
cn/upgrade.sh v0.0.65-pre-alpha   # 升级到指定版本
```

它会自动做这些：

```
拉上游 tag
  → 用上游内容替换 pilot/ 和 admin/
  → 删掉"我们加过、上游没有"的文件
  → git apply --3way 重放我们的补丁
  → 重新编译三个前端（dashboard / editor / in-app-embed）
  → 抽查关键改动是否都在
```

我们自己的层（`cn/`、`config/`、`install-cn.sh`）**不在 `pilot/` `admin/` 里，升级不会碰**。

### ⚠️ 改了源码后必做：重新生成补丁

否则升级时你的改动会被冲掉：

```bash
git diff upstream-base -- pilot/ admin/ ':(exclude)admin/frontend/in-app-embed/dev.sh' \
  > cn/patches/pilot-cn-mods.patch
```

### 提交推送（两个远端）

```bash
git add -A && git commit -m "你的改动"
git push git@github.com:0409linxiansheng/pilot-cn.git main   # GitHub
git push gitee main                                          # Gitee
```

---

## 七、我们在官方基础上改了什么

全部源码改动 = **30 个文件**，集中在 `cn/patches/pilot-cn-mods.patch`（改了源码记得按[第六节](#六改了代码之后怎么升级和部署)重新生成）。

### 已实现

| # | 改动 | 涉及文件 |
|---|---|---|
| 1 | 多渠道 Git 支持（Gitee / 本地目录 / 任意 Git 服务器） | `pilot/integrations/git/` |
| 2 | 应用仓库自动识别应用名（去掉 GitHub 硬编码） | `pilot/core/app/repository.py`、`pilot/internal/git.py` |
| 3 | 应用市场 registry 指向 Gitee（可用环境变量覆盖） | `pilot/core/registry_cache.py` |
| 4 | **中文界面**：运行时注入，不改前端源码；后端每次请求重读词表，**改翻译不用重启** | `admin/backend/app.py` + `cn/i18n/pilot-zh.js` |
| 5 | **进程崩溃不拖垮整个 bench**：只有 redis / admin 是致命进程，web / worker / scheduler / socketio 崩了只自动重启自身 | `pilot/managers/processes/local.py` |
| 6 | **导入应用自动装到唯一站点**：单站点 bench 下不再"只下载不安装" | `admin/backend/api/v1/apps.py` |
| 7 | 市场页自动选中唯一站点 | `admin/frontend/.../useMarketplace.ts` |
| 8 | 导入应用文案不再只写 GitHub（支持 Gitee 了） | `admin/frontend/.../AddAppFromGithubDialog.vue`、`search/index.ts` |
| 9 | 隐藏 Cloud Settings（自建环境用不到 Frappe Cloud） | `admin/backend/api/v1/auth.py`、`middleware.py` |
| 10 | **公网 IP 探测改用国内可达服务**：NAT 机器不再误报"域名没指过来" | `pilot/core/adapters/domain_provider.py` |
| 11 | **上游升级机制**：补丁 + 重放脚本 + 升级后自动重编译前端 | `cn/upgrade.sh`、`cn/patches/` |
| 12 | **部署脚本**：源码 → 运行实例一键同步（含前端产物） | `cn/deploy.sh` |
| 13 | 安装脚本给运行用户设密码 + 给安装者授权（VSCode 能看文件） | `install-cn.sh`、`cn/lib/core.sh` |
| 14 | **向导预填读真实的 bench.toml**：仓库/分支取 `name = "frappe"` 那条 `[[apps]]`（以前取第一条），配置写坏也仍然能预填 | `admin/backend/api/v1/setup/config.py`、`pilot/config/bench.py` |
| 15 | **向导分支列表带 tag**：`git ls-remote --heads --tags`（走 git 改写通道，不碰 api.github.com，拉不到时退回内置列表），只列版本类 ref、缓存 10 分钟 | `pilot/integrations/git/refs.py`、`admin/backend/api/v1/setup/__init__.py` |
| 16 | **单站点 bench 自动固定站点**（`default_site`）：`http://<IP>:8000` 直接可用，不用改 hosts；面板的站点地址 / 一键登录用访问面板的地址；建站后立即生效 | `pilot/core/bench/config_files.py`、`pilot/core/site/login.py`、`pilot/tasks/new_site.py` |
| 17 | **装/更新应用构建完资产后重启 web**：旧资产清单被缓存时，页面里 hash 化的 js/css 会全部 404（表现为登录后白屏） | `pilot/core/app/__init__.py`、`pilot/core/bench/runtime.py` |
| 18 | **服务器 bench 默认关掉常驻 JS 监听**（`watch_apps_js=false`）：它会在 web 读过资产清单后再换一遍 hash，还常驻占 CPU | `install-cn.sh`、`cn/install-bench.sh`、`cn/lib/core.sh` |
| 19 | **应用 `dev` extra 解析失败时降级安装**：frappe 把 pypika 钉在 fork 上，和它自己的 `pypika-stubs` 冲突，不能因此中断 init | `pilot/managers/environment.py` |
| 20 | **向导失败后残留的 `.wizard-active` 自动清理**：bench 已初始化时不再把用户推回向导 | `admin/backend/api/v1/core.py` |
| 21 | **市场应用更新时校验失败只告警不中断**：安装本来就不校验市场应用（钉住的是已发布的 commit），上游偶发的"孤立文件引用了没提交的模块"不该让整次更新失败 | `pilot/core/bench/update.py` |
| 22 | **记录的仓库地址不再被 insteadOf 污染**：读 `.git/config` 原始值，避免把 `ghfast.top/...` 写进 bench.toml 后和市场 registry 对不上 | `pilot/internal/git.py` |

### 还没做

| # | 改动 | 现状 |
|---|---|---|
| 1 | `pilot doctor` 预检子命令 | 已有独立脚本 `cn/preflight.sh`，未接进 CLI |
| 2 | 证书目录可配置（`cert_dir`） | 未做；国内建议用云厂商证书 |
| 3 | `--no-takeover`（不接管已有 MariaDB / Redis / nginx） | 未做（`mirrors.conf` 里有开关，但 Pilot 侧还没接） |
| 4 | S3 备份增加国内厂商 | 未做 |
| 5 | `install.sh` 国产系统适配（麒麟 / 统信 / openEuler） | 未做（只验证过 Ubuntu 24.04） |
| 6 | 网页里加预检页 | 未做 |

### 明确不做的事

| 不做 | 原因 |
|---|---|
| ❌ 改 `frappe` / `erpnext` 代码 | 会毁掉持续升级能力（它们是强制覆盖升级的） |
| ❌ 把 Pilot 塞进 Docker | Pilot 是宿主机编排器，两套编排会抢地盘 |
| ❌ 重写升级 / 迁移链 | 现有的备份 + 双向回滚设计很扎实，重写风险极高 |

---

## 八、常见问题

### 面板打不开 / 一直显示"重连 bench"

bench 挂了。**一键恢复**：

```bash
sudo cn/deploy.sh --restart
```

然后看日志找原因：

```bash
tail -80 /home/erpnext/pilot/benches/main/bench-start.log
```

> 上游 Pilot 的原始行为是"任何一个进程崩，整个 bench 全停"。**我们已经打了补丁**，
> 现在只有 redis / admin 崩了才会全停，web / worker / scheduler 崩了只重启自己。

### 装应用成功了，但 ERPNext 里没出现

`get-app`（下载）和 `install-app`（装到站点）是**两步**，你只做了第一步。补上：

```bash
pilot -b main install-app erp.local <应用名>
```

验证：

```bash
pilot -b main list-site-apps erp.local
```

> 单站点 bench 下，面板里"导入应用"已经会自动做第二步（我们改的）。

### 域名配置在哪

**面板 → Sites → 点进站点 → Settings 标签页 → 往下滚到 Domains**。

⚠️ **但这个区块只在生产模式下显示**。开发模式（`bench.toml` 里 `[production] enabled = false`）下，前端**直接不渲染**这块。

要用域名，两条路：

| 方案 | 命令 | 代价 |
|---|---|---|
| 开生产模式 | `pilot -b main setup production --admin-domain admin.example.com` | 会**取代** `pilot start`，开发环境就没了 |
| 建第二个 bench 专做生产 | `pilot -b main new production` 然后在新 bench 上 setup production | 配置量大，但这是"开发 + 生产一体"的正确做法 |

### 配域名时提示"域名还没指向这里"

我们已经修了公网 IP 探测（原来用 `8.8.8.8` + `ifconfig.me`，国内不通还会返回 IPv6）。
现在用 `ip.3322.net` 等国内可达服务，并且**只接受 IPv4**。

也可以用环境变量指定自己的探测服务：

```bash
export PILOT_CN_IP_PROBE_URLS="https://你的服务/ip,https://ip.3322.net"
```

### 报错 "command not found: bench"

Pilot 取代了 `bench`。所有命令改成 `pilot -b main ...`，详见[第四节](#四终端里怎么用)。

### 用 IP 打开显示「xxx does not exist」/ 登录后白屏

这两种都是**路由**和**前端资产**的问题，新版已经自动处理：

- **`192.168.1.102 does not exist`**：Frappe 按请求的 `Host` 头选站点。单站点 bench 现在会自动把唯一站点固定为默认站点（`common_site_config.json` 里的 `default_site`），`http://<IP>:8000` 直接可用。如果这个键被手动删掉，重启一次 `pilot -b main start` 会重新写上。
- **能登录但页面空白、浏览器控制台一堆 404**：浏览器缓存了旧页面的 hash 资源名。先 `Ctrl+F5` 强刷；仍不行就 `pilot -b main stop && pilot -b main start` 重启一次（新版装应用后会自动重启 web，正常不会出现）。
- **建了第二个站点之后打不开**：多站点只能靠 Host / 域名区分，给每个站点配域名，或临时在客户端 hosts 里加一行；单站点不受影响。

### 忘了密码

```bash
sudo cat /var/lib/pilot-cn/secrets.env
```

忘了 ERPNext 管理员密码、又进不去界面：

```bash
pilot -b main frappe --site erp.local set-admin-password
```

### 想彻底重来

```bash
# 只重置站点数据（应用保留）
pilot -b main frappe --site erp.local --help    # 找 reset / reinstall

# 全部重新生成密码
sudo rm /var/lib/pilot-cn/secrets.env
```

---

## 九、安装流程与预检

### 完整流程（七步）

```
【第 0 步】从 Gitee 拉取（一条命令）
              ↓
【第 1 步】自动预检
              输出：🟢 可自动修 / 🟡 要你选 / 🔴 能降级 / ⛔ 硬伤
              ↓
【第 2 步】自动配源 + 问你要选的那几项
              ↓
【第 3 步】重新预检
              没有 ⛔ → 继续
              有 ⛔ → 告诉你怎么处理，停止（不会装到一半炸）
              ↓
【第 4 步】安装 Pilot（源码已内置，dev 模式）
              ↓
【第 5 步】安装 Frappe + ERPNext
              ⚠️ 不改它们的代码，只写配置文件
              ↓
【第 6 步】在 Pilot 面板里：看预检结果 / 改源 / 换版本再预检
              ↓
【第 7 步】日常：每次升级前再预检一次
```

### 为什么主入口放在 Gitee 而不是 GitHub

**GitHub 本身就是国内不稳定的源头之一。** 如果用户的第一个动作是"从 GitHub 拉脚本"，那脚本写得再好也没用——第一步就卡住了。

所以：**Gitee 作为主入口，GitHub 放一份作为备份**，并且引导脚本**自包含**，从 Gitee 仓库里拉自己需要的一切。

### 预检：整个项目最有价值的一环

现在的痛点不是"装不上"，而是**"装到一半失败，不知道哪里错了"**。7 个外网出口分散在 30 分钟的安装过程里，每步的报错都很难懂。

预检把这件事变成：**开跑前 10 秒，给你一张链路健康表 + 每一处的处理办法。**

#### 结果分四类

| 类型 | 例子 | 脚本怎么办 |
|---|---|---|
| 🟢 **能自动修** | Python 源、npm 源、字体、git 改写 | 直接改掉，不打扰你 |
| 🟡 **要你选** | 要不要走代理、装不装 Chromium | 弹问题让你选 |
| 🔴 **修不了，但能降级** | 预构建资源下不动 | 明确告知"会慢一点，**功能不受影响**"，问你是否继续 |
| ⛔ **修不了，且是硬伤** | 网络完全不通 | 停止，告诉你怎么处理 |

> **"通过"的标准是：没有 ⛔ 项。** 🔴 项允许带警告继续，否则用户会被一堆无害的警告吓得不敢往下走。

#### 输出样例

```
$ cn/preflight.sh

链路健康检查
────────────────────────────────────────────────────────────
[✓] git → 源码仓库              312ms   经 insteadOf 改写
[✓] PyPI 索引 (清华)             89ms
[✓] npm registry (npmmirror)    120ms
[✓] Python 3.14 运行时 (南大)    210ms
[✓] Node 24 二进制 (npmmirror)   95ms
[✗] GitHub Releases             超时    → 预构建资源不可用
                                        降级：回退本地编译，功能可用
[!] 中文字体                     缺失    → 修复：apt install fonts-noto-cjk
[!] 公网 IP 探测                 失败    → 配域名时会误报，需换探测端点

7/8 通过 · 1 个降级项 · 1 个待修
```

#### 预检会出现三次，共用一套检查逻辑

| 什么时候 | 用什么 | 状态 |
|---|---|---|
| 装 Pilot **之前** | 独立脚本 `cn/preflight.sh` | ✅ 已实现 |
| 装 Pilot **之后** | `pilot doctor` 子命令 | 🔧 未接进 CLI |
| 装好之后（可选） | Pilot 面板里加一页 | 🔧 未做 |

---

## 十、多渠道 Git 支持

用户可以选择从**任何渠道**拉源码和应用，不再局限于 GitHub。

| 渠道 | 支持方式 |
|---|---|
| **Gitee** | 原生支持（含 API：列分支、查默认分支、读文件、私有仓库 token） |
| **GitLab / 内网 Gitea** | 通用兜底（纯 git 命令） |
| **任意 Git 服务器** | 通用兜底 |
| **本地目录** | 原生支持（`/path/to/repo` 或 `file:///path/to/repo`） |
| GitHub | 原生支持（保持现状） |

### 原理：Pilot 本来就为此设计

Pilot 的 git 模块**第一行就写着设计目标**：

```python
# pilot/integrations/git/__init__.py:1
"""Provider-agnostic Git integration for private app repositories."""
```

而装应用本来就是普通的 `git clone`，所以我们做的事情是**把它想做的事补完，不是改它的设计**。

### 各能力现状

| 能力 | 现状 |
|---|---|
| 命令行 `pilot get-app <任意 git 地址>` | ✅ 可用 |
| 从 Gitee 装应用 | ✅ 可用 |
| 从本地目录装应用 | ✅ 可用 |
| 切换分支 / 升级 | ✅ 纯 git 操作，任意渠道可用 |
| 面板里粘贴地址、自动识别应用名 | ✅ 已修（原来只支持 GitHub） |
| 面板的仓库 / 分支选择器 | ✅ 走通用 provider |
| 预构建资源加速 | ⚠️ 非 GitHub 时自动降级为本地编译（只影响速度） |

### Git 层面还有一个"隐形改写"

`/etc/gitconfig` 里写了地址改写规则（`url.<镜像>.insteadOf`）：

```
bench.toml 里写的仍是 https://github.com/frappe/frappe
        ↓ git 传输时自动改道
实际从 https://gitee.com/linxiansheng0409/frappe 拉
```

**好处**：Pilot 完全不知道仓库实际在 Gitee，升级、切分支、更新全都自动走镜像，不需要改 Pilot 代码，也不需要改 `bench.toml`。

规则在 `config/mirrors.conf` 的 `REPO_MIRRORS` 里配。

---

## 十一、开发与生产一体

### 先说实话：开发和生产在传统上是互斥的

- 开发需要**热重载、未压缩资源、开发者模式**
- 生产需要 **nginx + 进程守护 + 压缩资源 + HTTPS**

**没有任何工具能把两者塞进同一个实例**（Pilot 不行，Docker 官方也明确说 "Development, testing, and production are separate workflows"）。

### Pilot 给的方案：共享基础设施，隔离运行实例

```
服务器
├── MariaDB / PostgreSQL     ← 跨 bench 共享（配置在 common_config.toml）
├── bench: dev               ← 开发实例
│   ├── Redis 13000/11000
│   ├── pilot -b dev start   → :8000，热重载全开
│   └── 站点：dev.localhost
└── bench: prod              ← 生产实例
    ├── Redis 13100/11100
    ├── systemd + nginx + HTTPS
    └── 站点：erp.example.com
```

- **共享数据库服务**，各自独立的站点目录、Redis 端口、nginx 虚拟主机
- 代码流：dev 上开发 → 推送到 Git → prod 上更新 + 迁移
- 一个面板可以同时管这两个 bench

### 三个层次的"一体"，支持程度不同

| 层次 | 支持吗 |
|---|---|
| 同一台机器上同时有开发和生产环境 | ✅ 完全支持，而且是 Pilot 的设计核心 |
| 同一个 bench 既跑生产、又能做定制开发 | ✅ 支持（可开站点级开发者模式）<br>⚠️ 但生产 bench **不装应用的 dev 依赖** |
| 同一个 bench 既是 `pilot start` 开发服务器又是生产服务 | ❌ 不支持（两者都要占用同一个 web 端口） |

> 你现在这台机器就是**第三种情况**：单 bench + 开发模式。
> 所以面板里的域名区块不显示（见[第八节](#八常见问题)的说明）。
> 想两边都要，就按上面的图建**第二个 bench**。

---

### 以后想切换到生产模式：完整步骤

#### 先搞清楚代价

| | 开发模式（你现在） | 生产模式 |
|---|---|---|
| 服务托管 | `pilot start` 前台跑 | **systemd**（开机自启、崩了自动拉起） |
| Web 入口 | Pilot 自带的开发服务器 | **nginx** |
| 重启命令 | `pilot start` | `pilot -b main restart` |
| Domains 配置界面 | ❌ 不显示 | ✅ 显示 |
| 部署脚本 | `sudo cn/deploy.sh --restart` | 同一条命令（脚本会自动识别走 `pilot restart`） |

**关键：生产模式会取代 `pilot start`。** 服务改由 systemd 托管，开机自启。

#### 第 1 步：准备一个管理域名

生产模式**必须**提供一个管理域名（面板的访问地址）。三选一：

| 方案 | 填什么 | 前提 |
|---|---|---|
| **内网 IP**（最简单） | `192.168.1.102` | 无，立刻能用 |
| 内网域名 | `admin.erp.local` | 加 hosts / 内网 DNS |
| 公网域名 | `admin.example.com` | 域名 + DNS + 备案 + 路由器映射 80/443 |

先确认域名能解析到本机：

```bash
getent hosts admin.erp.local      # 换成你选的域名
```

#### 第 2 步：备份（强烈建议）

```bash
pilot -b main frappe --site erp.local backup
```

#### 第 3 步：执行切换

```bash
sudo -u erpnext -H env XDG_RUNTIME_DIR=/run/user/1001 \
  /home/erpnext/pilot/bin/pilot -b main setup production \
  --admin-domain 192.168.1.102
```

它会依次做这些：

```
切换进程管理器（dev → systemd）
  → 启动生产服务（systemd units）
  → 生成并加载 nginx 配置
  → （加了 --tls 时）申请 Let's Encrypt 证书
  → 构建生产版管理面板
  → 装监控与日志收集
  → 把 production.enabled = true 写进 bench.toml
```

**关于 HTTPS**：不加 `--tls` 就是纯 HTTP，内网够用。要 HTTPS 就加：

```bash
... --admin-domain admin.example.com --tls --letsencrypt-email you@example.com
```

⚠️ 国内未备案的域名 80 端口会被运营商拦，`--tls` 必然失败。这种情况请用云厂商证书手动放置。

#### 第 4 步：验证

```bash
# 服务是否起来
systemctl --user list-units --no-pager | grep -i pilot
# nginx 配置是否正确
sudo nginx -t
# 面板是否能访问
curl -I http://192.168.1.102:7000
```

#### 第 5 步：以后怎么重启 / 部署

```bash
# 重启生产服务
pilot -b main restart

# 改完代码后部署（deploy.sh 会自动识别生产模式）
sudo cn/deploy.sh --restart
```

#### 想退回来（回到开发模式）

```bash
pilot -b main remove production    # 移除生产部署（保留日志、证书、管理域名）
pilot -b main start                # 回到开发模式
```

`remove production` 会把 `production.enabled` 改回 `false`，并清掉 systemd units 和 nginx 配置。

---

## 十二、升级与回滚

这是 Pilot 相对于"自己写脚本部署"最大的优势，**必须保留**。

### 升级 Pilot 自己（我们的补丁层）

```bash
cn/upgrade.sh --list              # 看有哪些上游版本
cn/upgrade.sh v0.0.65-pre-alpha   # 升级到指定版本
```

它会：拉上游 → 替换 `pilot/` `admin/` → 重放我们的补丁 → 重编译前端 → 抽查关键改动。

### 升级应用（Frappe / ERPNext）

Pilot 的迁移链会自动执行：

```
查更新 → 备份 → 拉代码 + 装依赖 + 构建资源 → 数据库迁移 → 重启服务
                          ↓ 失败
                  自动回滚应用代码
                          ↓ 迁移失败
                  自动回滚站点数据
```

**这条链的"备份 + 双向回滚"是自己写脚本最难做对的部分，也是最不该自己重写的地方。**

### ⚠️ 改了源码后必做

否则升级时你的改动会被冲掉：

```bash
git diff upstream-base -- pilot/ admin/ ':(exclude)admin/frontend/in-app-embed/dev.sh' \
  > cn/patches/pilot-cn-mods.patch
```

---

## 十三、已知限制

1. **系统要求**：Pilot 只支持 **Ubuntu 24.04+ / Debian 12+**。这是硬性要求，选错系统全盘重来。
2. **不在官方文档里**：frappe v16 / erpnext v16 的 README 目前还没提到 Pilot，官方安装文档仍指向 Docker 和 bench。Pilot 是 bench 官方指定的继任者，但尚未接管 erpnext 的安装文档。
3. **要跟着官方更新**：我们的 fork 需要定期从官方同步，否则会逐渐过时。
4. **第三方代理不稳定**：git 改写的"加速代理"路线依赖公共加速站，存活率不稳定；建议走 Gitee 导入或自建反代。
5. **源码镜像不同步**：Gitee 镜像仓库不会自动跟随上游更新，需要手动同步。
6. **wkhtmltopdf 版本**：apt 版不是 patched-qt 构建，复杂打印格式可能异常。打印中文 PDF 需要系统装中文字体（安装脚本已自动装 `fonts-noto-cjk`）。
7. **域名备案**：国内服务器用域名对外提供服务必须备案，否则 80 端口被运营商拦，自动申请 HTTPS 证书必然失败——这也是为什么证书要支持手动放置。
8. **应用兼容性**：部分第三方应用（如 helpdesk 1.31）前端依赖的 `frappe-ui` 版本与很新的 frappe（v16.51）不匹配，构建会失败。这属于上游版本漂移，不是 pilot-cn 的问题。
9. **多站点靠 Host 区分**：一个 bench 只有一个站点时，Pilot 把它固定为默认站点，`http://<IP>:8000` 直接可用；一旦有第二个站点，就必须给每个站点配域名（或客户端 hosts），因为 HTTP 请求里只有 Host 头能说明"要访问哪个站"。

---

## 十四、设计说明

### 四条铁律

这四条是整个项目的设计底线。任何改动如果违反其中一条，方案就要推翻重来。

#### 铁律 1：绝不修改 `frappe` 和 `erpnext` 的代码

**原因**：Pilot 升级应用时执行的是**强制覆盖**（`git reset --hard origin/<分支>`）。你在应用代码里做的任何修改，升级时会被**静默清除**；如果改动涉及数据库结构，升级会直接失败，从此再也升不上去。

**怎么判断哪些会被覆盖**——记住这一条就够了：

| 目录 | 升级时 |
|---|---|
| `apps/` 里（frappe、erpnext 的**代码**） | ❌ 全部被覆盖 |
| `sites/` 里（站点**配置**） | ✅ 保留 |
| `config/` 里（工作台配置） | ✅ 保留 |
| 系统里装的软件（字体等） | ✅ 保留 |

> **一句话：代码会被覆盖，配置会保留。** 所以所有国内适配都写在配置里，不写进代码。

#### 铁律 2：环境层用配置文件，不用环境变量

**原因**：bench 的后台服务和面板的后台任务，都跑在 systemd 用户服务里。**你在命令行里 `export` 的变量，这些后台服务读不到。**

所以镜像源、代理这些配置，必须写成**文件**（`/etc/uv/uv.toml`、`/etc/npmrc`、`/etc/gitconfig` 等），而不是环境变量。

#### 铁律 3：对 Pilot 的修改必须提交进自己的代码仓库

**原因**：Pilot 升级自己时会执行 `git pull`。你在服务器上手动改的文件，要么产生冲突，要么被覆盖。

#### 铁律 4：所有外部地址收敛到一处配置

**原因**：Pilot 官方迭代很快。如果外部地址散落在各个文件里，官方一更新，维护成本就会爆炸。所以全部集中在 **`config/mirrors.conf`**。

### 三层架构

核心思路：**把国内适配全部推到应用代码之外。**

```
┌─ 第 0 层：环境层（配置文件 + 系统软件）──────────────┐
│  /etc/uv/uv.toml         PyPI 镜像 + Python 运行时镜像 │
│  /etc/npmrc              npm 镜像                      │
│  /etc/gitconfig          git 地址改写                   │
│  ~/.config/environment.d 代理（让后台服务也能读到）     │
│  /etc/sudoers.d/         代理穿透 sudo                 │
│  系统字体                 中文字体（否则 PDF 是方块）    │
│                                                        │
│  ← 永不碰应用代码，永久有效，任何升级都不影响           │
├─ 第 1 层：Pilot 层（我们的补丁，尽量少）────────────────┤
│  · 外部地址收敛到一处配置（铁律 4）                     │
│  · 多渠道 Git 支持（Gitee / 本地 / 任意）               │
│  · 管理面板中文化                                       │
│  · 进程崩溃隔离（不再一个进程崩全站挂）                  │
│  · 公网 IP 探测改国内可达                               │
│                                                        │
│  ← 补丁形式，升级时自动重放，不会被覆盖                  │
├─ 第 2 层：frappe / erpnext ──────────────────────────┤
│  ⛔ 一行不改。用官方发布版本。                          │
│  升级、备份、回滚全部由 Pilot 的迁移链负责。             │
└────────────────────────────────────────────────────────┘
```

**关键点：第 0 层的配置对所有路线都有效。** 无论你最终用 bench 还是 Pilot，环境层只做一次。

### 国内网络到底卡在哪（7 个出口）

ERPNext 安装过程要访问 7 类外部资源，分属不同的包管理器。**每一个都要单独处理。**

| # | 环节 | 官方默认源 | 国内状况 | 国内版用什么 |
|---|---|---|---|---|
| 1 | 系统软件包（apt） | archive.ubuntu.com | 慢 | 清华 / 阿里云镜像 |
| 2 | Python 包（pip / uv） | pypi.org | 慢 | 清华镜像 |
| 3 | 前端包（npm / yarn） | registry.npmjs.org | 慢 | npmmirror |
| 4 | Node.js 二进制 | nodejs.org | 慢 | npmmirror 二进制源 |
| 5 | MariaDB 源 | deb.mariadb.org | 慢 | 清华镜像 |
| 6 | Python 3.14 运行时 | GitHub Releases | **经常不通** | 南京大学 github-release 镜像 |
| 7 | **frappe / erpnext 源码** | github.com | **经常不通** | **Gitee 镜像仓库** |

#### 除了这 7 个，还有一批"没有镜像可用"的

这些不是包源，是 GitHub 上的裸文件下载，**没有国内镜像，只能靠代理或改写**：

| 内容 | 出现在哪 | 影响 |
|---|---|---|
| frappe 钉死在 GitHub 的 3 个依赖 | `pyproject.toml` / `package.json` | **阻塞安装**（必须解决） |
| 预构建前端资源 | Pilot 下载加速用 | 失败自动回退本地编译，**不阻塞**，只是慢 |
| Pilot 自己的升级包 | Pilot 升级自己时 | 用源码方式安装即可绕过 |
| WAF 安全规则包 | 可选功能 | 不影响核心 |
| 应用市场列表 | 面板用 | 已改为 Gitee registry |
| 公网 IP 探测 | 配域名时用 | 已改为国内可达服务 |

#### 三个钉死 GitHub 的依赖（最硬的一块）

frappe v16 的依赖里，有 3 个直接指向 GitHub，**且国内没有现成镜像**：

| 依赖 | 问题 |
|---|---|
| `PyPika @ git+github.com/frappe/pypika@<SHA>` | Gitee 无对应镜像 |
| `gunicorn @ git+github.com/frappe/gunicorn@<SHA>` | Gitee 有上游镜像，但**不含 frappe fork 的那个 commit** |
| `air-datepicker: git+github.com/frappe/air-datepicker` | 同上 |

> ⚠️ **关键陷阱**：后两个是**钉死在具体 commit SHA 的 fork**。所以"把镜像地址换个域名"这种粗暴做法会失败——Gitee 的 `mirrors/*` 镜的是上游仓库，SHA 对不上，git 会直接报找不到对象。

**解决方案：三路线自动降级**

| 路线 | 做法 | 优劣 |
|---|---|---|
| **A** | Gitee 服务端「从 GitHub 导入仓库」 | ✅ 最精确，保留 fork 与 pinned SHA<br>✅ **是 Gitee 的服务器去 GitHub 拉代码，不需要你能访问 GitHub** |
| **B** | GitHub 加速代理 | ⚠️ 依赖第三方代理站，存活率不稳定 |
| **C** | 改写依赖为 PyPI / npm 官方版本 | ⚠️ 保底能装，但**丢掉 frappe 的 fork 补丁**，版本偏离官方 |

配置在 `config/mirrors.conf` 的 `GITEE_OWNER` / `GITHUB_PROXY_CANDIDATES` / `PATCH_*` 三处。

---

## 十五、待定问题（需要拍板）

| # | 问题 | 选项 |
|---|---|---|
| 1 | 目标操作系统 | 只支持 Ubuntu 24.04 / 还是加国产系统（麒麟、统信、openEuler）？ |
| 2 | 数据库归属 | 用 Pilot 自带的隔离实例（默认），还是接入机器上已有的 MariaDB？ |
| 3 | 证书方案 | 手动放云厂商证书（默认）/ 还是打通 Let's Encrypt（需要备案 + 80 端口）？ |
| 4 | 第三方代理 | 用公共加速站，还是自建缓存反代？ |
| 5 | 应用市场 | 继续用 Gitee 镜像版 / 还是支持自建应用市场？ |
| 6 | 离线安装包 | 现在做，还是后续再说？ |
| 7 | 维护人 | 谁负责定期同步官方更新（建议每月一次）？ |

---

## 十六、参考

- [frappe/pilot](https://github.com/frappe/pilot) — 官方仓库
- [frappe/bench](https://github.com/frappe/bench) — 上一代工具，README 指向 Pilot
- [frappe/frappe_docker](https://github.com/frappe/frappe_docker) — 官方 Docker 方案
- [Frappe 论坛](https://discuss.frappe.io/)

---

## 附：改完源码的三步走

```bash
# 1. 重新生成补丁（保证升级时能重放你的改动）
git diff upstream-base -- pilot/ admin/ ':(exclude)admin/frontend/in-app-embed/dev.sh' \
  > cn/patches/pilot-cn-mods.patch

# 2. 前端源码改过就重新编译（否则界面还是旧的）
cd admin/frontend/dashboard && npm install && npm run build && cd -

# 3. 部署到运行实例
sudo cn/deploy.sh --restart
```

**新改动应该放哪：**

| 改动性质 | 放哪 |
|---|---|
| 能写进配置文件的 | `config/mirrors.conf`（第 0 层，永不失效） |
| 必须改 Pilot 源码的 | 改完收进 `cn/patches/pilot-cn-mods.patch`（越少越好） |
| 属于我们自己的东西 | `cn/`（脚本、词表）和 `config/`（升级不会碰） |

---

## 附：本文档的定位

这份 README 同时是**使用手册**和**设计说明**。✅ 表示已实现，🔧 表示待实现。

**改动前请重点看**：

1. [第十四节](#十四设计说明)的**四条铁律** —— 这是底线，动了就要重来
2. 同节的**三层架构** —— 决定了改动应该放在哪一层
3. [第七节](#七我们在官方基础上改了什么)的**改动清单** —— 已经改过哪些文件
4. [第六节](#六改了代码之后怎么升级和部署) —— 升级和部署命令
