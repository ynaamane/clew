"""Data model and storage for enrolled speaker voiceprints."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

VOICEPRINT_DIR = Path("~/.config/clew/voiceprints").expanduser()
VOICEPRINT_DB_PATH = VOICEPRINT_DIR / "voiceprints.json"

# Legacy location from the meeting-scribe era. Read only by clew.cli.main()'s
# one-time startup migration -- never referenced here otherwise.
LEGACY_VOICEPRINT_DIR = Path("~/.config/meeting-scribe/voiceprints").expanduser()

DEFAULT_MATCH_THRESHOLD = 0.65


@dataclass
class Voiceprint:
    name: str
    embedding: list[float] = field(default_factory=list)


@dataclass
class VoiceprintDB:
    voiceprints: list[Voiceprint] = field(default_factory=list)

    @classmethod
    def load(cls, path: Path | None = None) -> VoiceprintDB:
        resolved_path = path if path is not None else VOICEPRINT_DB_PATH
        if not resolved_path.exists():
            return cls()
        data = json.loads(resolved_path.read_text())
        return cls(voiceprints=[Voiceprint(**v) for v in data.get("voiceprints", [])])

    def save(self, path: Path | None = None) -> None:
        resolved_path = path if path is not None else VOICEPRINT_DB_PATH
        resolved_path.parent.mkdir(parents=True, exist_ok=True)
        resolved_path.write_text(json.dumps(asdict(self), indent=2))

    def upsert(self, name: str, embedding: list[float]) -> None:
        for vp in self.voiceprints:
            if vp.name == name:
                vp.embedding = embedding
                return
        self.voiceprints.append(Voiceprint(name=name, embedding=embedding))

    def remove(self, name: str) -> bool:
        before = len(self.voiceprints)
        self.voiceprints = [vp for vp in self.voiceprints if vp.name != name]
        return len(self.voiceprints) != before
