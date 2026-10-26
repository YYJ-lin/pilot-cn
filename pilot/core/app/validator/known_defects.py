"""上游已知缺陷的"就地隔离"。

背景
----
有些上游发布里会夹带**永远不被 import 的坏模块**：文件自己 import 同目录下
并不存在的模块，但全仓库没有任何地方引用它。它不影响 `pip install`、也不影响
运行时（没人 import），却会让本目录的 ImportCheck 判定"应用不可安装"，把整次
安装回滚掉。

pilot-cn 的处理方式：在校验之前把这几个已知缺陷文件重命名成
`<name>.py.disabled-upstream`。文件仍留在源码树里（可复查、可恢复），只是不再
参与扫描；`pilot update` 会用 `git reset --hard` 把它还原，于是下一轮校验时
这里会再隔离一次 —— 幂等。

只处理**明确登记过、且当前确实引用了缺失模块**的文件；上游一旦补齐，这里自动
不再介入。
"""

from __future__ import annotations

import ast
import typing
from dataclasses import dataclass

if typing.TYPE_CHECKING:
    from pathlib import Path

    from pilot.core.app import App

DISABLED_SUFFIX = ".disabled-upstream"


@dataclass(frozen=True)
class KnownDefect:
    """一条已知的上游缺陷。

    app:               应用名（bench.toml 里的 name）
    path:              缺陷文件相对应用根目录的路径
    missing_siblings:  该目录下应当存在、但某些发布里缺失的同级模块名
    reason:            给用户看的说明
    """

    app: str
    path: str
    missing_siblings: tuple[str, ...]
    reason: str


KNOWN_DEFECTS: tuple[KnownDefect, ...] = (
    KnownDefect(
        app="erpnext",
        path="erpnext/stock/doctype/stock_entry/services/material_transfer.py",
        missing_siblings=("manufacturing", "stock_entry_base"),
        reason=(
            "upstream 半截重构：该文件 import 同目录的 manufacturing / stock_entry_base，"
            "而这两个文件在 v16.50.0 ~ v16.52.x 与 version-16 分支顶端都不存在；"
            "该文件本身没有任何调用方（死代码）"
        ),
    ),
)


def _imported_siblings(source: str) -> set[str]:
    """文件里 `from .X import ...` / `from . import X` 引用的同级模块名。"""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return set()
    names: set[str] = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.ImportFrom) or node.level != 1:
            continue
        if node.module:
            names.add(node.module.split(".")[0])
        else:
            for alias in node.names:
                names.add(alias.name.split(".")[0])
    return names


def _missing(path: "Path", siblings: tuple[str, ...]) -> list[str]:
    """实际被引用、又确实不存在的同级模块。"""
    try:
        source = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    imported = _imported_siblings(source)
    return [s for s in siblings if s in imported and not (path.parent / f"{s}.py").exists()]


def quarantine_known_defects(app: "App") -> list[str]:
    """隔离命中的缺陷文件，返回给用户看的说明（空列表 = 什么都没做）。

    绝不抛异常：隔离失败只报告，交给后面的校验去处理，不能因为这道"补丁"
    本身让安装崩掉。
    """
    name = getattr(getattr(app, "config", None), "name", "") or ""
    if not name:
        return []

    messages: list[str] = []
    for defect in KNOWN_DEFECTS:
        if defect.app != name:
            continue
        target = app.path / defect.path
        if not target.is_file():
            continue  # 上游已经删掉这个文件了
        missing = _missing(target, defect.missing_siblings)
        if not missing:
            continue  # 同级模块齐了（上游补齐）→ 不动它
        disabled = target.with_name(target.name + DISABLED_SUFFIX)
        try:
            if disabled.exists():
                disabled.unlink()
            target.rename(disabled)
        except OSError as exc:
            messages.append(
                f"发现已知上游缺陷但无法隔离（{exc}）：{defect.path}\n"
                f"    说明：{defect.reason}"
            )
            continue
        messages.append(
            f"已隔离已知上游缺陷：{defect.path}\n"
            f"    原因：{defect.reason}\n"
            f"    处理：重命名为 {disabled.name}（不参与导入体检，运行时不受影响；"
            f"可用 git checkout 还原）"
        )
    return messages
