"""Tests for detecting summarizer-invented names not present in the source transcript."""

from __future__ import annotations

from ownscribe.summarization.grounding import find_ungrounded_names


class TestFindUngroundedNames:
    def test_real_bug2_repro_flags_all_three_invented_names(self):
        transcript = "Hi everyone, thanks for joining.\nLet's review the quarterly numbers before we start."
        summary = (
            "## Action Items\n"
            "- John to update the financial forecast by next week.\n"
            "- Sarah to prepare a presentation on the new marketing strategy.\n"
            "- Mark to analyze the customer feedback and report findings.\n"
        )

        result = find_ungrounded_names(summary, transcript)

        assert "John" in result
        assert "Sarah" in result
        assert "Mark" in result

    def test_name_present_in_transcript_is_not_flagged(self):
        transcript = "Alice said we should ship the feature next week."
        summary = "## Action Items\n- Alice to ship the feature next week.\n"

        assert "Alice" not in find_ungrounded_names(summary, transcript)

    def test_case_insensitive_match_against_transcript(self):
        transcript = "we discussed the quarterly roadmap in detail."
        summary = "## Summary\nQuarterly roadmap was discussed.\n"

        assert "Quarterly" not in find_ungrounded_names(summary, transcript)

    def test_sentence_starter_words_never_flagged(self):
        transcript = "Short transcript with nothing else in it."
        summary = "## Summary\nThe meeting was brief. This covered nothing.\n"

        result = find_ungrounded_names(summary, transcript)

        assert "The" not in result
        assert "This" not in result

    def test_heading_words_never_flagged(self):
        transcript = "Short transcript."
        summary = "## Action Items\n## Decisions\n## Key Points\n"

        result = find_ungrounded_names(summary, transcript)

        assert "Action" not in result
        assert "Items" not in result
        assert "Decisions" not in result
        assert "Key" not in result
        assert "Points" not in result

    def test_none_mentioned_never_flagged(self):
        transcript = "Short transcript."
        summary = "## Action Items\nNone mentioned.\n"

        result = find_ungrounded_names(summary, transcript)

        assert "None" not in result
        assert "Mentioned" not in result

    def test_empty_summary_returns_empty(self):
        assert find_ungrounded_names("", "Some transcript text.") == []

    def test_fully_grounded_summary_returns_empty(self):
        transcript = "Bob and Carol discussed the budget on Friday."
        summary = "## Summary\nBob and Carol discussed the budget.\n"

        assert find_ungrounded_names(summary, transcript) == []

    def test_result_is_sorted(self):
        transcript = "Nothing relevant here."
        summary = "## Action Items\n- Zach to follow up.\n- Amy to review.\n"

        result = find_ungrounded_names(summary, transcript)

        assert result == sorted(result)
