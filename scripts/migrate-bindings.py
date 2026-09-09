#!/usr/bin/env python3
"""Rewrites zigo binding declarations from the 0.14 anonymous-literal grammar
to the 0.15 typed schema.

Historical intermediate migration only. For the current declaration-tree API,
continue with docs/authoring/README.md.

Usage: scripts/migrate-bindings.py <file.zig>...

Every `.{ ... }` literal that carries a `.root` key is treated as a binding
declaration and rewritten in place:

- `.types` entries: `.repr = .X` becomes the `Type` union variant
  (`.@"opaque"` -> `.handle`), `.field_meta` becomes `.fields`,
  `.omit_variants` -> `.omit`, callback `.param_semantics` -> `.params`,
  callback `.semantic` -> `.returns.semantic`.
- `.functions` entries: `.params` + `.param_meta` merge into one `Param`
  list; `.semantic`/`.returns`/`.release`/`.go` fold into `.returns`;
  `.receiver`/`.constructs`/`.destroys` names become the registered type
  value; `.written = .@"return"` -> `.result`; `.userdata = "x"` ->
  `.{ .param = "x" }`.
- Receiver groups move out of `.functions` into `.methods`.
- Tuples that are now slices gain `&`; `.io`/`.allocator` path strings
  become `.{ .path = ... }`.

Run `zig fmt` on the result. The rewrite is syntactic: a name it cannot map
to a registered type is left as a string for the compiler to flag.
"""
import re
import sys

# --- a tiny parser for Zig anonymous literals ---------------------------------


class Node:
    pass


class Obj(Node):
    def __init__(self, fields, multiline):
        self.fields = fields  # list of Field
        self.multiline = multiline


class Field:
    def __init__(self, key, value, comments):
        self.key = key  # str or None (positional)
        self.value = value  # Node
        self.comments = comments  # list of comment lines preceding the field


class Str(Node):
    def __init__(self, text):
        self.text = text  # including quotes


class Expr(Node):
    def __init__(self, text):
        self.text = text


class Parser:
    def __init__(self, src, pos):
        self.s = src
        self.i = pos

    def peek(self):
        return self.s[self.i] if self.i < len(self.s) else ""

    def skip_ws(self):
        comments = []
        while self.i < len(self.s):
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif self.s.startswith("//", self.i):
                end = self.s.find("\n", self.i)
                if end < 0:
                    end = len(self.s)
                comments.append(self.s[self.i:end].strip())
                self.i = end
            else:
                break
        return comments

    def parse_obj(self):
        assert self.s.startswith(".{", self.i), self.s[self.i:self.i + 30]
        start = self.i
        self.i += 2
        fields = []
        while True:
            comments = self.skip_ws()
            if self.peek() == "}":
                self.i += 1
                break
            key = None
            m = re.match(r"\.(@\"[^\"]+\"|[A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)", self.s[self.i:])
            if m and not self.s.startswith(".{", self.i):
                key = m.group(1)
                self.i += m.end()
                self.skip_ws()
            value = self.parse_value()
            fields.append(Field(key, value, comments))
            self.skip_ws()
            if self.peek() == ",":
                self.i += 1
        multiline = "\n" in self.s[start:self.i]
        return Obj(fields, multiline)

    def parse_value(self):
        if self.s.startswith(".{", self.i):
            return self.parse_obj()
        if self.peek() == '"':
            j = self.i + 1
            while self.s[j] != '"':
                if self.s[j] == "\\":
                    j += 1
                j += 1
            text = self.s[self.i:j + 1]
            self.i = j + 1
            return Str(text)
        if self.s.startswith("&.{", self.i):
            self.i += 1
            obj = self.parse_obj()
            return Expr("&" + emit(obj, 0))
        # bare expression up to a top-level ',' or '}'
        depth = 0
        j = self.i
        while j < len(self.s):
            c = self.s[j]
            if c in "([{":
                depth += 1
            elif c in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif c == "," and depth == 0:
                break
            elif c == '"':
                j += 1
                while self.s[j] != '"':
                    if self.s[j] == "\\":
                        j += 1
                    j += 1
            j += 1
        text = self.s[self.i:j].strip()
        self.i = j
        return Expr(text)


def emit(node, indent):
    pad = "    " * indent
    if isinstance(node, Str) or isinstance(node, Expr):
        return node.text
    if not node.fields:
        return ".{}"
    parts = []
    for f in node.fields:
        head = f".{f.key} = " if f.key else ""
        parts.append((f.comments, head + emit(f.value, indent + 1)))
    if node.multiline or any(c for c, _ in parts):
        out = ".{\n"
        for comments, text in parts:
            for c in comments:
                out += pad + "    " + c + "\n"
            out += pad + "    " + text + ",\n"
        return out + pad + "}"
    return ".{ " + ", ".join(t for _, t in parts) + " }"


# --- transformation -----------------------------------------------------------


def get(obj, key):
    for f in obj.fields:
        if f.key == key:
            return f
    return None


def drop(obj, key):
    obj.fields = [f for f in obj.fields if f.key != key]


def slice_of(value):
    """`.{ a, b }` -> `&.{ a, b }`; strings stay."""
    if isinstance(value, Obj):
        return Expr("&" + emit(value, 0))
    if isinstance(value, Str):
        return Expr("&.{" + value.text + "}")
    return value


def short_name(type_expr):
    return type_expr.rsplit(".", 1)[-1]


def transform_type_entry(entry):
    repr_field = get(entry, "repr")
    if repr_field is None:
        return entry
    repr_name = repr_field.value.text.lstrip(".")
    variant = {'@"opaque"': "handle"}.get(repr_name, repr_name)
    drop(entry, "repr")
    fields_field = get(entry, "fields")
    if fields_field:
        fields_field.value = slice_of(fields_field.value)
    meta = get(entry, "field_meta")
    if meta:
        items = []
        for f in meta.value.fields:
            hint = get(f.value, "semantic").value.text
            items.append(f'.{{ .name = "{f.key}", .semantic = {hint} }}')
        drop(entry, "field_meta")
        entry.fields.append(Field("fields", Expr("&.{ " + ", ".join(items) + " }"), []))
    omit = get(entry, "omit_variants")
    if omit:
        omit.key = "omit"
        omit.value = slice_of(omit.value)
    covers = get(entry, "covers")
    if covers:
        covers.value = slice_of(covers.value)
    if variant == "callback":
        hints = get(entry, "param_semantics")
        if hints:
            items = [f".{{ .semantic = {f.value.text} }}" for f in hints.value.fields]
            drop(entry, "param_semantics")
            entry.fields.append(Field("params", Expr("&.{ " + ", ".join(items) + " }"), []))
        sem = get(entry, "semantic")
        if sem:
            drop(entry, "semantic")
            entry.fields.append(Field("returns", Expr(f".{{ .semantic = {sem.value.text} }}"), []))
    payload = Obj(entry.fields, entry.multiline)
    return Obj([Field(variant, payload, [])], entry.multiline)


def registered_types(decl):
    """Go name -> Zig type expression, after type entries were transformed."""
    names = {}
    types = get(decl, "types")
    if not types or not isinstance(types.value, Obj):
        return names
    for f in types.value.fields:
        if not isinstance(f.value, Obj) or not f.value.fields:
            continue
        payload = f.value.fields[0].value
        if not isinstance(payload, Obj):
            continue
        t = get(payload, "type")
        if not t:
            continue
        n = get(payload, "name")
        name = n.value.text.strip('"') if n and isinstance(n.value, Str) else short_name(t.value.text)
        names[name] = t.value.text
    return names


def transform_param_meta_value(meta):
    """One `.param_meta.<name> = .{...}` payload into Param fields."""
    out = []
    for f in meta.fields:
        v = f.value
        if f.key == "written" and isinstance(v, Expr) and v.text == '.@"return"':
            v = Expr(".result")
        elif f.key == "flatten":
            v = slice_of(v)
        elif f.key == "userdata" and isinstance(v, Str):
            v = Expr(f".{{ .param = {v.text} }}")
        out.append(Field(f.key, v, f.comments))
    return out


def transform_function_entry(entry, names):
    params = get(entry, "params")
    meta = get(entry, "param_meta")
    if params or meta:
        by_name = {}
        if meta:
            for f in meta.value.fields:
                by_name[f.key] = transform_param_meta_value(f.value)
        items = []
        if params and isinstance(params.value, Obj):
            for f in params.value.fields:
                name = f.value.text.strip('"')
                fields = [Field("name", f.value, [])] + by_name.pop(name, [])
                items.append(Field(None, Obj(fields, False), []))
        for name, fields in by_name.items():
            # An orphaned key (no `.params`): keep it positional-less so the
            # compiler's count check reports it.
            items.append(Field(None, Obj([Field("name", Str(f'"{name}"'), [])] + fields, False), []))
        drop(entry, "param_meta")
        if items:
            if params:
                params.value = Expr("&" + emit(Obj(items, False), 0))
            else:
                entry.fields.append(Field("params", Expr("&" + emit(Obj(items, False), 0)), []))
        elif params:
            drop(entry, "params")
    returns = []
    for key, target in (("returns", "ownership"), ("semantic", "semantic"), ("release", "release"), ("go", "go")):
        f = get(entry, key)
        if f:
            returns.append(Field(target, f.value, []))
            drop(entry, key)
    if returns:
        entry.fields.append(Field("returns", Obj(returns, False), []))
    covers = get(entry, "covers")
    if covers:
        covers.value = slice_of(covers.value)
    for key in ("receiver", "constructs", "destroys"):
        f = get(entry, key)
        if f and isinstance(f.value, Str):
            name = f.value.text.strip('"')
            if name in names:
                f.value = Expr(names[name])
    return entry


def transform_declaration(decl):
    types = get(decl, "types")
    if types and isinstance(types.value, Obj):
        types.value.fields = [Field(None, transform_type_entry(f.value), f.comments) if isinstance(f.value, Obj) else f for f in types.value.fields]
        types.value = Expr("&" + emit(types.value, 0)) if not types.value.multiline else types.value
        if isinstance(types.value, Obj):
            types.value = Expr("&" + emit(types.value, 1))
    names = registered_types_from_expr(decl)
    functions = get(decl, "functions")
    methods = []
    if functions and isinstance(functions.value, Obj):
        kept = []
        for f in functions.value.fields:
            v = f.value
            if isinstance(v, Obj) and get(v, "functions") is not None:
                group = v
                recv = get(group, "receiver")
                if recv and isinstance(recv.value, Str):
                    name = recv.value.text.strip('"')
                    if name in names:
                        recv.value = Expr(names[name])
                nested = get(group, "functions")
                new_nested = []
                for g in nested.value.fields:
                    gv = g.value
                    if isinstance(gv, Str):
                        gv = Obj([Field("path", gv, [])], False)
                    new_nested.append(Field(None, transform_function_entry(gv, names), g.comments))
                nested.value = Expr("&" + emit(Obj(new_nested, nested.value.multiline), 2))
                methods.append(Field(None, group, f.comments))
            elif isinstance(v, Obj):
                kept.append(Field(None, transform_function_entry(v, names), f.comments))
            elif isinstance(v, Str):
                kept.append(Field(None, Obj([Field("path", v, [])], False), f.comments))
            else:
                kept.append(f)
        if kept:
            functions.value = Expr("&" + emit(Obj(kept, functions.value.multiline), 1))
        else:
            drop(decl, "functions")
    if methods:
        decl.fields.append(Field("methods", Expr("&" + emit(Obj(methods, True), 1)), []))
    for key in ("exclude",):
        f = get(decl, key)
        if f:
            f.value = slice_of(f.value)
    for key in ("io", "allocator"):
        f = get(decl, key)
        if f and isinstance(f.value, Str):
            f.value = Expr(f".{{ .path = {f.value.text} }}")
    for key in ("packages", "interfaces"):
        f = get(decl, key)
        if f and isinstance(f.value, Obj):
            for entry in f.value.fields:
                if isinstance(entry.value, Obj):
                    for sub in entry.value.fields:
                        if sub.key in ("types", "functions", "namespaces", "methods"):
                            sub.value = slice_of(sub.value)
            f.value = Expr("&" + emit(f.value, 1))
    return decl


def registered_types_from_expr(decl):
    """`types` may already be an Expr (`&.{...}`); re-parse it for names."""
    types = get(decl, "types")
    if not types:
        return {}
    text = types.value.text if isinstance(types.value, Expr) else emit(types.value, 0)
    if text.startswith("&"):
        text = text[1:]
    if not text.startswith(".{"):
        return {}
    obj = Parser(text, 0).parse_obj()
    fake = Obj([Field("types", obj, [])], False)
    return registered_types(fake)


def find_declarations(src):
    """Spans of every `.{ ... }` literal that carries a top-level `.root`."""
    spans = []
    for m in re.finditer(r"\.root\s*=", src):
        # walk back to the enclosing `.{`
        depth = 0
        i = m.start() - 1
        while i >= 0:
            c = src[i]
            if c == "}":
                depth += 1
            elif c == "{":
                if depth == 0:
                    break
                depth -= 1
            i -= 1
        if i <= 0 or src[i - 1] != ".":
            continue
        start = i - 1
        p = Parser(src, start)
        try:
            p.parse_obj()
        except Exception as error:  # noqa: BLE001
            print(f"skip literal at {start}: {error}", file=sys.stderr)
            continue
        spans.append((start, p.i))
    # nested declarations never occur; drop overlaps defensively
    spans.sort()
    result = []
    for span in spans:
        if result and span[0] < result[-1][1]:
            continue
        result.append(span)
    return result


def migrate(src):
    out = []
    last = 0
    for start, end in find_declarations(src):
        decl = Parser(src, start).parse_obj()
        transform_declaration(decl)
        before = src[last:start]
        # A declaration held in a `const` needs the type spelled out, or the
        # literal stays an anonymous struct that does not coerce later.
        before = re.sub(r"(const\s+[A-Za-z_][A-Za-z0-9_]*)\s*=\s*$", r"\1: zigo.Binding = ", before)
        out.append(before)
        out.append(emit(decl, indent_of(src, start)))
        last = end
    out.append(src[last:])
    return "".join(out)


def indent_of(src, pos):
    line_start = src.rfind("\n", 0, pos) + 1
    return (pos - line_start) // 4


# --- markdown fragments -------------------------------------------------------


def migrate_fragment(block):
    """A doc snippet is usually a few top-level keys (`.types = .{...},`) or a
    single entry. Wrap it as a declaration, transform, and unwrap."""
    text = block.strip()
    if not text.startswith("."):
        return block
    try:
        decl = Parser(".{" + text + "}", 0).parse_obj()
    except Exception:  # noqa: BLE001
        return block
    if get(decl, "root") is None and not any(get(decl, k) for k in ("types", "functions", "exclude", "packages", "interfaces")):
        # Bare entries, one per positional field: decide each by its keys.
        changed = False
        for f in decl.fields:
            if f.key is not None or not isinstance(f.value, Obj):
                continue
            if get(f.value, "repr"):
                f.value = transform_type_entry(f.value)
                changed = True
            elif get(f.value, "path") or get(f.value, "functions"):
                f.value = transform_function_entry(f.value, {})
                changed = True
        if not changed:
            return block
    else:
        transform_declaration(decl)
    inner = emit(Obj(decl.fields, True), 0)
    lines = inner.split("\n")[1:-1]
    return reindent("\n".join(lines))


def reindent(text):
    """Nested slices are emitted without knowing their depth; rebuild the
    indentation from brace depth, which is all a literal-only snippet has."""
    out = []
    depth = 0
    for raw in text.split("\n"):
        line = raw.strip()
        if not line:
            out.append("")
            continue
        closing = len(line) - len(line.lstrip("}"))
        depth -= closing
        out.append("    " * max(depth, 0) + line)
        depth += line.count("{") - line.count("}") + closing
    return "\n".join(out)


def migrate_markdown(src):
    out = []
    pos = 0
    for m in re.finditer(r"```zig\n(.*?)```", src, re.S):
        out.append(src[pos:m.start(1)])
        block = m.group(1)
        if ".root =" in block or "zigo.define" in block:
            out.append(migrate(block))
        else:
            out.append(migrate_fragment(block).rstrip("\n") + "\n")
        pos = m.end(1)
    out.append(src[pos:])
    return "".join(out)


if __name__ == "__main__":
    for path in sys.argv[1:]:
        if path.endswith(".md"):
            text = open(path).read()
            result = migrate_markdown(text)
            with open(path, "w") as out:
                out.write(result)
            print(f"migrated {path}")
            continue
        text = open(path).read()
        result = migrate(text)
        with open(path, "w") as out:
            out.write(result)
        print(f"migrated {path}")
