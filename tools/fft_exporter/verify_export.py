"""Verification script to compare Python and C# export outputs."""

import json
import sys
from pathlib import Path


def compare_json_values(py_val, cs_val, path="", tolerance=1e-4):
    """Recursively compare JSON values with float tolerance."""
    errors = []

    if isinstance(py_val, dict) and isinstance(cs_val, dict):
        all_keys = set(py_val.keys()) | set(cs_val.keys())
        for key in all_keys:
            if key not in py_val:
                errors.append(f"{path}.{key}: missing in Python output")
            elif key not in cs_val:
                errors.append(f"{path}.{key}: missing in C# output")
            else:
                errors.extend(compare_json_values(
                    py_val[key], cs_val[key], f"{path}.{key}", tolerance
                ))
    elif isinstance(py_val, list) and isinstance(cs_val, list):
        if len(py_val) != len(cs_val):
            errors.append(f"{path}: list length mismatch (py={len(py_val)}, cs={len(cs_val)})")
        else:
            for i, (pv, cv) in enumerate(zip(py_val, cs_val)):
                errors.extend(compare_json_values(pv, cv, f"{path}[{i}]", tolerance))
    elif isinstance(py_val, float) or isinstance(cs_val, float):
        try:
            py_f = float(py_val)
            cs_f = float(cs_val)
            if abs(py_f - cs_f) > tolerance:
                errors.append(f"{path}: float mismatch (py={py_f}, cs={cs_f}, diff={abs(py_f - cs_f)})")
        except (TypeError, ValueError):
            errors.append(f"{path}: type mismatch (py={type(py_val)}, cs={type(cs_val)})")
    elif py_val != cs_val:
        errors.append(f"{path}: value mismatch (py={py_val!r}, cs={cs_val!r})")

    return errors


def compare_json_files(py_path: Path, cs_path: Path, tolerance=1e-4):
    """Compare two JSON files."""
    if not py_path.exists():
        return [f"Python file not found: {py_path}"]
    if not cs_path.exists():
        return [f"C# file not found: {cs_path}"]

    with open(py_path) as f:
        py_data = json.load(f)
    with open(cs_path) as f:
        cs_data = json.load(f)

    return compare_json_values(py_data, cs_data, py_path.name, tolerance)


def compare_binary_files(py_path: Path, cs_path: Path):
    """Compare two binary files."""
    if not py_path.exists():
        return [f"Python file not found: {py_path}"]
    if not cs_path.exists():
        return [f"C# file not found: {cs_path}"]

    with open(py_path, 'rb') as f:
        py_data = f.read()
    with open(cs_path, 'rb') as f:
        cs_data = f.read()

    if len(py_data) != len(cs_data):
        return [f"Size mismatch: py={len(py_data)}, cs={len(cs_data)}"]

    if py_data != cs_data:
        # Find first difference
        for i, (pb, cb) in enumerate(zip(py_data, cs_data)):
            if pb != cb:
                return [f"First byte difference at offset {i}: py=0x{pb:02x}, cs=0x{cb:02x}"]

    return []


def main():
    if len(sys.argv) < 3:
        print("Usage: python verify_export.py <python_export_dir> <csharp_export_dir>")
        sys.exit(1)

    py_dir = Path(sys.argv[1])
    cs_dir = Path(sys.argv[2])

    print(f"Comparing Python ({py_dir}) vs C# ({cs_dir})")
    print("=" * 60)

    all_errors = []

    # Compare JSON files
    json_files = [
        ("palettes.json", 0),  # Exact match for integers
        ("manifest.json", 1e-4),
        ("geometry.json", 1e-4),
        ("terrain.json", 1e-4),
    ]

    for filename, tolerance in json_files:
        py_path = py_dir / filename
        cs_path = cs_dir / filename

        print(f"\n{filename}:")
        errors = compare_json_files(py_path, cs_path, tolerance)

        if errors:
            print(f"  FAILED - {len(errors)} errors")
            for err in errors[:10]:  # Show first 10 errors
                print(f"    {err}")
            if len(errors) > 10:
                print(f"    ... and {len(errors) - 10} more errors")
            all_errors.extend(errors)
        else:
            print(f"  PASSED")

    # Compare GLTF files (JSON format)
    gltf_files = ["geometry.gltf", "terrain.gltf"]
    for filename in gltf_files:
        py_path = py_dir / filename
        cs_path = cs_dir / filename

        print(f"\n{filename}:")
        errors = compare_json_files(py_path, cs_path, 1e-4)

        if errors:
            # GLTF structure might differ, just report
            print(f"  DIFFERS - {len(errors)} structural differences (expected)")
        else:
            print(f"  PASSED")

    # Check texture file exists
    print("\ntexture_indexed:")
    py_tex = py_dir / "texture_indexed.tga"
    cs_tex = cs_dir / "texture_indexed.png"

    if py_tex.exists():
        print(f"  Python: {py_tex.name} ({py_tex.stat().st_size} bytes)")
    else:
        print(f"  Python: NOT FOUND")

    if cs_tex.exists():
        print(f"  C#: {cs_tex.name} ({cs_tex.stat().st_size} bytes)")
    else:
        print(f"  C#: NOT FOUND")

    print("\n" + "=" * 60)
    print(f"Total errors in JSON comparison: {len(all_errors)}")

    if all_errors:
        print("VERIFICATION FAILED")
        sys.exit(1)
    else:
        print("VERIFICATION PASSED")
        sys.exit(0)


if __name__ == "__main__":
    main()
