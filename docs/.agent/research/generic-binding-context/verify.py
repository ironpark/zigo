#!/usr/bin/env python3
"""Compile the isolated prototype and temporary rewrites; never modify examples."""
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def closing(text, start):
    end = {"(": ")", "{": "}", "[": "]"}[text[start]]
    i = start + 1
    while i < len(text):
        if text[i] == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif text.startswith("//", i):
            i = text.index("\n", i)
        elif text[i] in "({[":
            i = closing(text, i)
        elif text[i] == end:
            return i
        i += 1
    raise ValueError("Unbalanced example expression")


def rewrite(text):
    scopes = dict((m[2], m[1]) for m in re.finditer(
        r'const (\w+) = api.in\("([^"]+)"\);', text))
    original_scopes = dict(scopes)
    contexts = {}
    for match in reversed(list(re.finditer(r'api.handle\("([^"]+)",', text))):
        name = match[1]
        start = match.start()
        end = closing(text, text.index("(", start))
        while not text.startswith(".members(", end + 1):
            chain = re.match(r"\.\w+\(", text[end + 1:])
            if not chain:
                break
            end = closing(text, end + 1 + chain.end() - 1)
        if not text.startswith(".members(", end + 1):
            continue
        base = text[start:end + 1]
        local = scopes.setdefault(name, re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower() + "_context")
        contexts[name] = (local, base)
        text = text[:start] + local + ".define(" + text[end + 10:]
    added = []
    for name, (local, base) in contexts.items():
        declaration = f"const {local} = ctx.context({base});"
        if name in original_scopes:
            text = text.replace(f'const {local} = api.in("{name}");', declaration)
        else:
            added.append(declaration)
        text = text.replace(f'api.typeRef("{name}")', f"{local}.typeRef()")
        text = re.sub(rf"{local}\.define\({local}\.functions\((\w+)\)\)", rf"{local}.select(\1)", text)
    text = 'const ctx = @import("context");\n' + text
    if added:
        anchor = re.search(r"const api = .*?;", text).end()
        text = text[:anchor] + "\n" + "\n".join(added) + text[anchor:]
    return text, len(contexts)


def module_args(modules):
    args = []
    for name, path, deps in modules:
        for dep in deps:
            args += ["--dep", dep]
        args.append(f"-M{name}={path}")
    return args


def run(args, expected=None):
    result = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if expected is None:
        if result.returncode:
            raise RuntimeError(result.stdout)
        print(result.stdout, end="")
    elif result.returncode == 0 or expected not in result.stdout:
        raise RuntimeError(f"Expected failure containing {expected!r}:\n{result.stdout}")


def main():
    examples = [
        ("callback", "04-callback", "callback"),
        ("queue", "07-event-queue", "event_queue"),
        ("streams", "11-io-streams", "streams"),
        ("materialized", "12-materialized", "materialized"),
    ]
    with tempfile.TemporaryDirectory(prefix="zigo-generic-context-") as directory:
        tmp = Path(directory)
        modules = [
            ("root", HERE / "tests.zig", ["zigo", "context"] + [
                f"{side}_{key}" for key, _, _ in examples for side in ["before", "after"]]),
            ("zigo", ROOT / "src/root.zig", []),
            ("context", HERE / "context.zig", ["zigo"]),
            ("naming", ROOT / "src/gen/naming.zig", []),
            ("semantic", ROOT / "src/gen/ir/semantic.zig", ["naming"]),
            ("abi", ROOT / "src/gen/ir/abi.zig", ["semantic"]),
            ("diagnostic", ROOT / "src/gen/diagnostic.zig", []),
            ("plugin", ROOT / "src/plugin.zig", ["abi", "semantic", "diagnostic"]),
            ("zigo_satisfies", ROOT / "plugins/satisfies/src/plugin.zig", ["semantic", "diagnostic", "plugin"]),
        ]
        for key, folder, library in examples:
            path = ROOT / "examples" / folder / "src"
            before = subprocess.check_output(
                ["git", "show", "755501c0:" + str((path / "bindings.zig").relative_to(ROOT))],
                cwd=ROOT, text=True,
            )
            original = tmp / f"{key}_before.zig"
            original.write_text(before)
            after, count = rewrite(before)
            candidate = tmp / f"{key}.zig"
            candidate.write_text(after)
            run(["zig", "fmt", str(candidate)])
            print(f"{folder}: {count} contexts; source-name selections "
                  f"{len(re.findall('api.in|api.handle', before))} -> "
                  f"{len(re.findall('api.in|api.handle', after))}", flush=True)
            deps = ["zigo", library] + (["zigo_satisfies"] if key == "streams" else [])
            modules += [
                (library, path / "root.zig", []),
                (f"before_{key}", original, deps),
                (f"after_{key}", candidate, deps + ["context"]),
            ]
        run(["zig", "test", "-lc"] + module_args(modules))
        prefix = '''
const zigo = @import("zigo");
const ctx = @import("context");
const Lib = struct {
    pub const A = opaque { pub fn read(_: *@This()) void {} };
    pub const B = opaque {};
    pub const AliasA = A;
    pub const Callback = *const fn(usize) callconv(.c) void;
    pub fn rootFn() void {}
};
const api = zigo.scope(Lib);
'''
        cases = {
            "duplicate_alias": ('''const A = ctx.context(api.handle("A", .{}));
const Alias = ctx.context(api.handle("AliasA", .{}));
_ = zigo.define(.{ .root = Lib, .declarations = &.{ A.define(&.{}), Alias.define(&.{}) } });''', "zigo ambiguous registration of the same Zig type"),
            "function_context": ('_ = ctx.context(api.function("rootFn", .{}));', "research context requires a type entry"),
            "callback_context": ('_ = ctx.context(api.callback("Callback", .{}));', "research callback entries have no member context"),
            "missing_member": ('const A = ctx.context(api.handle("A", .{})); _ = A.function("missing", .{});', "zigo reference is not a public function"),
            "wrong_receiver": ('''const A = ctx.context(api.handle("A", .{}));
const B = ctx.context(api.handle("B", .{}));
_ = zigo.define(.{ .root = Lib, .declarations = &.{ A.define(&.{}), B.define(&.{A.function("read", .{})}) } });''', "zigo receiver differs from the enclosing member type"),
            "wrong_root": ('''const Other = struct { pub fn other() void {} };
const A = ctx.context(api.handle("A", .{}));
_ = zigo.define(.{ .root = Lib, .declarations = &.{ A.define(&.{zigo.scope(Other).function("other", .{})}) } });''', "zigo reference belongs to a different root"),
            "context_as_entry": ('''const A = ctx.context(api.handle("A", .{}));
_ = zigo.define(.{ .root = Lib, .declarations = &.{A} });''', "expected type"),
        }
        for name, (body, expected) in cases.items():
            source = tmp / f"{name}.zig"
            source.write_text(prefix + "\ncomptime {\n" + body + "\n}\n")
            run(["zig", "build-obj", "-fno-emit-bin"] + module_args([
                ("root", source, ["zigo", "context"]),
                ("zigo", ROOT / "src/root.zig", []),
                ("context", HERE / "context.zig", ["zigo"]),
            ]), expected)
            print(f"rejects {name}: PASS", flush=True)


if __name__ == "__main__":
    main()
