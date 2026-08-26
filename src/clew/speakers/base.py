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
    # One entry per enrolled sample -- multi-sample so a single bad clip can't
    # wipe out (or be) the only representation of someone's voice. Matched
    # against a centroid of these, not any single sample; see speakers/matching.py.
    embeddings: list[list[float]] = field(default_factory=list)


def _voiceprint_from_dict(data: dict) -> Voiceprint:
    """Read one voiceprints.json entry, transparently upgrading the pre-multi-sample
    shape (a single flat "embedding" vector) into the current "embeddings" list.

    Never rewrites the file itself -- the next VoiceprintDB.save() call persists
    the upgraded shape, so a store never needs an explicit migration step.
    """
    name = data["name"]
    if "embeddings" in data:
        embeddings = data["embeddings"]
    elif "embedding" in data:
        old = data["embedding"]
        embeddings = [old] if old else []
    else:
        embeddings = []
    return Voiceprint(name=name, embeddings=embeddings)


@dataclass
class VoiceprintDB:
    voiceprints: list[Voiceprint] = field(default_factory=list)

    @classmethod
    def load(cls, path: Path | None = None) -> VoiceprintDB:
        resolved_path = path if path is not None else VOICEPRINT_DB_PATH
        if not resolved_path.exists():
            return cls()
        data = json.loads(resolved_path.read_text())
        return cls(voiceprints=[_voiceprint_from_dict(v) for v in data.get("voiceprints", [])])

    def save(self, path: Path | None = None) -> None:
        resolved_path = path if path is not None else VOICEPRINT_DB_PATH
        resolved_path.parent.mkdir(parents=True, exist_ok=True)
        resolved_path.write_text(json.dumps(asdict(self), indent=2))

    def upsert(self, name: str, embedding: list[float]) -> None:
        """Add one enrollment sample under `name`, creating the entry if new.

        Appends rather than replaces (unbounded -- enrollment is a rare,
        deliberate user action, not something that runs unattended, so nothing
        in real usage currently justifies a cap; add one later if usage ever
        shows unbounded growth as an actual problem).
        """
        for vp in self.voiceprints:
            if vp.name == name:
                vp.embeddings.append(embedding)
                return
        self.voiceprints.append(Voiceprint(name=name, embeddings=[embedding]))

    def remove(self, name: str) -> bool:
        before = len(self.voiceprints)
        self.voiceprints = [vp for vp in self.voiceprints if vp.name != name]
        return len(self.voiceprints) != before
