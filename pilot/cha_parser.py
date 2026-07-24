"""Parser for CHAT-format (.cha) transcripts, scoped to what the FEBLOC pilot needs.

Not a general CHAT parser -- handles exactly the annotation conventions FEBLOC's
pair01-anon.cha actually uses (confirmed by reading the real file end to end
before writing this): @-header lines, *SPEAKER: utterance lines with a trailing
start_end millisecond timestamp wrapped in CHAT's 0x15 (NAK) media-bullet
control character (invisible in a terminal/grep/sed view -- only found by
reading the raw bytes; every one of 1466 utterance lines has exactly one
0x15-wrapped timestamp), %eng: gloss lines (skipped, not part of the
French/English reference), and inline markers:

  word@s:fra / word@s:eng / word@s:eng&fra / word@s:fra+eng / word@s:eng+fra
      per-word language tag -- the ground truth this pilot's per-language WER
      split is built from.
  [- fra] / [- eng]
      utterance-level default language when words aren't individually tagged.
  word[: correction]
      "word" is what was actually said; "correction" is the standard form.
      Kept as "word" -- WER references what was spoken, not the idealization.
  (syllable)
      an elided-but-implied syllable inside a word, e.g. c(e) -- pronounced
      without it. Stripped, since the syllable was not actually pronounced.
  word:
      vowel lengthening -- same word, held longer. Colon stripped.
  0word
      a grammatically-implied word that was NOT actually spoken. Dropped
      entirely -- an ASR system correctly transcribing the audio should not
      produce this word either.
  &=event
      a non-verbal sound event (laughs, breathes, coughs...). Dropped.
  &-filler
      a verbal filler/hesitation (uh, um, hm). Kept as a literal token --
      it was genuinely spoken and audible.
  &+fragment
      an incomplete word-start, abandoned mid-utterance. Dropped -- it is
      not a complete lexical token and has no correct ASR transcription.
  [///] / [//] / [/]
      retracing/repetition markers. Stripped; the words around them (both
      the abandoned false-start and the restart) are kept, since both were
      genuinely spoken.
  [?]
      transcriber uncertainty marker. Stripped, word kept.
  +< / +... / +" / +/.
      turn-overlap/trail-off/quote/interruption markers at the start of an
      utterance. Stripped (they carry no lexical content).
"""

from __future__ import annotations

import re
from dataclasses import dataclass

_TIMESTAMP_RE = re.compile(r"\x15?(\d+)_(\d+)\x15?\s*$")
_LANG_TAG_RE = re.compile(r"@s:(eng|fra)(?:[&+](?:eng|fra))?")
_CORRECTION_RE = re.compile(r"\[:\s*[^\]]*\]")
_RETRACE_RE = re.compile(r"\[/{1,3}\??\]")
_UNCERTAIN_RE = re.compile(r"\[\?\]")
_ERROR_CODE_RE = re.compile(r"\[\*\]")
_SPEECH_MANNER_RE = re.compile(r"\[=!?\s*[^\]]*\]")
_MANNER_SCOPE_BRACKETS_RE = re.compile(r"<([^>]*)>")
_UTTERANCE_LANG_RE = re.compile(r"\[-\s*(fra|eng)\]")
_ELISION_RE = re.compile(r"\(([a-zA-Zàâéèêëîïôùûüç]+)\)")
_LENGTHENING_RE = re.compile(r"([a-zA-Zàâéèêëîïôùûüçéè])(:+)")
_OMITTED_WORD_RE = re.compile(r"\b0[a-zA-Zàâéèêëîïôùûüç]+\b")
_NONVERBAL_EVENT_RE = re.compile(r"&=[a-z:]+")
_WORD_FRAGMENT_RE = re.compile(r"&\+[a-zA-Zàâéèêëîïôùûüç]*")
_TURN_MARKER_RE = re.compile(r'^\+[<."/]*\s*')
_TRAILING_MARKER_RE = re.compile(r'(?:^|\s)\+[.,"/]*\??\s*$')


@dataclass
class Utterance:
    speaker: str
    start_ms: int
    end_ms: int
    words: list[str]
    word_languages: list[str]


def _strip_lang_tag(token: str) -> tuple[str, str | None]:
    """Return (bare_word, language) for a word carrying an @s: language tag."""
    match = _LANG_TAG_RE.search(token)
    if not match:
        return token, None
    return _LANG_TAG_RE.sub("", token), match.group(1)


def _clean_word(token: str) -> str:
    token = _ELISION_RE.sub(r"\1", token)
    token = _LENGTHENING_RE.sub(r"\1", token)
    return token.strip(" .,!?()").lower()


def _parse_utterance_line(line: str) -> Utterance | None:
    if not line.startswith("*"):
        return None
    speaker, _, rest = line[1:].partition(":")
    rest = rest.strip()

    timestamp_match = _TIMESTAMP_RE.search(rest)
    if not timestamp_match:
        return None
    start_ms, end_ms = int(timestamp_match.group(1)), int(timestamp_match.group(2))
    rest = rest[: timestamp_match.start()].strip()

    rest = _TURN_MARKER_RE.sub("", rest)

    default_lang_match = _UTTERANCE_LANG_RE.search(rest)
    default_lang = default_lang_match.group(1) if default_lang_match else None
    rest = _UTTERANCE_LANG_RE.sub("", rest)

    rest = _CORRECTION_RE.sub("", rest)
    rest = _RETRACE_RE.sub("", rest)
    rest = _UNCERTAIN_RE.sub("", rest)
    rest = _ERROR_CODE_RE.sub("", rest)
    rest = _SPEECH_MANNER_RE.sub("", rest)
    rest = _MANNER_SCOPE_BRACKETS_RE.sub(r"\1", rest)
    rest = _OMITTED_WORD_RE.sub("", rest)
    rest = _NONVERBAL_EVENT_RE.sub("", rest)
    rest = _WORD_FRAGMENT_RE.sub("", rest)
    rest = _TRAILING_MARKER_RE.sub("", rest)

    words: list[str] = []
    word_languages: list[str] = []
    for raw_token in rest.split():
        bare, tagged_lang = _strip_lang_tag(raw_token)
        cleaned = _clean_word(bare)
        if not cleaned:
            continue
        words.append(cleaned)
        word_languages.append(tagged_lang or default_lang or "unknown")

    if not words:
        return None
    return Utterance(speaker=speaker, start_ms=start_ms, end_ms=end_ms, words=words, word_languages=word_languages)


def parse_cha(text: str) -> list[Utterance]:
    """Parse a CHAT-format transcript into a list of Utterance, skipping headers and %eng: glosses."""
    utterances = []
    for line in text.splitlines():
        utterance = _parse_utterance_line(line)
        if utterance is not None:
            utterances.append(utterance)
    return utterances


def utterances_in_window(utterances: list[Utterance], start_ms: int, end_ms: int) -> list[Utterance]:
    """Utterances whose timestamp span overlaps [start_ms, end_ms)."""
    return [u for u in utterances if u.start_ms < end_ms and u.end_ms > start_ms]
