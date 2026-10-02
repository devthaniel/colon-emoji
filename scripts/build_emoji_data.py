#!/usr/bin/env python3
"""Flatten an @emoji-mart/data native.json into Resources/emoji.json.

Usage: build_emoji_data.py <path/to/@emoji-mart/data/sets/15/native.json>
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

source_path = Path(sys.argv[1])
output_path = Path(__file__).resolve().parent.parent / "Resources" / "emoji.json"

source = json.loads(source_path.read_text())

aliases_by_emoji_id: dict[str, list[str]] = defaultdict(list)
for alias, emoji_id in source["aliases"].items():
    aliases_by_emoji_id[emoji_id].append(alias)

ordered_emoji_ids = [
    emoji_id for category in source["categories"] for emoji_id in category["emojis"]
]

entries = []
for emoji_id in ordered_emoji_ids:
    emoji = source["emojis"][emoji_id]
    entries.append(
        {
            "id": emoji_id,
            "name": emoji["name"],
            "keywords": emoji["keywords"],
            "aliases": aliases_by_emoji_id[emoji_id],
            "native": emoji["skins"][0]["native"],
        }
    )

output_path.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")))
print(f"wrote {len(entries)} emoji to {output_path}")
