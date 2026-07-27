"""Every utterance in a markdown transcript must carry its own timestamp."""

from __future__ import annotations

import re

from ownscribe.output.markdown import format_transcript
from ownscribe.transcription.models import Segment, TranscriptResult

TIMESTAMPED_LINE = re.compile(r"^\[\d+:\d{2}\]\s+\S")
SPEAKER_HEADER = re.compile(r"^\*\*[^*]+\*\*\s+\[\d+:\d{2}\]$")


def _diarized(turns: list[tuple[str, float, str]]) -> TranscriptResult:
    return TranscriptResult(
        segments=[Segment(text=text, start=start, end=start + 1.0, speaker=speaker) for speaker, start, text in turns],
        language="fr",
        duration=turns[-1][1] + 1.0 if turns else 0.0,
    )


class TestEveryUtteranceIsTimestamped:
    def test_first_utterance_of_a_turn_carries_its_own_timestamp(self):
        result = _diarized(
            [
                ("SPEAKER_01", 309.0, "Une image de coeur qui se deploie sur la Lambda."),
                ("SPEAKER_01", 328.0, "Et devant, c'est toujours le JWT ?"),
            ]
        )

        body = format_transcript(result)
        utterances = [line for line in body.splitlines() if TIMESTAMPED_LINE.match(line)]

        assert len(utterances) == 2, (
            "A reader that matches [mm:ss] lines must see every utterance; the first line of a "
            f"speaker turn was dropped. Got:\n{body}"
        )
        assert "[05:09] Une image de coeur qui se deploie sur la Lambda." in utterances[0]

    def test_no_utterance_is_left_as_a_bare_line(self):
        result = _diarized(
            [
                ("SPEAKER_01", 0.0, "Premier tour."),
                ("SPEAKER_00", 10.0, "Deuxieme tour."),
                ("SPEAKER_01", 20.0, "Troisieme tour."),
            ]
        )

        body = format_transcript(result)
        content = [line for line in body.splitlines() if line.strip() and not line.startswith("**Language")]
        orphans = [
            line
            for line in content
            if not TIMESTAMPED_LINE.match(line)
            and not SPEAKER_HEADER.match(line)
            and not line.startswith(("#", "**Duration"))
        ]

        assert orphans == [], f"These lines carry text but no timestamp, so a parser drops them: {orphans}"

    def test_speaker_change_count_matches_turn_count(self):
        result = _diarized(
            [
                ("SPEAKER_01", 0.0, "A."),
                ("SPEAKER_01", 5.0, "B."),
                ("SPEAKER_00", 10.0, "C."),
            ]
        )

        body = format_transcript(result)
        headers = [line for line in body.splitlines() if SPEAKER_HEADER.match(line)]
        utterances = [line for line in body.splitlines() if TIMESTAMPED_LINE.match(line)]

        assert len(headers) == 2
        assert len(utterances) == 3, "Three segments must yield three timestamped utterances"

    def test_undiarized_transcript_is_unaffected(self):
        result = TranscriptResult(
            segments=[
                Segment(text="Hello world.", start=0.0, end=1.5),
                Segment(text="How are you?", start=1.5, end=3.0),
            ],
            language="en",
            duration=3.0,
        )

        utterances = [line for line in format_transcript(result).splitlines() if TIMESTAMPED_LINE.match(line)]

        assert len(utterances) == 2
