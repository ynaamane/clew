"""Test that anchor contexts contain their tokens."""

from __future__ import annotations

from pathlib import Path

import pytest

from ownscribe.summarization.anchoring import anchor_summary_claims


@pytest.fixture
def real_meeting_data():
    """Load the real 27-July meeting data for verification."""
    fixture_dir = Path("/tmp/ms-fixture")
    if not fixture_dir.exists():
        pytest.skip("Real meeting fixture not available")

    summary = (fixture_dir / "summary.md").read_text()
    transcript = (fixture_dir / "transcript.md").read_text()
    return summary, transcript


def test_all_anchors_contain_their_token(real_meeting_data):
    """Every anchor's context must contain its token case-insensitively.

    This is the bar from the lead: 2 of 14 real anchors failed this test
    with the old [:100] slicing (Confluence @10:03, Lambda @05:09).
    The real 05:09 line is 113 chars with the token at ~106.
    """
    summary, transcript = real_meeting_data
    anchors = anchor_summary_claims(summary, transcript)

    missing_token = []
    for token, occurrences in anchors.items():
        for occurrence in occurrences:
            context = occurrence["context"]
            timestamp = occurrence["timestamp"]

            if token.lower() not in context.lower():
                missing_token.append(
                    {
                        "token": token,
                        "timestamp": timestamp,
                        "context": context,
                    }
                )

    assert len(missing_token) == 0, f"Found {len(missing_token)} anchors missing their token:\n" + "\n".join(
        f"  {item['token']} @{item['timestamp']}: {item['context'][:80]}..." for item in missing_token
    )


def test_context_centered_on_long_line():
    """Context window should be centered on token for lines > 100 chars."""
    from ownscribe.summarization.anchoring import _center_context_on_token

    long_line = (
        "Et sur la partie architecture, du coup, là, maintenant, "
        "j'entends une image de cœur qui se déploie sur la Lambda."
    )

    context = _center_context_on_token(long_line, "Lambda", window_size=100)

    assert "Lambda" in context, "Token must be in centered context"
    assert len(context) <= 100, "Context must not exceed window size"

    lower_context = context.lower()
    token_pos = lower_context.find("lambda")
    assert 0 <= token_pos <= 100, f"Token must be within window, found at position {token_pos}"


def test_context_centered_on_short_line():
    """Short lines should not be truncated."""
    from ownscribe.summarization.anchoring import _center_context_on_token

    short_line = "Gary discussed the bug"
    context = _center_context_on_token(short_line, "Gary", window_size=100)

    assert context == short_line, "Short lines should remain intact"
    assert "Gary" in context


def test_context_token_at_end():
    """Token at end of long line should still be included."""
    from ownscribe.summarization.anchoring import _center_context_on_token

    line_with_token_at_end = "A" * 90 + " Lambda"
    context = _center_context_on_token(line_with_token_at_end, "Lambda", window_size=100)

    assert "Lambda" in context, "Token at end must be included"
    assert len(context) <= 100


def test_context_token_at_start():
    """Token at start of long line should still be included."""
    from ownscribe.summarization.anchoring import _center_context_on_token

    line_with_token_at_start = "Lambda " + "B" * 120
    context = _center_context_on_token(line_with_token_at_start, "Lambda", window_size=100)

    assert "Lambda" in context, "Token at start must be included"
    assert len(context) <= 100
