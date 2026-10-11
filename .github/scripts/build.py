#!/usr/bin/env python3
"""
Sonic VANE - Godot Multi-Platform & Content Pack Export Script
Handles exporting executable targets and all modular PCK packs defined
in export_presets.cfg (preset 3 onwards), structuring the Data/ directory
for Windows, Linux, and macOS standalone releases.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import zipfile


def parse_export_presets(cfg_path):
    """
    Parses export_presets.cfg line-by-line to extract preset metadata.
    Avoids INI parser failures caused by multi-line script options.
    """
    presets = []
    current_preset = None

    if not os.path.exists(cfg_path):
        raise FileNotFoundError(f"Export presets file not found: {cfg_path}")

    with open(cfg_path, "r", encoding="utf-8") as f:
        for line in f:
            line_s = line.strip()
            # Match preset section header e.g. [preset.0]
            m_sec = re.match(r"^\[preset\.(\d+)\]$", line_s)
            if m_sec:
                current_preset = {
                    "id": int(m_sec.group(1)),
                    "name": "",
                    "platform": "",
                    "export_path": "",
                }
                presets.append(current_preset)
                continue

            # Any sub-section (like [preset.0.options]) ends current preset definition
            if current_preset and line_s.startswith("[preset."):
                current_preset = None
                continue

            if current_preset:
                m_name = re.match(r'^name="([^"]+)"', line_s)
                if m_name:
                    current_preset["name"] = m_name.group(1)
                m_plat = re.match(r'^platform="([^"]+)"', line_s)
                if m_plat:
                    current_preset["platform"] = m_plat.group(1)
                m_path = re.match(r'^export_path="([^"]+)"', line_s)
                if m_path:
                    current_preset["export_path"] = m_path.group(1)

    presets.sort(key=lambda x: x["id"])
    return presets


def run_command(cmd, dry_run=False):
    """Executes a command or logs it in dry-run mode."""
    cmd_str = " ".join(f'"{c}"' if " " in c else c for c in cmd)
    print(f"--> [EXEC] {cmd_str}")
    if dry_run:
        return 0

    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed with exit code {result.returncode}: {cmd_str}")
    return 0


def determine_data_relative_path(export_path):
    """
    Given an export path like '../LS5E3_Build/LS5E3_Structured/Data/Levels/cityescape.pck'
    or '../Export/data/characters.pck', returns the relative path inside Data/.
    """
    normalized = export_path.replace("\\", "/")
    parts = re.split(r"(?i)/data/", normalized)
    if len(parts) > 1:
        sub = parts[-1]
    else:
        sub = os.path.basename(normalized)
    return os.path.normpath(sub)


def create_zip_archive(source_dir, output_zip_path):
    """
    Creates a zip archive of source_dir.
    Preserves executable and directory permission bits for Linux environments.
    """
    print(f"Creating release archive: {output_zip_path} ...")
    with zipfile.ZipFile(output_zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(source_dir):
            for d in dirs:
                full_dir = os.path.join(root, d)
                rel_dir = os.path.relpath(full_dir, source_dir).replace("\\", "/") + "/"
                zinfo = zipfile.ZipInfo(rel_dir)
                zinfo.external_attr = 0o755 << 16  # rwxr-xr-x
                zf.writestr(zinfo, "")

            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, source_dir).replace("\\", "/")
                zinfo = zipfile.ZipInfo.from_file(full_path, rel_path)
                # Preserve executable permission for Linux binary or shell scripts
                if rel_path.endswith(".x86_64") or rel_path.endswith(".sh"):
                    zinfo.external_attr = 0o755 << 16
                else:
                    zinfo.external_attr = 0o644 << 16
                with open(full_path, "rb") as f:
                    zf.writestr(zinfo, f.read())
    print(f"Archive created: {output_zip_path} ({os.path.getsize(output_zip_path):,} bytes)")


def main():
    parser = argparse.ArgumentParser(description="Export Sonic VANE with structured Data/ pack folders.")
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"), help="Path to Godot binary")
    parser.add_argument("--presets-cfg", default="export_presets.cfg", help="Path to export_presets.cfg")
    parser.add_argument("--output-dir", default="dist", help="Output directory for builds")
    parser.add_argument("--platforms", default="all", help="Comma-separated platforms: windows,linux,macos or all")
    parser.add_argument("--dry-run", action="store_true", help="Print export commands without executing")
    parser.add_argument("--skip-packs", action="store_true", help="Skip building packs (if already staged)")
    parser.add_argument("--archive", action="store_true", help="Create release .zip files for each platform")
    parser.add_argument("--version-tag", default="", help="Version string for archives (e.g. 2026.10.11)")

    args = parser.parse_args()

    presets = parse_export_presets(args.presets_cfg)
    print(f"Loaded {len(presets)} presets from {args.presets_cfg}")

    platform_presets = {}
    pack_presets = []

    for p in presets:
        p_id = p["id"]
        p_name = p["name"]
        p_path = p["export_path"]

        if p_id == 0 or p_name == "Windows Desktop":
            platform_presets["windows"] = p
        elif p_id == 1 or p_name == "Linux":
            platform_presets["linux"] = p
        elif p_id == 2 or p_name == "macOS":
            platform_presets["macos"] = p
        elif p_id >= 3 or p_path.endswith(".pck"):
            pack_presets.append(p)

    target_platforms = (
        ["windows", "linux", "macos"]
        if args.platforms == "all"
        else [x.strip().lower() for x in args.platforms.split(",")]
    )

    common_data_dir = os.path.abspath(os.path.join(args.output_dir, "_common_data"))
    os.makedirs(common_data_dir, exist_ok=True)

    # 1. Build Content Packs (Preset 3 onwards)
    if not args.skip_packs:
        print("\n==========================================")
        print(f"Building {len(pack_presets)} Content Packs into {common_data_dir}")
        print("==========================================")

        for pack in pack_presets:
            rel_path = determine_data_relative_path(pack["export_path"])
            target_pck = os.path.join(common_data_dir, rel_path)
            os.makedirs(os.path.dirname(target_pck), exist_ok=True)

            display_rel = rel_path.replace("\\", "/")
            print(f"Exporting Pack [{pack['id']}] '{pack['name']}' -> Data/{display_rel}")
            cmd = [
                args.godot_bin,
                "--headless",
                "--export-pack",
                pack["name"],
                target_pck,
            ]
            run_command(cmd, dry_run=args.dry_run)

        # Ensure Mods directory exists
        mods_dir = os.path.join(common_data_dir, "Mods")
        os.makedirs(mods_dir, exist_ok=True)
        readme_path = os.path.join(mods_dir, "README_MODS.txt")
        if not os.path.exists(readme_path) and not args.dry_run:
            with open(readme_path, "w", encoding="utf-8") as f:
                f.write("Place user mod .pck files in this folder to load custom content.\n")

    # 2. Build Executable Targets & Assemble Distributions
    for plat in target_platforms:
        print("\n==========================================")
        print(f"Building Platform Target: {plat.upper()}")
        print("==========================================")

        plat_preset = platform_presets.get(plat)
        if not plat_preset:
            print(f"Warning: No preset found for platform '{plat}', skipping.")
            continue

        plat_dir = os.path.abspath(os.path.join(args.output_dir, plat))
        os.makedirs(plat_dir, exist_ok=True)

        # Export Executable
        if plat == "windows":
            exe_target = os.path.join(plat_dir, "SonicVANE_WIN.exe")
            cmd = [args.godot_bin, "--headless", "--export-release", plat_preset["name"], exe_target]
            run_command(cmd, dry_run=args.dry_run)

        elif plat == "linux":
            bin_target = os.path.join(plat_dir, "SonicVANE_LINUX.x86_64")
            cmd = [args.godot_bin, "--headless", "--export-release", plat_preset["name"], bin_target]
            run_command(cmd, dry_run=args.dry_run)
            if not args.dry_run and os.path.exists(bin_target):
                os.chmod(bin_target, 0o755)

        elif plat == "macos":
            # On Linux/CI, Godot exports macOS preset as a .zip containing .app
            mac_zip = os.path.join(plat_dir, "SonicVANE_MAC.zip")
            cmd = [args.godot_bin, "--headless", "--export-release", plat_preset["name"], mac_zip]
            run_command(cmd, dry_run=args.dry_run)

            if not args.dry_run and os.path.exists(mac_zip):
                print(f"Unpacking {mac_zip} into {plat_dir}...")
                with zipfile.ZipFile(mac_zip, "r") as zf:
                    zf.extractall(plat_dir)
                try:
                    os.remove(mac_zip)
                except OSError:
                    pass

        # Copy structured Data/ folder next to the executable
        target_data_dir = os.path.join(plat_dir, "Data")
        if not args.dry_run:
            if os.path.exists(target_data_dir):
                shutil.rmtree(target_data_dir)
            print(f"Copying structured Data folder -> {target_data_dir}")
            shutil.copytree(common_data_dir, target_data_dir)
        else:
            print(f"--> [COPY] {common_data_dir} -> {target_data_dir}")

        # 3. Create Release Archive if requested
        if args.archive:
            tag_suffix = f"-{args.version_tag}" if args.version_tag else ""
            plat_name_title = {"windows": "Windows", "linux": "Linux", "macos": "macOS"}.get(plat, plat.capitalize())
            archive_filename = f"SonicVANE-{plat_name_title}{tag_suffix}.zip"
            archive_path = os.path.abspath(os.path.join(args.output_dir, archive_filename))

            if not args.dry_run:
                create_zip_archive(plat_dir, archive_path)
            else:
                print(f"--> [ARCHIVE] {plat_dir} -> {archive_path}")

    print("\n==========================================")
    print("Export process completed successfully!")
    print("==========================================")


if __name__ == "__main__":
    main()

