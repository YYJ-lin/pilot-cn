# pilot-cn 源码改动补丁

## 这是什么

`pilot-cn-mods.patch` 记录了 **pilot-cn 对上游 Pilot 源码的全部改动**，用于"上游升级后自动重放"。

- **基线**：上游 `v0.0.64-pre-alpha`（pilot-cn 的初始提交就是它的 pristine 副本）
- **覆盖**：`pilot/` 与 `admin/` 下的 30 个文件
- **不包含**：我们自己的层（`cn/`、`config/`、`install-cn.sh`）——上游没有这些文件，永远不会被升级覆盖

## 补丁内容

| 文件 | 改动 |
|---|---|
| `pilot/integrations/git/github.py` | git 命令替代 GitHub API（列分支含 tag、默认分支、has_branch、读文件走 git 克隆）+ `GiteeProvider` |
| `pilot/integrations/git/local.py` | 新增 `LocalProvider`（本地目录作为应用源） |
| `pilot/integrations/git/__init__.py` | 注册 Gitee / Local provider，新增 `repo_full_name` |
| `pilot/core/app/__init__.py` | 已安装应用切换到不同 tag/branch（`_switch_to_commit`） |
| `pilot/core/app/repository.py` | `switch_branch` 支持 tag |
| `pilot/internal/git.py` | 新增 `remote_ref_sha`（分支或 tag 的 SHA）；`remote_url` 改读 `.git/config` 原始值，避免 insteadOf 展开后的代理地址被写进 bench.toml |
| `pilot/core/registry_cache.py` | 市场 registry 指向 Gitee（`PILOT_MARKETPLACE_URL` 可覆盖） |
| `admin/backend/middleware.py` | 面板 cookie `sid` → `pilot_sid`（避免与 Frappe 冲突） |
| `admin/backend/api/v1/auth.py` | 同上（登出删除对应 cookie） |
| `admin/backend/api/v1/git.py` | Gitee / 本地路径支持 |
| `pilot/integrations/git/refs.py` | 新增：`git ls-remote --heads --tags` 列分支和 tag（向导的分支/版本列表，带缓存与降级） |
| `pilot/config/bench.py` | `framework_app` 按 `name = "frappe"` 取，不看列表顺序；`app_repo/app_branch` 写回同一条 |
| `admin/backend/api/v1/setup/config.py` | 向导预填直接读 bench.toml 里 frappe 的 `[[apps]]` 条目（半残配置也能预填） |
| `admin/backend/api/v1/setup/__init__.py` | `/setup/framework-branches` 返回远端 heads + tags，失败退回内置列表 |
| `admin/backend/api/v1/core.py` | bench 已初始化时清理失败向导残留的 `.wizard-active` |
| `admin/backend/api/v1/sites/core.py` | 面板站点地址 / 一键登录用「访问面板的地址」（单站点固定时） |
| `pilot/core/bench/config_files.py` | 单站点自动写 `default_site`（≈ `bench use`），多站点自动去掉 |
| `pilot/core/bench/runtime.py` | Python 依赖统一走 `install_app`；重建资产后重启 web |
| `pilot/core/site/login.py`、`pilot/core/site/__init__.py` | 站点 URL / 登录链接支持 `dev_host`，单站点时用面板地址 |
| `pilot/tasks/new_site.py` | 建站后同步 `default_site` 并重启 web，站点立刻可访问 |
| `pilot/managers/environment.py` | 应用 `dev` extra 解析失败时降级为不带 extra 安装（frappe 的 pypika 冲突） |
| `pilot/core/bench/update.py` | 市场应用更新时校验失败只告警不中断（与安装时的"信任 registry 钉住版本"保持一致） |
| `pilot/core/app/validator/known_defects.py` | **新增**：校验前隔离已知上游缺陷文件（`material_transfer.py` 那类「引用了不存在同级模块的死代码」），安装/升级/切分支三条路径都覆盖 |
| `pilot/core/app/validator/validator.py` | 校验前调用上面的隔离步骤 |

## 怎么用

```bash
cn/upgrade.sh --list                # 看可选的上游版本
cn/upgrade.sh v0.0.66-pre-alpha     # 升级到该上游版本，并自动重放本补丁
git diff --stat                     # 检查
git add -A && git commit -m 'chore: upgrade vendored pilot to v0.0.66-pre-alpha'
```

升级原理：

```
上游新版本 ──checkout──▶ pilot/ admin/ 被替换成上游内容
                             │
                             ▼
             git apply --3way ◀── cn/patches/pilot-cn-mods.patch
                             │
                             ▼
             结果 = 上游新版 + pilot-cn 全部改动
```

`--3way` 以「上游 v0.0.64（基线）/ 我们的版本 / 上游新版」做三路合并，能自动吸收
上下文漂移；真冲突时会列出文件，停下来等你手工处理（脚本退出码 2）。

## 又改了源码之后：重新生成补丁

```bash
git diff upstream-base..HEAD -- pilot/ admin/ ':(exclude)admin/frontend/in-app-embed/dev.sh' \
  > cn/patches/pilot-cn-mods.patch
```

> `upstream-base` 是指向"上游 v0.0.64"的本地 tag，`cn/upgrade.sh` 首次运行时会自动补上
> `upstream` remote；如果本机没有这个 tag，先跑一次 `cn/upgrade.sh --list`。
