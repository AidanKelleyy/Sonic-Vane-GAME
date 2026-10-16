#!/usr/bin/env python3
"""Validate bootstrap script dependencies and synchronize platform export selections."""

import argparse
import ast
import hashlib
import json
from pathlib import Path
import posixpath
import re
import sys

MANIFEST = "res://LS5Framework/Resources/Diagnostics/PlayerStartupDependencies.json"
PLATFORMS = {"Windows Desktop", "Linux", "macOS"}
PLAYER_DIR = "LS5Framework/Scripts/Player"
VALIDATOR = "res://LS5Framework/Scripts/Managers/PlayerScriptValidation.gd"
VERIFY = "res://LS5Framework/Scripts/Managers/VerifyPlayerStartup.gd"
TOKEN = re.compile(r"#[^\n]*|\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|[A-Za-z_]\w*|[()]")


def tokens(source):
    result = []
    for match in TOKEN.finditer(source):
        value = match.group()
        if value.startswith("#"):
            continue
        if value.startswith(("\"", "'")):
            try:
                result.append(("string", ast.literal_eval(value)))
            except (ValueError, SyntaxError):
                result.append(("string", ""))
        else:
            result.append(("code", value))
    return result


def read_presets(text):
    result = []
    for match in re.finditer(r"\[preset\.(\d+)\]\n(.*?)(?=\n\[|\Z)", text, re.S):
        body = match.group(2)
        values = dict(re.findall(r"^(name|export_filter|export_files|include_filter|exclude_filter)=(.*)$", body, re.M))
        if "name" not in values:
            continue
        result.append({"id": match.group(1), "name": ast.literal_eval(values["name"]),
                       "filter": ast.literal_eval(values.get("export_filter", '\"resources\"')),
                       "files": [v for k, v in tokens(values.get("export_files", "")) if k == "string"],
                       "includes": ast.literal_eval(values.get("include_filter", '\"\"')).split(","),
                       "excludes": ast.literal_eval(values.get("exclude_filter", '\"\"')).split(",")})
    return result


def discover(root, presets):
    sources = {}
    classes = {}
    script_uids = {}
    for directory in ["LS5Framework", "addons"]:
        for path in sorted((root / directory).rglob("*.gd")):
            relative = "res://" + path.relative_to(root).as_posix()
            source = path.read_text(encoding="utf-8-sig")
            sources[relative] = tokens(source)
            uid_file = Path(str(path) + ".uid")
            if uid_file.is_file():
                script_uids[uid_file.read_text(encoding="utf-8-sig").strip()] = relative
            code = TOKEN.sub(lambda match: re.sub(r"[^\n]", " ", match.group()) if match.group().startswith(("#", "\"", "'")) else match.group(), source)
            for name in re.findall(r"^\s*class_name\s+([A-Za-z_]\w*)", code, re.M):
                if name in classes and classes[name] != relative:
                    raise ValueError(f"Duplicate script class {name}: {classes[name]} and {relative}")
                classes[name] = relative
    players = sorted("res://" + p.relative_to(root).as_posix() for p in (root / PLAYER_DIR).glob("*.gd"))
    roots = set(players + [VALIDATOR, VERIFY])
    for preset in presets:
        if preset["name"] in PLATFORMS:
            roots.update(p for p in preset["files"] + preset["includes"] if p.endswith(".gd"))
    project = root / "project.godot"
    if project.is_file():
        section = re.search(r"\[autoload\]\n(.*?)(?=\n\[|\Z)", project.read_text(encoding="utf-8-sig"), re.S)
        if section:
            for _, reference in re.findall(r'^([^=]+)="([^"\n]+)"', section.group(1), re.M):
                target = reference.removeprefix("*")
                if target.startswith("uid://"):
                    if target not in script_uids:
                        raise ValueError("Unresolved autoload script UID: " + target)
                    target = script_uids[target]
                if target.endswith(".gd"):
                    roots.add(target)
    entries = {}
    queue = [(p, "Bootstrap script", "Root") for p in sorted(roots)]
    while queue:
        path, owner, kind = queue.pop()
        if path in entries:
            reference = {"path": owner, "kind": kind}
            if reference not in entries[path]["owners"]:
                entries[path]["owners"].append(reference)
            continue
        local = root / path.removeprefix("res://")
        if not local.is_file():
            raise ValueError(f"Missing startup dependency: {path} referenced by {owner} ({kind})")
        entry = {"path": path, "owners": [{"path": owner, "kind": kind}]}
        entries[path] = entry
        if path.endswith(".gd"):
            entry["source_sha256"] = hashlib.sha256(local.read_text(encoding="utf-8-sig").encode("utf-8")).hexdigest()
            stream = sources[path]
            for index, (token_kind, value) in enumerate(stream):
                if token_kind == "code" and value in classes:
                    queue.append((classes[value], path, "Script class"))
                target = None
                if (token_kind == "code" and value == "preload" and index + 2 < len(stream)
                        and stream[index + 1] == ("code", "(") and stream[index + 2][0] == "string"):
                    target = stream[index + 2][1]
                elif token_kind == "code" and value == "extends" and index + 1 < len(stream) and stream[index + 1][0] == "string":
                    target = stream[index + 1][1]
                if target is not None:
                    if target.startswith("uid://"):
                        if target not in script_uids:
                            raise ValueError(f"Unresolved startup UID {target} referenced by {path}; use an explicit resource path")
                        target = script_uids[target]
                    elif not target.startswith("res://"):
                        target = "res://" + posixpath.normpath(posixpath.join(posixpath.dirname(path[6:]), target))
                    queue.append((target, path, "Inheritance" if value == "extends" else "Preload"))
        elif local.suffix in {".tscn", ".tres", ".gdshader", ".gdshaderinc"}:
            source = local.read_text(encoding="utf-8-sig")
            for target in re.findall(r'\[ext_resource[^\n]*?path="([^"\n]+)"', source):
                queue.append((target, path, "Resource"))
            for target in re.findall(r'^\s*#include\s+"([^"\n]+)"', source, re.M):
                target = target if target.startswith("res://") else "res://" + (Path(path[6:]).parent / target).as_posix()
                queue.append((target, path, "Shader include"))
    for entry in entries.values():
        root_reference = {"path": "Bootstrap script", "kind": "Root"}
        if entry["path"].endswith(".gd") and root_reference not in entry["owners"]:
            entry["owners"].append(root_reference)
        entry["owners"].sort(key=lambda value: (value["path"], value["kind"]))
    return {"version": 1, "player_scripts": players, "required_resources": [entries[p] for p in sorted(entries)]}


def validate(root, cfg_path, fix=False):
    text = cfg_path.read_text(encoding="utf-8-sig")
    presets = read_presets(text)
    found = {p["name"] for p in presets} & PLATFORMS
    if found != PLATFORMS:
        raise ValueError("Missing platform presets: " + ", ".join(sorted(PLATFORMS - found)))
    manifest = discover(root, presets)
    required = [entry["path"] for entry in manifest["required_resources"]] + [MANIFEST]
    failures = []
    total_added = 0
    import fnmatch
    for preset in presets:
        if preset["name"] not in PLATFORMS:
            continue
        if preset["filter"] != "resources":
            raise ValueError(f"Unsupported bootstrap filter for {preset['name']}: {preset['filter']}")
        for path in required:
            if any(pattern and (fnmatch.fnmatchcase(path, pattern) or fnmatch.fnmatchcase(path[6:], pattern)) for pattern in preset["excludes"]):
                failures.append(f"{preset['name']} excludes startup dependency {path}")
        absent = [path for path in required if path not in preset["files"]]
        if fix:
            block_pattern = r"(\[preset\." + preset["id"] + r"\]\n)(.*?)(?=\n\[|\Z)"
            match = re.search(block_pattern, text, re.S)
            block = match.group(2)
            values = preset["files"] + absent
            block = re.sub(r"^export_files=.*$", lambda _: "export_files=PackedStringArray(" + ", ".join(json.dumps(p, ensure_ascii=False) for p in values) + ")", block, flags=re.M)
            includes = [p for p in preset["includes"] if p]
            if MANIFEST not in includes:
                includes.append(MANIFEST)
            block = re.sub(r"^include_filter=.*$", lambda _: "include_filter=" + json.dumps(",".join(includes)), block, flags=re.M)
            text = text[:match.start(2)] + block + text[match.end(2):]
            total_added += len(absent)
        else:
            failures.extend(f"{preset['name']} missing startup dependency {path}" for path in absent)
            if MANIFEST not in preset["includes"]:
                failures.append(f"{preset['name']} must include the raw startup manifest")
    manifest_path = root / MANIFEST[6:]
    encoded = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    if fix and not failures:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        if not manifest_path.exists() or manifest_path.read_text(encoding="utf-8") != encoded:
            manifest_path.write_text(encoded, encoding="utf-8")
        if cfg_path.read_text(encoding="utf-8-sig") != text:
            cfg_path.write_text(text, encoding="utf-8")
    elif not manifest_path.is_file() or manifest_path.read_text(encoding="utf-8") != encoded:
        failures.append("Startup dependency manifest is stale; run validate_startup_dependencies.py --fix")
    if failures:
        raise ValueError("\n".join(failures))
    return len(manifest["player_scripts"]), len(required), total_added


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--presets-cfg", type=Path, default=Path("export_presets.cfg"))
    parser.add_argument("--fix", action="store_true", help="Synchronize base presets and regenerate the manifest")
    args = parser.parse_args()
    root = args.root.resolve()
    cfg = args.presets_cfg if args.presets_cfg.is_absolute() else root / args.presets_cfg
    try:
        scripts, resources, additions = validate(root, cfg, args.fix)
    except (ValueError, OSError, KeyError) as error:
        print("Startup dependency validation failed:\n" + str(error), file=sys.stderr)
        return 1
    print(f"Startup dependencies: {scripts} player scripts, {resources} required resources, {additions} preset additions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
