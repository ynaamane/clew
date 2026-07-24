"""Tests for pilot/cha_parser.py, the FEBLOC CHAT-format transcript parser.

Every fixture line below is copied VERBATIM (including the literal 0x15
control-character timestamp wrapper) from the real downloaded
FEBLOC-pair01-anon.cha transcript -- not synthesized -- since the parser's
correctness was established by reading the real file end to end and this
suite pins that reading down as regression coverage.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "pilot"))

from cha_parser import Utterance, parse_cha, utterances_in_window


def _line(raw: str) -> str:
    """Wrap a bare '<content> <start>_<end>' string in the real 0x15 NAK bullet."""
    content, _, timestamp = raw.rpartition(" ")
    return f"{content} \x15{timestamp}\x15"


class TestBasicUtterance:
    def test_parses_speaker_words_and_timestamp(self):
        line = _line("*INV:\t[- fra] j(e) ferme la porte . 0_878")
        result = parse_cha(line)
        assert len(result) == 1
        u = result[0]
        assert u.speaker == "INV"
        assert u.start_ms == 0
        assert u.end_ms == 878
        assert u.words == ["je", "ferme", "la", "porte"]
        assert u.word_languages == ["fra", "fra", "fra", "fra"]

    def test_non_utterance_lines_are_skipped(self):
        text = "@UTF8\n@Begin\n%eng:\tsome gloss\n@End"
        assert parse_cha(text) == []

    def test_line_without_timestamp_is_skipped(self):
        line = "*INV:\t[- fra] no timestamp here ."
        assert parse_cha(line) == []


class TestLanguageTags:
    def test_per_word_language_tags(self):
        line = _line("*KEV:\tpis@s:fra un@s:fra sac@s:fra à@s:fra chip(s)@s:eng+fra . 1498498_1499504")
        u = parse_cha(line)[0]
        assert u.words == ["pis", "un", "sac", "à", "chips"]
        assert u.word_languages == ["fra", "fra", "fra", "fra", "eng"]

    def test_utterance_level_default_language_applies_to_untagged_words(self):
        line = _line("*INV:\t[- fra] j(e) ferme la porte . 0_878")
        u = parse_cha(line)[0]
        assert all(lang == "fra" for lang in u.word_languages)

    def test_untagged_word_with_no_utterance_default_is_unknown(self):
        line = _line("*KEV:\tokay . 100_200")
        u = parse_cha(line)[0]
        assert u.word_languages == ["unknown"]


class TestCorrectionBrackets:
    def test_correction_bracket_keeps_the_spoken_form_not_the_correction(self):
        line = _line("*KEV:\tah@s:eng&fra &+é cé [: c'est] défendu . 790446_791663")
        u = parse_cha(line)[0]
        assert "cé" in u.words
        assert "c'est" not in u.words
        assert "défendu" in u.words

    def test_double_colon_correction_variant(self):
        line = _line(
            "*MAN:\tj'essayais pas (..) 0de le [/] le comparer à la situaction "
            "[:: situation] [*] &+ac 0actuelle [//] (.) la situation actuelle . 3093586_3099354"
        )
        u = parse_cha(line)[0]
        assert "situaction" in u.words
        assert "situation" in u.words
        assert "0de" not in u.words
        assert "0actuelle" not in u.words
        assert not any("[" in w or "]" in w for w in u.words)


class TestRetracingAndUncertainty:
    def test_retrace_marker_keeps_both_the_false_start_and_the_restart(self):
        line = _line("*MAN:\tun: (.) c(e) qui &+s [///] ça dl'air [: a de l'air] d'être un bas vert ? 1492549_1495848")
        u = parse_cha(line)[0]
        assert "un" in u.words
        assert "ça" in u.words
        assert "dl'air" in u.words
        assert not any("[" in w for w in u.words)

    def test_uncertainty_marker_stripped_word_kept(self):
        line = _line(
            "*KEV:\t(o)kay@s:eng&fra y'a@s:fra [: il y a] un@s:fra toutou@s:fra "
            "&-uh jaune@s:fra qui:@s:fra fall@s:eng+fra [?] . 1508269_1511253"
        )
        u = parse_cha(line)[0]
        assert "fall" in u.words
        assert not any("?" in w for w in u.words if w != "y'a")


class TestElisionAndLengthening:
    def test_elided_syllable_in_parens_is_dropped_keeping_the_pronounced_part(self):
        line = _line("*INV:\t[- fra] j(e) ferme la porte . 0_878")
        u = parse_cha(line)[0]
        assert "je" in u.words
        assert "j(e)" not in u.words

    def test_vowel_lengthening_colon_is_stripped(self):
        line = _line("*KEV:\t[- fra] l'enfant dans le: [/] le: [/] le &=lip:trill . 1501406_1503906")
        u = parse_cha(line)[0]
        assert u.words == ["l'enfant", "dans", "le", "le", "le"]


class TestOmittedWordsAndNonverbalEvents:
    def test_zero_prefixed_omitted_word_is_dropped(self):
        line = _line("*INV:\t[- fra] si quelqu'un s(e) lève . 4169_5359")
        u = parse_cha(line)[0]
        assert "0de" not in u.words

    def test_nonverbal_event_is_dropped(self):
        line = _line("*KEV:\t[- fra] l'enfant dans le: [/] le: [/] le &=lip:trill . 1501406_1503906")
        u = parse_cha(line)[0]
        assert not any("lip" in w for w in u.words)

    def test_verbal_filler_is_kept_as_a_literal_token(self):
        line = _line("*KEV:\t&-uh real@s:eng estate@s:eng agents@s:eng ? 1511453_1513466")
        u = parse_cha(line)[0]
        assert "&-uh" in u.words

    def test_word_fragment_is_dropped(self):
        line = _line("*MAN:\tun: (.) c(e) qui &+s [///] ça dl'air [: a de l'air] d'être un bas vert ? 1492549_1495848")
        u = parse_cha(line)[0]
        assert not any(w.startswith("&+") for w in u.words)


class TestTurnAndTrailingMarkers:
    def test_leading_turn_overlap_marker_is_stripped(self):
        line = _line("*KEV:\t+< [- fra] cannette mauve . 1497535_1498498")
        u = parse_cha(line)[0]
        assert u.words == ["cannette", "mauve"]

    def test_trailing_off_marker_is_stripped(self):
        line = _line("*MAN:\t[- fra] une cannette (.) mauve +... 1496546_1498435")
        u = parse_cha(line)[0]
        assert u.words == ["une", "cannette", "mauve"]

    def test_leading_quote_marker_is_stripped(self):
        line = _line('*KEV:\t+" [- eng] &-uh real estate agents ? 1511453_1513466')
        u = parse_cha(line)[0]
        assert u.words[0] != '+"'


class TestSpeechMannerAndErrorCode:
    def test_speech_manner_comment_is_stripped_scoped_word_kept(self):
        line = _line("*MAN:\t[- eng] okay@s:eng&fra (.) <well> [=! mumbles] . 1352634_1353716")
        u = parse_cha(line)[0]
        assert "well" in u.words
        assert not any("[" in w or "<" in w or ">" in w for w in u.words)

    def test_plain_speech_manner_without_bang_is_stripped(self):
        line = _line("*MAN:\t[- eng] yeah [= mumbles] . 1843704_1844078")
        u = parse_cha(line)[0]
        assert u.words == ["yeah"]

    def test_error_code_marker_is_stripped(self):
        line = _line("*KEV:\t[- fra] voir le [/] le [*] grand [*] image là alors . 3022052_3024127")
        u = parse_cha(line)[0]
        assert not any("*" in w for w in u.words)
        assert "grand" in u.words
        assert "image" in u.words


class TestUtterancesInWindow:
    def test_filters_by_overlap_with_window(self):
        utterances = [
            Utterance(speaker="A", start_ms=0, end_ms=1000, words=["x"], word_languages=["fra"]),
            Utterance(speaker="B", start_ms=1000, end_ms=2000, words=["y"], word_languages=["fra"]),
            Utterance(speaker="C", start_ms=5000, end_ms=6000, words=["z"], word_languages=["fra"]),
        ]
        result = utterances_in_window(utterances, 500, 1500)
        assert [u.speaker for u in result] == ["A", "B"]

    def test_empty_window_returns_empty(self):
        utterances = [Utterance(speaker="A", start_ms=0, end_ms=1000, words=["x"], word_languages=["fra"])]
        assert utterances_in_window(utterances, 5000, 6000) == []


class TestNoLeftoverMarkers:
    """Regression guard: no CHAT annotation syntax should ever survive into a
    cleaned word. Exercises every marker class in one line."""

    def test_a_line_with_every_marker_class_leaves_no_bracket_or_angle_syntax(self):
        line = _line(
            "*KEV:\t+< [- fra] &-uh pis@s:fra [: puis] un: (e) sac@s:fra à@s:fra "
            "chip(s)@s:eng+fra &+ch [///] &=laughs <well> [=! mumbles] [*] [?] 0de +... 100_200"
        )
        u = parse_cha(line)[0]
        for w in u.words:
            assert not any(c in w for c in "[]<>@"), f"leftover marker syntax in {w!r}"
            assert not w.startswith("0"), f"leftover omitted-word marker in {w!r}"
            assert not w.startswith("&+"), f"leftover fragment marker in {w!r}"
            assert not w.startswith("&="), f"leftover nonverbal-event marker in {w!r}"
