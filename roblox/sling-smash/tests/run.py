"""Runs the Sling Smash logic tests with the standalone `luau` CLI.

The modules use Roblox-style `require(script.Parent.X)`, so this script
bundles them, the datatype mocks in mocks.luau and spec.luau into one chunk.

Usage:  python3 tests/run.py [path/to/luau]
        (defaults to $LUAU, then `luau` on PATH)
"""

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "src"
# (folder, module) pairs; server modules here must not touch Roblox services.
MODULES = [
    ("shared", "Config"),
    ("shared", "CourseLayout"),
    ("shared", "Physics"),
    ("shared", "RunSim"),
    ("shared", "Format"),
    ("shared", "Index"),
    ("shared", "Daily"),
    ("server", "Codes"),
]


def bundle() -> str:
    parts = [(HERE / "mocks.luau").read_text(encoding="utf-8")]
    parts.append("local __modules, __loaded = {}, {}")
    parts.append(
        "local function __require(name)\n"
        "\tif __loaded[name] == nil then __loaded[name] = __modules[name]() end\n"
        "\treturn __loaded[name]\n"
        "end"
    )
    for folder, name in MODULES:
        source = (SRC / folder / f"{name}.luau").read_text(encoding="utf-8")
        for _, dep in MODULES:
            source = source.replace(f"require(script.Parent.{dep})", f"__require('{dep}')")
        parts.append(f"__modules['{name}'] = function()\n{source}\nend")
    parts.append("\n".join(f"local {name} = __require('{name}')" for _, name in MODULES))
    parts.append((HERE / "spec.luau").read_text(encoding="utf-8"))
    return "\n".join(parts)


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("LUAU") or shutil.which("luau")
    if not luau:
        print("Couldn't find the luau CLI. Pass its path or set $LUAU.", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory() as tmp:
        bundled = pathlib.Path(tmp) / "bundled.luau"
        bundled.write_text(bundle(), encoding="utf-8")
        result = subprocess.run([luau, str(bundled)], capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode != 0 or "ALL CHECKS PASSED" not in result.stdout:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
