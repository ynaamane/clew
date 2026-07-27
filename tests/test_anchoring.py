from __future__ import annotations

from ownscribe.summarization.anchoring import anchor_summary_claims


def test_rare_token_anchoring_on_english_summary_french_transcript():
    summary = """# Meeting Summary

## Key Points
- Architecture section mentioned an image of a heart expanding on Lambda and security involving JWT.
- An agent's tool sends a GWT token from the user, which is used for key extraction from project and molecule.
- A bug related to Gary was discussed and needs to be checked if fixed.
- Evaluation documentation for PPTX and Confluence was mentioned.
"""

    transcript = """
**SPEAKER_01** [05:09]
Et sur la partie architecture, du coup, là, maintenant,
j'entends une image de cœur qui se déploie sur la Lambda.
[05:28] Et devant, par la partie sécurité, c'est toujours le JWT, c'est ça ?
[05:37] Et du coup, l'agent, quand il appelle le tool, il envoie le token GWT
de l'utilisateur et après, ça exploite les mots-clés, genre le projet et la molécule.

**SPEAKER_01** [08:30]
Le bug qu'avait Gary, tu m'as dit qu'il faut voir avec lui si ça a été fixé ou pas demain, c'est ça ?

**SPEAKER_01** [10:03]
Ok, ça t'as vu, j'ai regardé les confluences, donc il y a une doc pour le PPTX,
pour l'évaluation il y a de la doc aussi sur confluence.
[13:11] Juste une question, pour revenir sur la PPTX Tool, parce que j'ai eu une question en tête.
[13:32] Tu crées un JWT temporaire et tu testes avec un script Python, comment tu fais ?
[16:06] Ça, je le récupère, je crée un token GWT effectif.
"""

    result = anchor_summary_claims(summary, transcript)

    assert "Lambda" in result
    assert len(result["Lambda"]) == 1
    assert result["Lambda"][0]["timestamp"] == "05:09"
    assert result["Lambda"][0]["context"] is not None

    assert "JWT" in result
    assert len(result["JWT"]) == 2
    timestamps = sorted([a["timestamp"] for a in result["JWT"]])
    assert timestamps == ["05:28", "13:32"]

    assert "GWT" in result
    assert len(result["GWT"]) == 2
    timestamps = sorted([a["timestamp"] for a in result["GWT"]])
    assert timestamps == ["05:37", "16:06"]

    assert "Gary" in result
    assert len(result["Gary"]) == 1
    assert result["Gary"][0]["timestamp"] == "08:30"

    assert "PPTX" in result
    assert len(result["PPTX"]) == 2
    timestamps = sorted([a["timestamp"] for a in result["PPTX"]])
    assert timestamps == ["10:03", "13:11"]

    assert "Confluence" in result
    assert len(result["Confluence"]) == 1
    assert result["Confluence"][0]["timestamp"] == "10:03"


def test_unanchored_claim_marked_as_such():
    summary = """# Meeting Summary

## Key Points
- Evaluation documentation for PPTX was mentioned.
"""

    transcript = """
**SPEAKER_01** [05:09]
Some discussion about testing.
"""

    result = anchor_summary_claims(summary, transcript)

    assert "PPTX" not in result or len(result.get("PPTX", [])) == 0


def test_french_summary_french_transcript():
    summary = """# Résumé de réunion

## Points clés
- Discussion sur Lambda et JWT pour la sécurité.
- Un bug concernant Gary a été mentionné.
"""

    transcript = """
**SPEAKER_01** [05:09]
Et sur la partie architecture, du coup, là, maintenant, j'entends une image de cœur qui se déploie sur la Lambda.
[05:28] Et devant, par la partie sécurité, c'est toujours le JWT, c'est ça ?

**SPEAKER_01** [08:30]
Le bug qu'avait Gary, tu m'as dit qu'il faut voir avec lui si ça a été fixé ou pas demain, c'est ça ?
"""

    result = anchor_summary_claims(summary, transcript)

    assert "Lambda" in result
    assert result["Lambda"][0]["timestamp"] == "05:09"

    assert "JWT" in result
    assert result["JWT"][0]["timestamp"] == "05:28"

    assert "Gary" in result
    assert result["Gary"][0]["timestamp"] == "08:30"


def test_empty_summary_returns_empty_result():
    result = anchor_summary_claims("", "some transcript")
    assert result == {}


def test_empty_transcript_returns_empty_result():
    summary = "- Discussion about Lambda."
    result = anchor_summary_claims(summary, "")
    assert result == {}


def test_case_insensitive_matching():
    summary = "- Discussion about lambda and jwt."
    transcript = """
**SPEAKER_01** [05:09]
We discussed Lambda.
[05:28] Also JWT security.
"""

    result = anchor_summary_claims(summary, transcript)

    assert "lambda" in result or "Lambda" in result
    assert "jwt" in result or "JWT" in result


def test_sentence_start_words_excluded():
    summary = """# Summary

## Key Points
- Discussion about testing revealed concerns.
- The team evaluated several approaches.
- Concerns were addressed by John.
"""

    transcript = """
**SPEAKER_01** [01:00]
Let me share some concerns about the timeline.
[02:00] John helped address those concerns.
"""

    result = anchor_summary_claims(summary, transcript)

    assert "John" in result
    assert result["John"][0]["timestamp"] == "02:00"

    assert "Discussion" not in result
    assert "The" not in result
    assert "Concerns" not in result


def test_english_transcript_no_false_positives():
    summary = """# Meeting Summary

## Key Points
- Discussion about testing revealed some concerns.
- Evaluation of the new feature is complete.
- Key decisions were made by Gary and the team.
"""

    transcript = """
**SPEAKER_01** [00:12]
We had a long discussion about the roadmap.
[01:30] My main concerns are around latency.
[02:45] The evaluation went fine, nothing blocking.
[03:15] Gary mentioned some performance issues.
"""

    result = anchor_summary_claims(summary, transcript)

    assert "Gary" in result
    assert result["Gary"][0]["timestamp"] == "03:15"

    assert "Discussion" not in result
    assert "Concerns" not in result
    assert "Evaluation" not in result
    assert "Key" not in result


def test_pipeline_integration_with_transcript_result():
    from ownscribe.transcription.models import Segment, TranscriptResult, Word
    from ownscribe.output.markdown import format_transcript

    segments = [
        Segment(
            text="Et sur la partie architecture, maintenant j'entends une image qui se déploie sur la Lambda.",
            start=309.0,
            end=320.0,
            speaker="SPEAKER_01",
            words=[
                Word(text="Et", start=309.0, end=309.1, speaker="SPEAKER_01"),
                Word(text="sur", start=309.1, end=309.2, speaker="SPEAKER_01"),
            ]
        ),
        Segment(
            text="Et devant, par la partie sécurité, c'est toujours le JWT, c'est ça ?",
            start=328.0,
            end=335.0,
            speaker="SPEAKER_01",
            words=[]
        ),
        Segment(
            text="Le bug a été signalé par Gary qui m'a dit qu'il faut voir avec lui.",
            start=510.0,
            end=518.0,
            speaker="SPEAKER_01",
            words=[]
        ),
    ]

    result = TranscriptResult(segments=segments, language="fr", duration=518.0)

    summary = """# Meeting Summary

## Key Points
- Architecture discussion mentioned Lambda deployment.
- Security uses JWT tokens.
- A bug was reported by Gary for verification.
"""

    transcript_md = format_transcript(result)

    anchors = anchor_summary_claims(summary, transcript_md)

    assert anchors is not None
    assert len(anchors) > 0, "Anchors should not be empty when using TranscriptResult through format_transcript"

    assert "Lambda" in anchors
    assert "JWT" in anchors
    assert "Gary" in anchors

    assert anchors["Lambda"][0]["timestamp"] == "05:09"
    assert anchors["JWT"][0]["timestamp"] == "05:28"
    assert anchors["Gary"][0]["timestamp"] == "08:30"

