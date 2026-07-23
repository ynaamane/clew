"""Tests for pipeline orchestration."""

from __future__ import annotations

import contextlib
import json
from unittest import mock

from ownscribe.config import Config
from ownscribe.transcription.models import Segment, TranscriptResult, Word


class TestCreateRecorder:
    def test_coreaudio_when_available(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            recorder = _create_recorder(config)
            assert recorder == mock_cls.return_value

    def test_fallback_to_sounddevice(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""

        with (
            mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_ca,
            mock.patch("ownscribe.audio.sounddevice_recorder.SoundDeviceRecorder") as mock_sd,
        ):
            mock_ca.return_value.is_available.return_value = False
            recorder = _create_recorder(config)
            assert recorder == mock_sd.return_value

    def test_sounddevice_when_device_set(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = "USB Mic"

        with mock.patch("ownscribe.audio.sounddevice_recorder.SoundDeviceRecorder") as mock_sd:
            recorder = _create_recorder(config)
            assert recorder == mock_sd.return_value

    def test_silence_timeout_passed_to_coreaudio(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""
        config.audio.silence_timeout = 120

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            mock_cls.assert_called_once_with(mic=False, mic_device="", capture_mode="all", silence_timeout=120)

    def test_capture_mode_defaults_to_all(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            mock_cls.assert_called_once_with(mic=False, mic_device="", capture_mode="all", silence_timeout=300)

    def test_capture_mode_picker_override_passed_to_coreaudio(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""
        config.audio.capture_mode = "picker"

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            mock_cls.assert_called_once_with(mic=False, mic_device="", capture_mode="picker", silence_timeout=300)

    def test_silence_timeout_passed_to_sounddevice(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "sounddevice"
        config.audio.device = "USB Mic"
        config.audio.silence_timeout = 60

        with mock.patch("ownscribe.audio.sounddevice_recorder.SoundDeviceRecorder") as mock_sd:
            _create_recorder(config)
            mock_sd.assert_called_once_with(device="USB Mic", silence_timeout=60)


class TestFormatOutput:
    def test_markdown_format(self, sample_transcript):
        from ownscribe.pipeline import _format_output

        config = Config()
        config.output.format = "markdown"

        transcript_str, summary_str = _format_output(config, sample_transcript)
        assert "# Transcript" in transcript_str
        assert summary_str is None

    def test_markdown_with_summary(self, sample_transcript):
        from ownscribe.pipeline import _format_output

        config = Config()
        config.output.format = "markdown"

        transcript_str, summary_str = _format_output(config, sample_transcript, "A great meeting.")
        assert "# Transcript" in transcript_str
        assert "# Meeting Summary" in summary_str
        assert "A great meeting." in summary_str

    def test_json_format(self, sample_transcript):
        from ownscribe.pipeline import _format_output

        config = Config()
        config.output.format = "json"

        transcript_str, _summary_str = _format_output(config, sample_transcript)
        parsed = json.loads(transcript_str)
        assert "segments" in parsed


class TestSlugify:
    def test_basic(self):
        from ownscribe.pipeline import _slugify

        assert _slugify("Q3 Budget Planning Review") == "q3-budget-planning-review"

    def test_strips_special_chars(self):
        from ownscribe.pipeline import _slugify

        assert _slugify("Hello, World! @#$") == "hello-world"

    def test_truncates_to_max_length(self):
        from ownscribe.pipeline import _slugify

        result = _slugify("a " * 100, max_length=10)
        assert len(result) <= 10

    def test_empty_input(self):
        from ownscribe.pipeline import _slugify

        assert _slugify("") == ""

    def test_colons_removed(self):
        from ownscribe.pipeline import _slugify

        assert _slugify("Meeting: Budget Review") == "meeting-budget-review"


class TestGenerateTitleSlug:
    def test_returns_slug(self):
        from ownscribe.pipeline import _generate_title_slug

        mock_summarizer = mock.MagicMock()
        mock_summarizer.generate_title.return_value = "Budget Review"

        assert _generate_title_slug("summary text", mock_summarizer) == "budget-review"

    def test_returns_empty_on_empty_slug(self):
        from ownscribe.pipeline import _generate_title_slug

        mock_summarizer = mock.MagicMock()
        mock_summarizer.generate_title.return_value = "!!!"  # slugifies to empty

        assert _generate_title_slug("summary", mock_summarizer) == ""

    def test_returns_empty_on_llm_failure(self):
        from ownscribe.pipeline import _generate_title_slug

        mock_summarizer = mock.MagicMock()
        mock_summarizer.generate_title.side_effect = Exception("LLM down")

        assert _generate_title_slug("summary", mock_summarizer) == ""


class TestDoTranscribeAndSummarize:
    """Test _do_transcribe_and_summarize with mocked transcriber/summarizer."""

    def _make_transcript(self) -> TranscriptResult:
        return TranscriptResult(
            segments=[Segment(text="Hello world.", start=0.0, end=1.5)],
            language="en",
            duration=1.5,
        )

    def test_transcribe_only(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        assert (tmp_path / "transcript.md").exists()
        assert not (tmp_path / "summary.md").exists()

    def test_transcribe_and_summarize(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.summarization.enabled = True
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.return_value = "## Summary\nGood meeting."

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=True)

        assert (tmp_path / "transcript.md").exists()
        assert (tmp_path / "summary.md").exists()
        assert "Summary" in (tmp_path / "summary.md").read_text()

    def test_summarizer_unavailable_skips_gracefully(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.summarization.enabled = True
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = False

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=True)

        assert (tmp_path / "transcript.md").exists()
        assert not (tmp_path / "summary.md").exists()

    def test_json_output_format(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "json"
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        assert (tmp_path / "transcript.json").exists()
        assert not (tmp_path / "transcript.md").exists()

    def test_keep_recording_false_deletes_wav(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.output.keep_recording = False
        audio_path = tmp_path / "recording.wav"
        audio_path.write_bytes(b"fake audio data")

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        assert (tmp_path / "transcript.md").exists()
        assert not audio_path.exists()

    def test_keep_recording_true_keeps_wav(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.output.keep_recording = True
        audio_path = tmp_path / "recording.wav"
        audio_path.write_bytes(b"fake audio data")

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        assert (tmp_path / "transcript.md").exists()
        assert audio_path.exists()

    def test_summarization_failure_preserves_transcript(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.summarization.enabled = True
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.side_effect = Exception("GPU OOM")

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=True)

        assert (tmp_path / "transcript.md").exists()
        assert "Hello world." in (tmp_path / "transcript.md").read_text()
        assert not (tmp_path / "summary.md").exists()

    def test_separate_audio_dir_renamed_alongside_out_dir(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.summarization.enabled = True
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = str(tmp_path / "audio-cache")

        out_dir = tmp_path / "notes" / "2026-01-01_1200"
        out_dir.mkdir(parents=True)
        audio_dir = tmp_path / "audio-cache" / "2026-01-01_1200"
        audio_dir.mkdir(parents=True)
        audio_path = audio_dir / "recording.wav"
        audio_path.write_bytes(b"fake audio data")

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.return_value = "## Summary\nGood meeting."
        mock_summarizer.generate_title.return_value = "Budget Review"

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            _do_transcribe_and_summarize(config, audio_path, out_dir, summarize=True)

        renamed_out_dir = out_dir.parent / "2026-01-01_1200_budget-review"
        renamed_audio_dir = audio_dir.parent / "2026-01-01_1200_budget-review"
        assert (renamed_out_dir / "transcript.md").exists()
        assert (renamed_out_dir / "summary.md").exists()
        assert (renamed_audio_dir / "recording.wav").exists()
        assert not out_dir.exists()
        assert not audio_dir.exists()

    def test_keep_recording_false_deletes_from_separate_audio_dir(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.output.keep_recording = False
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = str(tmp_path / "audio-cache")

        out_dir = tmp_path / "notes" / "2026-01-01_1200"
        out_dir.mkdir(parents=True)
        audio_dir = tmp_path / "audio-cache" / "2026-01-01_1200"
        audio_dir.mkdir(parents=True)
        audio_path = audio_dir / "recording.wav"
        audio_path.write_bytes(b"fake audio data")

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, out_dir, summarize=False)

        assert (out_dir / "transcript.md").exists()
        assert not audio_path.exists()
        assert not audio_dir.exists()

    def test_colocated_audio_follows_rename_despite_separate_audio_dir(self, tmp_path):
        """Resuming a directory that holds its own recording (made before
        audio_dir was configured) must follow out_dir's rename, not try to
        rename the audio's directory a second time."""
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.output.keep_recording = False
        config.summarization.enabled = True
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = str(tmp_path / "audio-cache")

        out_dir = tmp_path / "notes" / "2026-01-01_1200"
        out_dir.mkdir(parents=True)
        audio_path = out_dir / "recording.wav"
        audio_path.write_bytes(b"fake audio data")

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.return_value = "## Summary\nGood meeting."
        mock_summarizer.generate_title.return_value = "Budget Review"

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            _do_transcribe_and_summarize(config, audio_path, out_dir, summarize=True)

        renamed_out_dir = out_dir.parent / "2026-01-01_1200_budget-review"
        assert (renamed_out_dir / "transcript.md").exists()
        assert (renamed_out_dir / "summary.md").exists()
        assert not (renamed_out_dir / "recording.wav").exists()
        assert not out_dir.exists()


class TestFindDualTracks:
    def test_returns_none_when_neither_track_exists(self, tmp_path):
        from ownscribe.pipeline import _find_dual_tracks

        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        assert _find_dual_tracks(audio_path) is None

    def test_returns_none_when_only_system_exists(self, tmp_path):
        from ownscribe.pipeline import _find_dual_tracks

        audio_path = tmp_path / "recording.wav"
        audio_path.touch()
        (tmp_path / "system.wav").touch()

        assert _find_dual_tracks(audio_path) is None

    def test_returns_none_when_only_mic_exists(self, tmp_path):
        from ownscribe.pipeline import _find_dual_tracks

        audio_path = tmp_path / "recording.wav"
        audio_path.touch()
        (tmp_path / "mic.wav").touch()

        assert _find_dual_tracks(audio_path) is None

    def test_returns_both_paths_when_both_exist(self, tmp_path):
        from ownscribe.pipeline import _find_dual_tracks

        audio_path = tmp_path / "recording.wav"
        audio_path.touch()
        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"
        system_path.touch()
        mic_path.touch()

        result = _find_dual_tracks(audio_path)

        assert result == (system_path, mic_path)


class TestReadMicStartOffset:
    def test_reads_positive_offset_from_sidecar(self, tmp_path):
        from ownscribe.pipeline import _read_mic_start_offset

        audio_path = tmp_path / "recording.wav"
        (tmp_path / "track_alignment.json").write_text('{"mic_start_offset_seconds": 0.3}')

        assert _read_mic_start_offset(audio_path) == 0.3

    def test_reads_negative_offset_from_sidecar(self, tmp_path):
        from ownscribe.pipeline import _read_mic_start_offset

        audio_path = tmp_path / "recording.wav"
        (tmp_path / "track_alignment.json").write_text('{"mic_start_offset_seconds": -0.3}')

        assert _read_mic_start_offset(audio_path) == -0.3

    def test_returns_zero_when_sidecar_missing(self, tmp_path):
        from ownscribe.pipeline import _read_mic_start_offset

        audio_path = tmp_path / "recording.wav"

        assert _read_mic_start_offset(audio_path) == 0.0

    def test_returns_zero_when_sidecar_malformed(self, tmp_path):
        from ownscribe.pipeline import _read_mic_start_offset

        audio_path = tmp_path / "recording.wav"
        (tmp_path / "track_alignment.json").write_text("not json at all")

        assert _read_mic_start_offset(audio_path) == 0.0

    def test_returns_zero_when_key_missing(self, tmp_path):
        from ownscribe.pipeline import _read_mic_start_offset

        audio_path = tmp_path / "recording.wav"
        (tmp_path / "track_alignment.json").write_text("{}")

        assert _read_mic_start_offset(audio_path) == 0.0


class TestShiftResult:
    def test_shifts_segment_and_word_timestamps(self):
        from ownscribe.pipeline import _shift_result

        result = TranscriptResult(
            segments=[
                Segment(
                    text="hello",
                    start=1.0,
                    end=2.0,
                    words=[Word(text="hello", start=1.0, end=2.0)],
                )
            ],
            language="en",
            duration=2.0,
        )

        shifted = _shift_result(result, 0.5)

        assert shifted.segments[0].start == 1.5
        assert shifted.segments[0].end == 2.5
        assert shifted.segments[0].words[0].start == 1.5
        assert shifted.segments[0].words[0].end == 2.5

    def test_negative_offset_shifts_backward(self):
        from ownscribe.pipeline import _shift_result

        result = TranscriptResult(segments=[Segment(text="hi", start=2.0, end=3.0)])

        shifted = _shift_result(result, -0.5)

        assert shifted.segments[0].start == 1.5
        assert shifted.segments[0].end == 2.5

    def test_does_not_mutate_original(self):
        from ownscribe.pipeline import _shift_result

        original = TranscriptResult(segments=[Segment(text="hi", start=1.0, end=2.0)])

        _shift_result(original, 0.5)

        assert original.segments[0].start == 1.0


class TestTagSpeaker:
    def test_sets_speaker_on_every_segment(self):
        from ownscribe.pipeline import _tag_speaker

        result = TranscriptResult(
            segments=[
                Segment(text="a", start=0.0, end=1.0, speaker=None),
                Segment(text="b", start=1.0, end=2.0, speaker="SPEAKER_00"),
            ]
        )

        tagged = _tag_speaker(result, "Owner")

        assert all(seg.speaker == "Owner" for seg in tagged.segments)


class TestMergeDualTrackResults:
    def test_interleaves_segments_by_start_time(self):
        from ownscribe.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(
            segments=[
                Segment(text="remote says hi", start=0.0, end=1.0, speaker="SPEAKER_00"),
                Segment(text="remote continues", start=2.0, end=3.0, speaker="SPEAKER_00"),
            ],
            language="en",
            duration=3.0,
        )
        mic_result = TranscriptResult(
            segments=[Segment(text="owner replies", start=0.5, end=1.5)],
            language="en",
            duration=1.0,
        )

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset=0.0)

        texts_in_order = [seg.text for seg in merged.segments]
        assert texts_in_order == ["remote says hi", "owner replies", "remote continues"]

    def test_mic_segments_tagged_owner_and_shifted(self):
        from ownscribe.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(segments=[], language="en", duration=5.0)
        mic_result = TranscriptResult(
            segments=[Segment(text="owner speaks", start=0.0, end=1.0)],
            language="en",
            duration=1.0,
        )

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset=0.3)

        assert len(merged.segments) == 1
        assert merged.segments[0].speaker == "Owner"
        assert merged.segments[0].start == 0.3
        assert merged.segments[0].end == 1.3

    def test_system_segments_speaker_labels_untouched(self):
        from ownscribe.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(
            segments=[Segment(text="remote", start=0.0, end=1.0, speaker="SPEAKER_00")],
            language="en",
            duration=1.0,
        )
        mic_result = TranscriptResult(segments=[], language="en", duration=0.0)

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset=0.0)

        assert merged.segments[0].speaker == "SPEAKER_00"

    def test_duration_is_max_of_both_tracks_accounting_for_offset(self):
        from ownscribe.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(segments=[], language="en", duration=5.0)
        mic_result = TranscriptResult(segments=[], language="en", duration=10.0)

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset=2.0)

        assert merged.duration == 12.0


class TestTranscribeDualTrack:
    def test_diarizes_system_never_diarizes_mic(self, tmp_path):
        from ownscribe.pipeline import _transcribe_dual_track

        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.side_effect = [
            TranscriptResult(segments=[Segment(text="remote", start=0.0, end=1.0, speaker="SPEAKER_00")]),
            TranscriptResult(segments=[Segment(text="owner", start=0.0, end=1.0)]),
        ]

        _transcribe_dual_track(mock_transcriber, system_path, mic_path, mic_offset=0.0)

        calls = mock_transcriber.transcribe.call_args_list
        assert calls[0].args[0] == system_path
        assert calls[0].kwargs == {}
        assert calls[1].args[0] == mic_path
        assert calls[1].kwargs == {"diarize": False}

    def test_merges_both_transcripts_into_one_result(self, tmp_path):
        from ownscribe.pipeline import _transcribe_dual_track

        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.side_effect = [
            TranscriptResult(segments=[Segment(text="remote", start=0.0, end=1.0, speaker="SPEAKER_00")]),
            TranscriptResult(segments=[Segment(text="owner", start=0.0, end=1.0)]),
        ]

        result = _transcribe_dual_track(mock_transcriber, system_path, mic_path, mic_offset=0.0)

        assert len(result.segments) == 2
        assert {seg.speaker for seg in result.segments} == {"SPEAKER_00", "Owner"}


class TestDoTranscribeAndSummarizeDualTrack:
    def test_uses_dual_track_when_both_tracks_present(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()
        (tmp_path / "system.wav").touch()
        (tmp_path / "mic.wav").touch()
        (tmp_path / "track_alignment.json").write_text('{"mic_start_offset_seconds": 0.2}')

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.side_effect = [
            TranscriptResult(segments=[Segment(text="remote", start=0.0, end=1.0, speaker="SPEAKER_00")]),
            TranscriptResult(segments=[Segment(text="owner", start=0.0, end=1.0)]),
        ]

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        assert mock_transcriber.transcribe.call_count == 2
        transcript_text = (tmp_path / "transcript.md").read_text()
        assert "Owner" in transcript_text

    def test_falls_back_to_single_track_when_tracks_absent(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = TranscriptResult(
            segments=[Segment(text="Hello world.", start=0.0, end=1.5)],
            language="en",
            duration=1.5,
        )

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        mock_transcriber.transcribe.assert_called_once_with(audio_path)


class TestRunWarmup:
    def test_run_warmup_calls_prepare_models(self):
        from ownscribe.pipeline import run_warmup

        config = Config()
        config.transcription.language = "en"

        mock_transcriber = mock.MagicMock()

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            run_warmup(config)

        mock_transcriber.prepare_models.assert_called_once_with(language="en")

    def test_run_warmup_enables_prepare_step_in_progress(self):
        from ownscribe.pipeline import run_warmup

        config = Config()
        mock_transcriber = mock.MagicMock()
        fake_progress = mock.MagicMock()

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.PipelineProgress") as mock_progress_cls,
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            mock_progress_cls.return_value.__enter__.return_value = fake_progress
            run_warmup(config)

        _, kwargs = mock_progress_cls.call_args
        assert kwargs["include_prepare"] is True
        assert kwargs["transcribe"] is False
        assert kwargs["download_summarizer"] is True

    def test_run_warmup_downloads_summarizer_with_progress(self):
        from ownscribe.pipeline import run_warmup

        config = Config()
        config.summarization.enabled = True
        config.summarization.backend = "local"
        config.summarization.model = "phi-4-mini"

        mock_transcriber = mock.MagicMock()

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model") as mock_ensure,
        ):
            run_warmup(config)

        mock_ensure.assert_called_once()
        _, kwargs = mock_ensure.call_args
        assert kwargs.get("on_progress") is not None

    def test_run_warmup_skips_summarizer_download_when_not_local(self):
        from ownscribe.pipeline import run_warmup

        config = Config()
        config.summarization.enabled = True
        config.summarization.backend = "ollama"

        mock_transcriber = mock.MagicMock()

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model") as mock_ensure,
        ):
            run_warmup(config)

        mock_ensure.assert_not_called()


class TestRunPipelineAudioLocation:
    """Test that run_pipeline records into the configured audio_dir."""

    def _make_recorder_mock(self):
        recorder = mock.MagicMock()
        recorder.is_recording = False  # skip the recording loop immediately
        recorder.is_muted = False
        recorder.silence_timed_out = False
        recorder.silence_warning = False

        def _start(path):
            # Must exceed _WAV_HEADER_SIZE (44 bytes) or run_pipeline treats it as empty.
            path.write_bytes(b"fake audio data, definitely more than 44 bytes")

        recorder.start.side_effect = _start
        return recorder

    def test_audio_recorded_into_separate_audio_dir(self, tmp_path):
        from ownscribe.pipeline import run_pipeline

        config = Config()
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = str(tmp_path / "audio-cache")

        mock_recorder = self._make_recorder_mock()

        with (
            mock.patch("ownscribe.pipeline._create_recorder", return_value=mock_recorder),
            mock.patch("ownscribe.pipeline._do_transcribe_and_summarize") as mock_ts,
        ):
            run_pipeline(config)

        # The recorder was pointed at a file under audio_dir, not dir.
        audio_path = mock_recorder.start.call_args[0][0]
        assert audio_path.is_relative_to(tmp_path / "audio-cache")
        assert not audio_path.is_relative_to(tmp_path / "notes")
        assert audio_path.exists()

        # Downstream processing still receives the audio dir's out_dir counterpart.
        called_audio_path, called_out_dir = mock_ts.call_args[0][1], mock_ts.call_args[0][2]
        assert called_audio_path == audio_path
        assert called_out_dir.is_relative_to(tmp_path / "notes")
        assert called_out_dir.name == audio_path.parent.name

    def test_audio_recorded_into_dir_when_audio_dir_unset(self, tmp_path):
        from ownscribe.pipeline import run_pipeline

        config = Config()
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = ""

        mock_recorder = self._make_recorder_mock()

        with (
            mock.patch("ownscribe.pipeline._create_recorder", return_value=mock_recorder),
            mock.patch("ownscribe.pipeline._do_transcribe_and_summarize"),
        ):
            run_pipeline(config)

        audio_path = mock_recorder.start.call_args[0][0]
        assert audio_path.is_relative_to(tmp_path / "notes")
        assert audio_path.parent.parent == tmp_path / "notes"


class TestRunTranscribeColocation:
    """Test that run_transcribe saves output alongside the input file."""

    def test_transcript_saved_next_to_audio(self, tmp_path):
        from ownscribe.pipeline import run_transcribe

        audio_dir = tmp_path / "meetings" / "2026-01-01_1200"
        audio_dir.mkdir(parents=True)
        audio_path = audio_dir / "recording.wav"
        audio_path.touch()

        config = Config()
        config.output.format = "markdown"

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = TranscriptResult(
            segments=[Segment(text="Test.", start=0.0, end=1.0)],
            language="en",
            duration=1.0,
        )

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline._check_audio_silence"),
        ):
            run_transcribe(config, str(audio_path))

        assert (audio_dir / "transcript.md").exists()


class TestRunSummarizeColocation:
    """Test that run_summarize saves output alongside the input file."""

    def test_summary_saved_next_to_transcript(self, tmp_path):
        from ownscribe.pipeline import run_summarize

        tx_dir = tmp_path / "meetings" / "2026-01-01_1200"
        tx_dir.mkdir(parents=True)
        tx_path = tx_dir / "transcript.md"
        tx_path.write_text("# Transcript\nHello world.")

        config = Config()
        config.summarization.enabled = True

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.return_value = "## Summary\nGood meeting."
        mock_summarizer.generate_title.return_value = "test-title"

        with (
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            run_summarize(config, str(tx_path))

        renamed_dir = tx_dir.parent / f"{tx_dir.name}_test-title"
        assert (renamed_dir / "summary.md").exists()

    def test_renames_matching_audio_dir_inside_output_tree(self, tmp_path):
        from ownscribe.pipeline import run_summarize

        tx_dir = tmp_path / "notes" / "2026-01-01_1200"
        tx_dir.mkdir(parents=True)
        tx_path = tx_dir / "transcript.md"
        tx_path.write_text("# Transcript\nHello world.")

        audio_dir = tmp_path / "audio-cache" / "2026-01-01_1200"
        audio_dir.mkdir(parents=True)
        (audio_dir / "recording.wav").write_bytes(b"fake audio data")

        config = Config()
        config.summarization.enabled = True
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = str(tmp_path / "audio-cache")

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.return_value = "## Summary\nGood meeting."
        mock_summarizer.generate_title.return_value = "test-title"

        with (
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            run_summarize(config, str(tx_path))

        renamed_audio_dir = audio_dir.parent / f"{audio_dir.name}_test-title"
        assert (renamed_audio_dir / "recording.wav").exists()
        assert not audio_dir.exists()

    def test_leaves_audio_dir_alone_for_transcript_outside_output_tree(self, tmp_path):
        """A same-named directory under audio_dir must not be renamed when the
        summarized transcript does not belong to the output tree."""
        from ownscribe.pipeline import run_summarize

        tx_dir = tmp_path / "elsewhere" / "2026-01-01_1200"
        tx_dir.mkdir(parents=True)
        tx_path = tx_dir / "transcript.md"
        tx_path.write_text("# Transcript\nHello world.")

        unrelated_audio_dir = tmp_path / "audio-cache" / "2026-01-01_1200"
        unrelated_audio_dir.mkdir(parents=True)

        config = Config()
        config.summarization.enabled = True
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = str(tmp_path / "audio-cache")

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.return_value = "## Summary\nGood meeting."
        mock_summarizer.generate_title.return_value = "test-title"

        with (
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            run_summarize(config, str(tx_path))

        renamed_dir = tx_dir.parent / f"{tx_dir.name}_test-title"
        assert (renamed_dir / "summary.md").exists()
        assert unrelated_audio_dir.exists()
        assert not (unrelated_audio_dir.parent / f"{tx_dir.name}_test-title").exists()


class TestResume:
    """Test run_resume artifact detection and dispatch."""

    def test_nothing_to_resume(self, tmp_path):
        from ownscribe.pipeline import run_resume

        (tmp_path / "transcript.md").write_text("hello")
        (tmp_path / "summary.md").write_text("summary")

        config = Config()
        run_resume(config, str(tmp_path))
        # Should exit cleanly without error

    def test_error_no_audio_no_transcript(self, tmp_path):
        from ownscribe.pipeline import run_resume

        config = Config()
        with mock.patch("sys.exit", side_effect=SystemExit(1)), contextlib.suppress(SystemExit):
            run_resume(config, str(tmp_path))

    def test_resumes_summarize_only(self, tmp_path):
        from ownscribe.pipeline import run_resume

        (tmp_path / "transcript.md").write_text("# Transcript\nHello.")

        config = Config()
        config.summarization.enabled = True

        with mock.patch("ownscribe.pipeline.run_summarize") as mock_sum:
            run_resume(config, str(tmp_path))
            mock_sum.assert_called_once_with(config, str(tmp_path / "transcript.md"))

    def test_resumes_transcribe_and_summarize(self, tmp_path):
        from ownscribe.pipeline import run_resume

        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        config = Config()

        with mock.patch("ownscribe.pipeline._do_transcribe_and_summarize") as mock_ts:
            run_resume(config, str(tmp_path))
            mock_ts.assert_called_once_with(config, audio_path, tmp_path)

    def test_finds_non_wav_audio(self, tmp_path):
        from ownscribe.pipeline import run_resume

        audio_path = tmp_path / "meeting.mp3"
        audio_path.touch()

        config = Config()

        with mock.patch("ownscribe.pipeline._do_transcribe_and_summarize") as mock_ts:
            run_resume(config, str(tmp_path))
            mock_ts.assert_called_once_with(config, audio_path, tmp_path)

    def test_finds_audio_in_separate_audio_dir(self, tmp_path):
        from ownscribe.pipeline import run_resume

        text_dir = tmp_path / "notes" / "2026-01-01_1200"
        text_dir.mkdir(parents=True)
        audio_dir = tmp_path / "audio-cache" / "2026-01-01_1200"
        audio_dir.mkdir(parents=True)
        audio_path = audio_dir / "recording.wav"
        audio_path.touch()

        config = Config()
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = str(tmp_path / "audio-cache")

        with mock.patch("ownscribe.pipeline._do_transcribe_and_summarize") as mock_ts:
            run_resume(config, str(text_dir))
            mock_ts.assert_called_once_with(config, audio_path, text_dir)

    def test_finds_json_transcript(self, tmp_path):
        from ownscribe.pipeline import run_resume

        (tmp_path / "transcript.json").write_text('{"segments": []}')

        config = Config()

        with mock.patch("ownscribe.pipeline.run_summarize") as mock_sum:
            run_resume(config, str(tmp_path))
            mock_sum.assert_called_once_with(config, str(tmp_path / "transcript.json"))
