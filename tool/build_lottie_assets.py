#!/usr/bin/env python3
"""Build brand-colored Lottie assets for Nool."""
from __future__ import annotations

import json
from pathlib import Path

ACID = [0xAD / 255, 0xFF / 255, 0x2F / 255, 1.0]
TANGERINE = [0xFF / 255, 0x6F / 255, 0x61 / 255, 1.0]

OUT = Path("/Users/efeardaaric/Desktop/Nool/assets/lottie")
TMP = Path("/tmp/lottie_try")
OUT.mkdir(parents=True, exist_ok=True)


def walk_recolor(obj, target: list[float]) -> None:
    if isinstance(obj, dict):
        if "k" in obj and isinstance(obj["k"], list) and len(obj["k"]) in (3, 4):
            k = obj["k"]
            if all(isinstance(x, (int, float)) for x in k[:3]):
                r, g, b = float(k[0]), float(k[1]), float(k[2])
                mx, mn = max(r, g, b), min(r, g, b)
                if mx - mn > 0.08 and mx > 0.15:
                    a = float(k[3]) if len(k) > 3 else 1.0
                    obj["k"] = [target[0], target[1], target[2], a]
        for v in obj.values():
            walk_recolor(v, target)
    elif isinstance(obj, list):
        for item in obj:
            walk_recolor(item, target)


def transform() -> dict:
    return {
        "ty": "tr",
        "p": {"a": 0, "k": [0, 0]},
        "a": {"a": 0, "k": [0, 0]},
        "s": {"a": 0, "k": [100, 100]},
        "r": {"a": 0, "k": 0},
        "o": {"a": 0, "k": 100},
        "sk": {"a": 0, "k": 0},
        "sa": {"a": 0, "k": 0},
    }


def make_radar() -> dict:
    fr, op = 60, 90
    layers = []
    for i, delay in enumerate([0, 15, 30]):
        layers.append(
            {
                "ddd": 0,
                "ind": i + 1,
                "ty": 4,
                "nm": f"Ring{i}",
                "sr": 1,
                "ks": {
                    "o": {
                        "a": 1,
                        "k": [
                            {"t": delay, "s": [0], "e": [85]},
                            {"t": delay + 40, "s": [85], "e": [0]},
                            {"t": delay + 60, "s": [0]},
                        ],
                    },
                    "r": {"a": 0, "k": 0},
                    "p": {"a": 0, "k": [150, 150, 0]},
                    "a": {"a": 0, "k": [0, 0, 0]},
                    "s": {
                        "a": 1,
                        "k": [
                            {"t": delay, "s": [18, 18, 100], "e": [100, 100, 100]},
                            {"t": delay + 60, "s": [100, 100, 100]},
                        ],
                    },
                },
                "ao": 0,
                "shapes": [
                    {
                        "ty": "el",
                        "p": {"a": 0, "k": [0, 0]},
                        "s": {"a": 0, "k": [220, 220]},
                        "nm": "Ellipse",
                    },
                    {
                        "ty": "st",
                        "c": {"a": 0, "k": ACID},
                        "o": {"a": 0, "k": 100},
                        "w": {"a": 0, "k": 6},
                        "lc": 2,
                        "lj": 2,
                        "nm": "Stroke",
                    },
                    transform(),
                ],
                "ip": 0,
                "op": op,
                "st": 0,
                "bm": 0,
            }
        )

    layers.append(
        {
            "ddd": 0,
            "ind": 10,
            "ty": 4,
            "nm": "Core",
            "sr": 1,
            "ks": {
                "o": {"a": 0, "k": 100},
                "r": {"a": 0, "k": 0},
                "p": {"a": 0, "k": [150, 150, 0]},
                "a": {"a": 0, "k": [0, 0, 0]},
                "s": {
                    "a": 1,
                    "k": [
                        {"t": 0, "s": [80, 80, 100], "e": [125, 125, 100]},
                        {"t": 45, "s": [125, 125, 100], "e": [80, 80, 100]},
                        {"t": 90, "s": [80, 80, 100]},
                    ],
                },
            },
            "ao": 0,
            "shapes": [
                {
                    "ty": "el",
                    "p": {"a": 0, "k": [0, 0]},
                    "s": {"a": 0, "k": [28, 28]},
                    "nm": "Ellipse",
                },
                {
                    "ty": "fl",
                    "c": {"a": 0, "k": ACID},
                    "o": {"a": 0, "k": 100},
                    "r": 1,
                    "nm": "Fill",
                },
                transform(),
            ],
            "ip": 0,
            "op": op,
            "st": 0,
            "bm": 0,
        }
    )
    return {
        "v": "5.7.4",
        "fr": fr,
        "ip": 0,
        "op": op,
        "w": 300,
        "h": 300,
        "nm": "Nool Radar",
        "ddd": 0,
        "assets": [],
        "layers": layers,
    }


def make_fire() -> dict:
    """Simple tangerine flame pulse."""
    fr, op = 60, 60
    layer = {
        "ddd": 0,
        "ind": 1,
        "ty": 4,
        "nm": "Flame",
        "sr": 1,
        "ks": {
            "o": {"a": 0, "k": 100},
            "r": {
                "a": 1,
                "k": [
                    {"t": 0, "s": [-6], "e": [6]},
                    {"t": 30, "s": [6], "e": [-6]},
                    {"t": 60, "s": [-6]},
                ],
            },
            "p": {"a": 0, "k": [100, 120, 0]},
            "a": {"a": 0, "k": [0, 40, 0]},
            "s": {
                "a": 1,
                "k": [
                    {"t": 0, "s": [90, 100, 100], "e": [110, 120, 100]},
                    {"t": 30, "s": [110, 120, 100], "e": [90, 100, 100]},
                    {"t": 60, "s": [90, 100, 100]},
                ],
            },
        },
        "ao": 0,
        "shapes": [
            {
                "ty": "sh",
                "ks": {
                    "a": 0,
                    "k": {
                        "i": [[0, 0], [0, 0], [0, 0], [0, 0]],
                        "o": [[0, 0], [0, 0], [0, 0], [0, 0]],
                        "v": [[0, -70], [28, 10], [0, 55], [-28, 10]],
                        "c": True,
                    },
                },
                "nm": "Path",
            },
            {
                "ty": "fl",
                "c": {"a": 0, "k": TANGERINE},
                "o": {"a": 0, "k": 100},
                "r": 1,
                "nm": "Fill",
            },
            transform(),
        ],
        "ip": 0,
        "op": op,
        "st": 0,
        "bm": 0,
    }
    core = {
        "ddd": 0,
        "ind": 2,
        "ty": 4,
        "nm": "Core",
        "sr": 1,
        "ks": {
            "o": {"a": 0, "k": 100},
            "r": {"a": 0, "k": 0},
            "p": {"a": 0, "k": [100, 135, 0]},
            "a": {"a": 0, "k": [0, 0, 0]},
            "s": {"a": 0, "k": [100, 100, 100]},
        },
        "ao": 0,
        "shapes": [
            {
                "ty": "el",
                "p": {"a": 0, "k": [0, 0]},
                "s": {"a": 0, "k": [22, 28]},
                "nm": "Ellipse",
            },
            {
                "ty": "fl",
                "c": {"a": 0, "k": ACID},
                "o": {"a": 0, "k": 100},
                "r": 1,
                "nm": "Fill",
            },
            transform(),
        ],
        "ip": 0,
        "op": op,
        "st": 0,
        "bm": 0,
    }
    return {
        "v": "5.7.4",
        "fr": fr,
        "ip": 0,
        "op": op,
        "w": 200,
        "h": 200,
        "nm": "Nool Fire",
        "ddd": 0,
        "assets": [],
        "layers": [layer, core],
    }


def main() -> None:
    import subprocess

    for junk in list(OUT.glob("*.json")):
        junk.unlink()

    ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    downloads = [
        (
            "neon_loading.json",
            "https://assets9.lottiefiles.com/packages/lf20_p8bfn5to.json",
            ACID,
        ),
        (
            "success_check.json",
            "https://assets10.lottiefiles.com/packages/lf20_jbrw3hcz.json",
            ACID,
        ),
    ]
    for name, url, color in downloads:
        path = OUT / name
        subprocess.check_call(
            ["curl", "-sL", "-A", ua, "-o", str(path), url],
        )
        data = json.loads(path.read_text())
        walk_recolor(data, color)
        path.write_text(json.dumps(data))
        print(f"wrote {name} nm={data.get('nm')}")

    mapping = [
        ("acid_loader.json", "lf20_jk6c1n2n.json", ACID),
        ("sparkle_confetti.json", "lf20_obhph3sh.json", TANGERINE),
        ("fire_energy.json", "lf20_uu0x8lqv.json", TANGERINE),
    ]
    for out_name, src_name, color in mapping:
        src = TMP / src_name
        if src.exists() and src.stat().st_size > 800:
            data = json.loads(src.read_text())
            walk_recolor(data, color)
            (OUT / out_name).write_text(json.dumps(data))
            print(f"wrote {out_name} nm={data.get('nm')} size={src.stat().st_size}")

    (OUT / "radar_scan.json").write_text(json.dumps(make_radar()))
    print("wrote radar_scan.json")
    (OUT / "fire_pulse.json").write_text(json.dumps(make_fire()))
    print("wrote fire_pulse.json")

    print("Final:")
    for f in sorted(OUT.glob("*.json")):
        print(f"  {f.name:28} {f.stat().st_size:8d}")


if __name__ == "__main__":
    main()
