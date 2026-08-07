from __future__ import annotations

import json
from pathlib import Path


def save_anchors(anchors: dict[str, list[dict[str, str]]], output_dir: Path) -> None:
    """
    Save the anchoring result to a JSON file next to the meeting files.

    The output file is named 'anchors.json' and contains a mapping from
    rare tokens to their timestamp anchors in the transcript.
    """
    output_path = output_dir / "anchors.json"

    output_data = {"version": "1.0", "anchors": anchors}

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(output_data, f, ensure_ascii=False, indent=2)
