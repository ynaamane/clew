"""Tests for pipeline orchestration."""

from __future__ import annotations

import contextlib
import json
from unittest import mock

import pytest

from ownscribe.config import Config
from ownscribe.transcription.models import Segment, TranscriptResult, Word


def _write_wav(path, samples, sample_rate=16000):
    import numpy as np
    import soundfile as sf

    sf.write(str(path), np.asarray(samples, dtype="float32"), sample_rate)


def _silent_samples(n=16000):
    import numpy as np

    return np.zeros(n, dtype="float32")


def _loud_samples(n=16000):
    import numpy as np

    return (np.sin(np.linspace(0, 100 * np.pi, n)) * 0.1).astype("float32")


class TestTrackRms:
    def test_silent_track_has_near_zero_rms(self, tmp_path):
        from ownscribe.pipeline import _track_rms

        path = tmp_path / "silent.wav"
        _write_wav(path, _silent_samples())

        assert _track_rms(path) == 0.0

    def test_loud_track_has_nonzero_rms(self, tmp_path):
        from ownscribe.pipeline import _track_rms

        path = tmp_path / "loud.wav"
        _write_wav(path, _loud_samples())

        rms = _track_rms(path)
        assert rms is not None
        assert rms > 1e-3

    def test_missing_file_returns_none(self, tmp_path):
        from ownscribe.pipeline import _track_rms

        assert _track_rms(tmp_path / "does-not-exist.wav") is None


class TestCheckDualTrackSilence:
    def test_both_loud_no_warning(self, tmp_path, capsys):
        from ownscribe.pipeline import _check_dual_track_silence

        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"
        _write_wav(system_path, _loud_samples())
        _write_wav(mic_path, _loud_samples())

        _check_dual_track_silence(system_path, mic_path)

        captured = capsys.readouterr()
        assert "Warning" not in captured.err

    def test_system_silent_mic_loud_warns_system_specifically(self, tmp_path, capsys):
        from ownscribe.pipeline import _check_dual_track_silence

        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"
        _write_wav(system_path, _silent_samples())
        _write_wav(mic_path, _loud_samples())

        _check_dual_track_silence(system_path, mic_path)

        captured = capsys.readouterr()
        assert "System audio track is silent" in captured.err
        assert "Microphone track is silent" not in captured.err

    def test_mic_silent_system_loud_warns_mic_specifically(self, tmp_path, capsys):
        from ownscribe.pipeline import _check_dual_track_silence

        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"
        _write_wav(system_path, _loud_samples())
        _write_wav(mic_path, _silent_samples())

        _check_dual_track_silence(system_path, mic_path)

        captured = capsys.readouterr()
        assert "Microphone track is silent" in captured.err
        assert "System audio track is silent" not in captured.err

    def test_both_silent_warns_both(self, tmp_path, capsys):
        from ownscribe.pipeline import _check_dual_track_silence

        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"
        _write_wav(system_path, _silent_samples())
        _write_wav(mic_path, _silent_samples())

        _check_dual_track_silence(system_path, mic_path)

        captured = capsys.readouterr()
        assert "Both system audio and microphone" in captured.err

    def test_never_raises_systemexit(self, tmp_path):
        from ownscribe.pipeline import _check_dual_track_silence

        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"
        _write_wav(system_path, _silent_samples())
        _write_wav(mic_path, _silent_samples())

        _check_dual_track_silence(system_path, mic_path)


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
            mock_cls.assert_called_once_with(
                mic=False, mic_device="", capture_mode="all", silence_timeout=120,
                capture_backend="coreaudio", echo_cancellation="off"
            )

    def test_capture_mode_defaults_to_all(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            mock_cls.assert_called_once_with(
                mic=False, mic_device="", capture_mode="all", silence_timeout=300,
                capture_backend="coreaudio", echo_cancellation="off"
            )

    def test_capture_mode_picker_override_passed_to_coreaudio(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""
        config.audio.capture_mode = "picker"

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            mock_cls.assert_called_once_with(
                mic=False, mic_device="", capture_mode="picker", silence_timeout=300,
                capture_backend="coreaudio", echo_cancellation="off"
            )

    def test_capture_backend_defaults_to_coreaudio_tap(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            assert mock_cls.call_args.kwargs["capture_backend"] == "coreaudio"

    def test_capture_backend_screencapturekit_override_passed_through(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""
        config.audio.capture_backend = "screencapturekit"

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            assert mock_cls.call_args.kwargs["capture_backend"] == "screencapturekit"

    def test_echo_cancellation_defaults_to_off(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            assert mock_cls.call_args.kwargs["echo_cancellation"] == "off"

    def test_echo_cancellation_override_passed_through(self):
        from ownscribe.pipeline import _create_recorder

        config = Config()
        config.audio.backend = "coreaudio"
        config.audio.device = ""
        config.audio.echo_cancellation = "auto"

        with mock.patch("ownscribe.audio.coreaudio.CoreAudioRecorder") as mock_cls:
            mock_cls.return_value.is_available.return_value = True
            _create_recorder(config)
            assert mock_cls.call_args.kwargs["echo_cancellation"] == "auto"

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


class TestProgressClass:
    def test_defaults_to_pipeline_progress(self):
        from ownscribe.pipeline import _progress_class
        from ownscribe.progress import PipelineProgress

        config = Config()
        assert _progress_class(config) is PipelineProgress

    def test_json_mode_selects_json_progress(self):
        from ownscribe.pipeline import _progress_class
        from ownscribe.progress import JsonProgress

        config = Config()
        config.progress_mode = "json"
        assert _progress_class(config) is JsonProgress

    def test_unknown_mode_falls_back_to_pipeline_progress(self):
        from ownscribe.pipeline import _progress_class
        from ownscribe.progress import PipelineProgress

        config = Config()
        config.progress_mode = "something-else"
        assert _progress_class(config) is PipelineProgress


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


class TestRenameOutputDir:
    def test_renames_when_target_does_not_exist(self, tmp_path):
        from ownscribe.pipeline import _rename_output_dir

        source = tmp_path / "2026-01-01_1200"
        source.mkdir()
        (source / "transcript.md").write_text("hi")

        result = _rename_output_dir(source, "budget-review")

        expected = tmp_path / "2026-01-01_1200_budget-review"
        assert result == expected
        assert expected.exists()
        assert not source.exists()

    def test_skips_cleanly_when_target_exists_with_content(self, tmp_path):
        from ownscribe.pipeline import _rename_output_dir

        source = tmp_path / "2026-01-01_1200"
        source.mkdir()
        (source / "transcript.md").write_text("hi")

        target = tmp_path / "2026-01-01_1200_budget-review"
        target.mkdir()
        (target / "unrelated.txt").write_text("already here")

        result = _rename_output_dir(source, "budget-review")

        assert result == source
        assert source.exists()
        assert (target / "unrelated.txt").read_text() == "already here"

    def test_renames_when_target_exists_but_is_empty(self, tmp_path):
        from ownscribe.pipeline import _rename_output_dir

        source = tmp_path / "2026-01-01_1200"
        source.mkdir()
        (source / "transcript.md").write_text("hi")

        target = tmp_path / "2026-01-01_1200_budget-review"
        target.mkdir()

        result = _rename_output_dir(source, "budget-review")

        assert result == target
        assert (target / "transcript.md").read_text() == "hi"

    def test_returns_original_on_unexpected_os_error(self, tmp_path):
        from pathlib import Path

        from ownscribe.pipeline import _rename_output_dir

        source = tmp_path / "2026-01-01_1200"
        source.mkdir()

        with mock.patch.object(Path, "rename", side_effect=OSError("cross-device link")):
            result = _rename_output_dir(source, "budget-review")

        assert result == source
        assert source.exists()


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

    def test_summary_with_invented_name_triggers_grounding_warning(self, tmp_path, capsys):
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
        mock_summarizer.summarize.return_value = "## Action Items\n- Zephyr to follow up.\n"

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=True)

        captured = capsys.readouterr()
        assert "Zephyr" in captured.err
        assert "not found in the transcript" in captured.err

    def test_summary_fully_grounded_in_transcript_has_no_warning(self, tmp_path, capsys):
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
        mock_summarizer.summarize.return_value = "## Summary\nHello world was discussed."

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=True)

        captured = capsys.readouterr()
        assert "not found in the transcript" not in captured.err

    def test_json_progress_mode_emits_ndjson_events_on_stderr(self, tmp_path, capsys):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.summarization.enabled = True
        config.progress_mode = "json"
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.return_value = "## Summary\nHello world was discussed."

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=True)

        captured = capsys.readouterr()
        json_lines = [line for line in captured.err.splitlines() if line.startswith("{")]
        events = [json.loads(line) for line in json_lines]

        assert any(e == {"event": "begin", "step": "summarizing"} for e in events)
        assert any(e == {"event": "complete", "step": "summarizing"} for e in events)

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

    def test_keep_recording_false_also_deletes_dual_tracks_and_sidecar(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.output.keep_recording = False
        audio_path = tmp_path / "recording.wav"
        audio_path.write_bytes(b"fake audio data")
        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"
        sidecar_path = tmp_path / "track_alignment.json"
        system_path.write_bytes(b"fake system audio")
        mic_path.write_bytes(b"fake mic audio")
        sidecar_path.write_text('{"mic_start_offset_seconds": 0.0}')

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        assert not audio_path.exists()
        assert not system_path.exists()
        assert not mic_path.exists()
        assert not sidecar_path.exists()

    def test_keep_recording_true_keeps_dual_tracks_too(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.output.format = "markdown"
        config.output.keep_recording = True
        audio_path = tmp_path / "recording.wav"
        audio_path.write_bytes(b"fake audio data")
        system_path = tmp_path / "system.wav"
        mic_path = tmp_path / "mic.wav"
        system_path.write_bytes(b"fake system audio")
        mic_path.write_bytes(b"fake mic audio")

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        assert audio_path.exists()
        assert system_path.exists()
        assert mic_path.exists()

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


class TestCorrectionIntegration:
    def _make_transcript(self) -> TranscriptResult:
        return TranscriptResult(
            segments=[Segment(text="Bonjur tout le monde.", start=0.0, end=1.5)],
            language="fr",
            duration=1.5,
        )

    def test_correction_disabled_leaves_transcript_untouched(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.correction.enabled = False
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        with mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        transcript_text = (tmp_path / "transcript.md").read_text()
        assert "Bonjur tout le monde." in transcript_text

    def test_correction_enabled_applies_fix(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.correction.enabled = True
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.chat.return_value = "Bonjour tout le monde."

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        transcript_text = (tmp_path / "transcript.md").read_text()
        assert "Bonjour tout le monde." in transcript_text
        assert "Bonjur" not in transcript_text

    def test_correction_enabled_creates_summarizer_even_without_summarize(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.correction.enabled = True
        config.summarization.enabled = False
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.chat.return_value = "Bonjour tout le monde."

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer) as mock_create,
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=True)

        mock_create.assert_called_once()
        mock_summarizer.close.assert_called_once()
        assert not (tmp_path / "summary.md").exists()

    def test_correction_and_summarization_share_one_summarizer_instance(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.correction.enabled = True
        config.summarization.enabled = True
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.chat.return_value = "Bonjour tout le monde."
        mock_summarizer.summarize.return_value = "A greeting."

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer) as mock_create,
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=True)

        mock_create.assert_called_once()

    def test_correction_backend_unavailable_skips_gracefully(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.correction.enabled = True
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
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        transcript_text = (tmp_path / "transcript.md").read_text()
        assert "Bonjur tout le monde." in transcript_text

    def test_correction_exception_falls_back_to_uncorrected_transcript(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.correction.enabled = True
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.chat.side_effect = RuntimeError("boom")

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        transcript_text = (tmp_path / "transcript.md").read_text()
        assert "Bonjur tout le monde." in transcript_text

    def test_hallucinated_correction_rejected_transcript_unchanged(self, tmp_path):
        from ownscribe.pipeline import _do_transcribe_and_summarize

        config = Config()
        config.correction.enabled = True
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = self._make_transcript()

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.chat.return_value = (
            "This is a wildly different unrelated hallucinated response that should be rejected"
        )

        with (
            mock.patch("ownscribe.pipeline._create_transcriber", return_value=mock_transcriber),
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
        ):
            _do_transcribe_and_summarize(config, audio_path, tmp_path, summarize=False)

        transcript_text = (tmp_path / "transcript.md").read_text()
        assert "Bonjur tout le monde." in transcript_text


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

    def test_negative_offset_shifts_system_forward_not_mic_backward(self):
        """mic_offset < 0 means mic started BEFORE system (BUG3: shifting mic backward by
        a negative amount pushed its early segments to negative timestamps, which
        _format_time then rendered as a bogus HH:MM like [59:51])."""
        from ownscribe.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(
            segments=[Segment(text="remote", start=0.0, end=1.0, speaker="SPEAKER_00")],
            language="en",
            duration=1.0,
        )
        mic_result = TranscriptResult(
            segments=[Segment(text="owner speaks first", start=0.0, end=1.0)],
            language="en",
            duration=1.0,
        )

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset=-0.3)

        assert all(seg.start >= 0.0 for seg in merged.segments)
        mic_seg = next(seg for seg in merged.segments if seg.speaker == "Owner")
        system_seg = next(seg for seg in merged.segments if seg.speaker == "SPEAKER_00")
        assert mic_seg.start == 0.0
        assert system_seg.start == 0.3

    def test_negative_offset_preserves_chronological_order(self):
        from ownscribe.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(
            segments=[Segment(text="remote later", start=0.0, end=1.0, speaker="SPEAKER_00")],
            language="en",
            duration=1.0,
        )
        mic_result = TranscriptResult(
            segments=[Segment(text="owner earlier", start=0.0, end=1.0)],
            language="en",
            duration=1.0,
        )

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset=-0.3)

        assert [seg.text for seg in merged.segments] == ["owner earlier", "remote later"]

    def test_negative_offset_duration_accounts_for_shifted_system(self):
        from ownscribe.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(segments=[], language="en", duration=5.0)
        mic_result = TranscriptResult(segments=[], language="en", duration=10.0)

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset=-2.0)

        assert merged.duration == 10.0

    def test_real_world_repro_offset_produces_chronological_non_negative_timeline(self):
        """Pins the exact BUG3 repro values (mic started ~28.28s before system;
        ~/ownscribe/2026-07-24_1756_emerging-internet-force-impact/track_alignment.json)."""
        from ownscribe.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(
            segments=[
                Segment(text="video content", start=1.659, end=9.956, speaker="SPEAKER_00"),
            ],
            language="fr",
            duration=10.979,
        )
        mic_result = TranscriptResult(
            segments=[Segment(text="Oui, ca a rate.", start=18.980, end=29.926)],
            language="fr",
            duration=39.271,
        )

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset=-28.277794125)

        assert all(seg.start >= 0.0 for seg in merged.segments)
        assert [seg.text for seg in merged.segments] == ["Oui, ca a rate.", "video content"]


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


class TestRelabelSpeakersWithVoiceprints:
    def test_relabels_matching_cluster(self, tmp_path):
        from ownscribe.pipeline import _relabel_speakers_with_voiceprints
        from ownscribe.speakers.base import VoiceprintDB

        db_path = tmp_path / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.save(db_path)

        result = TranscriptResult(
            segments=[Segment(text="hi", start=0.0, end=1.0, speaker="SPEAKER_00")]
        )

        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            relabeled = _relabel_speakers_with_voiceprints(
                result, {"SPEAKER_00": [0.99, 0.01, 0.0]}
            )

        assert relabeled.segments[0].speaker == "Alice"

    def test_unmatched_cluster_gets_unknown_label(self, tmp_path):
        from ownscribe.pipeline import _relabel_speakers_with_voiceprints
        from ownscribe.speakers.base import VoiceprintDB

        db_path = tmp_path / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.save(db_path)

        result = TranscriptResult(
            segments=[Segment(text="hi", start=0.0, end=1.0, speaker="SPEAKER_00")]
        )

        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            relabeled = _relabel_speakers_with_voiceprints(
                result, {"SPEAKER_00": [0.0, 0.0, 1.0]}
            )

        assert relabeled.segments[0].speaker == "Unknown-1"

    def test_no_embeddings_returns_result_unchanged(self, tmp_path):
        from ownscribe.pipeline import _relabel_speakers_with_voiceprints

        result = TranscriptResult(
            segments=[Segment(text="hi", start=0.0, end=1.0, speaker="SPEAKER_00")]
        )

        relabeled = _relabel_speakers_with_voiceprints(result, {})

        assert relabeled.segments[0].speaker == "SPEAKER_00"

    def test_no_enrolled_voiceprints_returns_result_unchanged(self, tmp_path):
        from ownscribe.pipeline import _relabel_speakers_with_voiceprints

        db_path = tmp_path / "voiceprints.json"

        result = TranscriptResult(
            segments=[Segment(text="hi", start=0.0, end=1.0, speaker="SPEAKER_00")]
        )

        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            relabeled = _relabel_speakers_with_voiceprints(
                result, {"SPEAKER_00": [0.99, 0.01, 0.0]}
            )

        assert relabeled.segments[0].speaker == "SPEAKER_00"

    def test_non_dict_embeddings_returns_result_unchanged(self, tmp_path):
        from ownscribe.pipeline import _relabel_speakers_with_voiceprints

        result = TranscriptResult(
            segments=[Segment(text="hi", start=0.0, end=1.0, speaker="SPEAKER_00")]
        )

        relabeled = _relabel_speakers_with_voiceprints(result, mock.MagicMock())

        assert relabeled.segments[0].speaker == "SPEAKER_00"

    def test_segments_without_speaker_are_untouched(self, tmp_path):
        from ownscribe.pipeline import _relabel_speakers_with_voiceprints
        from ownscribe.speakers.base import VoiceprintDB

        db_path = tmp_path / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.save(db_path)

        result = TranscriptResult(segments=[Segment(text="hi", start=0.0, end=1.0, speaker=None)])

        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            relabeled = _relabel_speakers_with_voiceprints(
                result, {"SPEAKER_00": [0.99, 0.01, 0.0]}
            )

        assert relabeled.segments[0].speaker is None


class TestTranscribeAndIdentify:
    def test_relabels_using_transcriber_captured_embeddings(self, tmp_path):
        from ownscribe.pipeline import _transcribe_and_identify
        from ownscribe.speakers.base import VoiceprintDB

        db_path = tmp_path / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.save(db_path)

        audio_path = tmp_path / "system.wav"

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = TranscriptResult(
            segments=[Segment(text="hi", start=0.0, end=1.0, speaker="SPEAKER_00")]
        )
        mock_transcriber.last_speaker_embeddings = {"SPEAKER_00": [0.99, 0.01, 0.0]}

        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            result = _transcribe_and_identify(mock_transcriber, audio_path)

        mock_transcriber.transcribe.assert_called_once_with(audio_path)
        assert result.segments[0].speaker == "Alice"

    def test_no_enrollment_db_leaves_diarized_labels_as_is(self, tmp_path):
        from ownscribe.pipeline import _transcribe_and_identify

        audio_path = tmp_path / "system.wav"

        mock_transcriber = mock.MagicMock()
        mock_transcriber.transcribe.return_value = TranscriptResult(
            segments=[Segment(text="hi", start=0.0, end=1.0, speaker="SPEAKER_00")]
        )
        mock_transcriber.last_speaker_embeddings = {"SPEAKER_00": [0.99, 0.01, 0.0]}

        db_path = tmp_path / "voiceprints.json"
        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            result = _transcribe_and_identify(mock_transcriber, audio_path)

        assert result.segments[0].speaker == "SPEAKER_00"


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


class TestRunWatch:
    def _make_fake_process(self, lines, returncode=0):
        process = mock.MagicMock()
        process.stdout = iter(lines)
        process.poll.return_value = returncode
        process.wait.return_value = returncode
        return process

    def test_errors_when_binary_not_found(self):
        from ownscribe.pipeline import run_watch

        config = Config()

        with (
            mock.patch("ownscribe.audio.coreaudio._find_binary", return_value=None),
            pytest.raises(SystemExit),
        ):
            run_watch(config, sustained_seconds=3.0)

    def test_starts_recording_on_detection(self, tmp_path):
        from ownscribe.pipeline import run_watch

        config = Config()
        binary_path = tmp_path / "ownscribe-audio"
        binary_path.touch()

        fake_process = self._make_fake_process(["[MEETING_DETECTED]\n"])

        with (
            mock.patch("ownscribe.audio.coreaudio._find_binary", return_value=binary_path),
            mock.patch("subprocess.Popen", return_value=fake_process),
            mock.patch("ownscribe.pipeline.run_pipeline") as mock_run_pipeline,
        ):
            run_watch(config, sustained_seconds=3.0)

        mock_run_pipeline.assert_called_once_with(config)

    def test_passes_sustained_seconds_to_subprocess(self, tmp_path):
        from ownscribe.pipeline import run_watch

        config = Config()
        binary_path = tmp_path / "ownscribe-audio"
        binary_path.touch()

        fake_process = self._make_fake_process(["[MEETING_DETECTED]\n"])

        with (
            mock.patch("ownscribe.audio.coreaudio._find_binary", return_value=binary_path),
            mock.patch("subprocess.Popen", return_value=fake_process) as mock_popen,
            mock.patch("ownscribe.pipeline.run_pipeline"),
        ):
            run_watch(config, sustained_seconds=5.0)

        called_args = mock_popen.call_args[0][0]
        assert str(binary_path) in called_args
        assert "watch-activity" in called_args
        assert "--sustained-seconds" in called_args
        assert "5.0" in called_args

    def test_process_exit_without_detection_does_not_start_recording(self, tmp_path):
        from ownscribe.pipeline import run_watch

        config = Config()
        binary_path = tmp_path / "ownscribe-audio"
        binary_path.touch()

        fake_process = self._make_fake_process([])

        with (
            mock.patch("ownscribe.audio.coreaudio._find_binary", return_value=binary_path),
            mock.patch("subprocess.Popen", return_value=fake_process),
            mock.patch("ownscribe.pipeline.run_pipeline") as mock_run_pipeline,
            pytest.raises(SystemExit),
        ):
            run_watch(config, sustained_seconds=3.0)

        mock_run_pipeline.assert_not_called()

    def test_ignores_unrelated_stdout_lines_before_detection(self, tmp_path):
        from ownscribe.pipeline import run_watch

        config = Config()
        binary_path = tmp_path / "ownscribe-audio"
        binary_path.touch()

        fake_process = self._make_fake_process(
            ["some noise\n", "\n", "[MEETING_DETECTED]\n"]
        )

        with (
            mock.patch("ownscribe.audio.coreaudio._find_binary", return_value=binary_path),
            mock.patch("subprocess.Popen", return_value=fake_process),
            mock.patch("ownscribe.pipeline.run_pipeline") as mock_run_pipeline,
        ):
            run_watch(config, sustained_seconds=3.0)

        mock_run_pipeline.assert_called_once_with(config)


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

    def test_dual_track_silence_check_runs_when_tracks_present(self, tmp_path, capsys):
        from ownscribe.pipeline import run_pipeline

        config = Config()
        config.output.dir = str(tmp_path / "notes")

        recorder = mock.MagicMock()
        recorder.is_recording = False
        recorder.is_muted = False
        recorder.silence_timed_out = False
        recorder.silence_warning = False

        def _start(path):
            path.write_bytes(b"fake audio data, definitely more than 44 bytes")
            _write_wav(path.parent / "system.wav", _silent_samples())
            _write_wav(path.parent / "mic.wav", _loud_samples())

        recorder.start.side_effect = _start

        with (
            mock.patch("ownscribe.pipeline._create_recorder", return_value=recorder),
            mock.patch("ownscribe.pipeline._do_transcribe_and_summarize"),
        ):
            run_pipeline(config)

        captured = capsys.readouterr()
        assert "System audio track is silent" in captured.err

    def test_single_track_silence_check_runs_when_no_dual_tracks(self, tmp_path):
        from ownscribe.pipeline import run_pipeline

        config = Config()
        config.output.dir = str(tmp_path / "notes")

        mock_recorder = self._make_recorder_mock()

        with (
            mock.patch("ownscribe.pipeline._create_recorder", return_value=mock_recorder),
            mock.patch("ownscribe.pipeline._do_transcribe_and_summarize"),
            mock.patch("ownscribe.pipeline._check_audio_silence") as mock_check,
        ):
            run_pipeline(config)

        mock_check.assert_called_once()


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

    def test_summary_with_invented_name_triggers_grounding_warning(self, tmp_path, capsys):
        from ownscribe.pipeline import run_summarize

        tx_dir = tmp_path / "meetings" / "2026-01-01_1200"
        tx_dir.mkdir(parents=True)
        tx_path = tx_dir / "transcript.md"
        tx_path.write_text("# Transcript\nHello world.")

        config = Config()
        config.summarization.enabled = True

        mock_summarizer = mock.MagicMock()
        mock_summarizer.is_available.return_value = True
        mock_summarizer.summarize.return_value = "## Action Items\n- Zephyr to follow up.\n"
        mock_summarizer.generate_title.return_value = "test-title"

        with (
            mock.patch("ownscribe.pipeline.create_summarizer", return_value=mock_summarizer),
            mock.patch("ownscribe.summarization.llama_cpp_summarizer._ensure_model"),
        ):
            run_summarize(config, str(tx_path))

        captured = capsys.readouterr()
        assert "Zephyr" in captured.err
        assert "not found in the transcript" in captured.err

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


class TestReprocess:
    """Test run_reprocess forced re-transcription from retained audio."""

    def test_errors_when_directory_does_not_exist(self, tmp_path):
        from ownscribe.pipeline import run_reprocess

        config = Config()
        missing = tmp_path / "does-not-exist"

        with pytest.raises(SystemExit):
            run_reprocess(config, str(missing))

    def test_errors_when_no_audio_retained(self, tmp_path):
        from ownscribe.pipeline import run_reprocess

        (tmp_path / "transcript.md").write_text("# Transcript\nHello.")
        (tmp_path / "summary.md").write_text("# Summary")

        config = Config()

        with pytest.raises(SystemExit):
            run_reprocess(config, str(tmp_path))

    def test_forces_reprocess_even_when_transcript_and_summary_exist(self, tmp_path):
        from ownscribe.pipeline import run_reprocess

        audio_path = tmp_path / "recording.wav"
        audio_path.touch()
        (tmp_path / "transcript.md").write_text("# Transcript\nOld.")
        (tmp_path / "summary.md").write_text("# Summary\nOld.")

        config = Config()

        with mock.patch("ownscribe.pipeline._do_transcribe_and_summarize") as mock_ts:
            run_reprocess(config, str(tmp_path))
            mock_ts.assert_called_once_with(config, audio_path, tmp_path)

    def test_deletes_stale_transcript_and_summary_before_reprocessing(self, tmp_path):
        from ownscribe.pipeline import run_reprocess

        audio_path = tmp_path / "recording.wav"
        audio_path.touch()
        transcript_path = tmp_path / "transcript.md"
        summary_path = tmp_path / "summary.md"
        transcript_path.write_text("# Transcript\nOld.")
        summary_path.write_text("# Summary\nOld.")

        config = Config()

        with mock.patch("ownscribe.pipeline._do_transcribe_and_summarize"):
            run_reprocess(config, str(tmp_path))

        assert not transcript_path.exists()
        assert not summary_path.exists()

    def test_finds_dual_track_audio_in_separate_audio_dir(self, tmp_path):
        from ownscribe.pipeline import run_reprocess

        text_dir = tmp_path / "notes" / "2026-01-01_1200"
        text_dir.mkdir(parents=True)
        audio_dir = tmp_path / "audio-cache" / "2026-01-01_1200"
        audio_dir.mkdir(parents=True)
        audio_path = audio_dir / "recording.wav"
        audio_path.touch()
        (audio_dir / "system.wav").touch()
        (audio_dir / "mic.wav").touch()

        config = Config()
        config.output.dir = str(tmp_path / "notes")
        config.output.audio_dir = str(tmp_path / "audio-cache")

        with mock.patch("ownscribe.pipeline._do_transcribe_and_summarize") as mock_ts:
            run_reprocess(config, str(text_dir))
            mock_ts.assert_called_once_with(config, audio_path, text_dir)

    def test_finds_non_wav_audio(self, tmp_path):
        from ownscribe.pipeline import run_reprocess

        audio_path = tmp_path / "meeting.mp3"
        audio_path.touch()

        config = Config()

        with mock.patch("ownscribe.pipeline._do_transcribe_and_summarize") as mock_ts:
            run_reprocess(config, str(tmp_path))
            mock_ts.assert_called_once_with(config, audio_path, tmp_path)


class TestRunPurge:
    """Test run_purge's retention policy: keep-forever, keep-N-days, and --all."""

    def _age_file(self, path, days):
        import os
        import time

        past = time.time() - (days * 86400)
        os.utime(path, (past, past))

    def test_keep_forever_default_without_all_is_a_noop(self, tmp_path):
        from ownscribe.pipeline import run_purge

        meeting_dir = tmp_path / "2026-01-01_1200"
        meeting_dir.mkdir()
        audio_path = meeting_dir / "recording.wav"
        audio_path.write_bytes(b"fake audio")
        self._age_file(audio_path, days=9999)

        config = Config()
        config.output.dir = str(tmp_path)

        run_purge(config, older_than_days=None, purge_all=False, dry_run=False)

        assert audio_path.exists()

    def test_all_purges_regardless_of_age(self, tmp_path):
        from ownscribe.pipeline import run_purge

        meeting_dir = tmp_path / "2026-01-01_1200"
        meeting_dir.mkdir()
        audio_path = meeting_dir / "recording.wav"
        audio_path.write_bytes(b"fake audio")

        config = Config()
        config.output.dir = str(tmp_path)

        run_purge(config, older_than_days=None, purge_all=True, dry_run=False)

        assert not audio_path.exists()

    def test_all_also_deletes_dual_tracks(self, tmp_path):
        from ownscribe.pipeline import run_purge

        meeting_dir = tmp_path / "2026-01-01_1200"
        meeting_dir.mkdir()
        audio_path = meeting_dir / "recording.wav"
        system_path = meeting_dir / "system.wav"
        mic_path = meeting_dir / "mic.wav"
        audio_path.write_bytes(b"fake audio")
        system_path.write_bytes(b"fake system")
        mic_path.write_bytes(b"fake mic")

        config = Config()
        config.output.dir = str(tmp_path)

        run_purge(config, older_than_days=None, purge_all=True, dry_run=False)

        assert not audio_path.exists()
        assert not system_path.exists()
        assert not mic_path.exists()

    def test_older_than_days_only_purges_aged_recordings(self, tmp_path):
        from ownscribe.pipeline import run_purge

        old_dir = tmp_path / "2020-01-01_1200"
        old_dir.mkdir()
        old_audio = old_dir / "recording.wav"
        old_audio.write_bytes(b"old")
        self._age_file(old_audio, days=60)

        recent_dir = tmp_path / "2026-07-01_1200"
        recent_dir.mkdir()
        recent_audio = recent_dir / "recording.wav"
        recent_audio.write_bytes(b"recent")

        config = Config()
        config.output.dir = str(tmp_path)

        run_purge(config, older_than_days=30, purge_all=False, dry_run=False)

        assert not old_audio.exists()
        assert recent_audio.exists()

    def test_older_than_flag_overrides_config_retention_days(self, tmp_path):
        from ownscribe.pipeline import run_purge

        meeting_dir = tmp_path / "2026-01-01_1200"
        meeting_dir.mkdir()
        audio_path = meeting_dir / "recording.wav"
        audio_path.write_bytes(b"fake audio")
        self._age_file(audio_path, days=10)

        config = Config()
        config.output.dir = str(tmp_path)
        config.output.retention_days = 0

        run_purge(config, older_than_days=5, purge_all=False, dry_run=False)

        assert not audio_path.exists()

    def test_dry_run_does_not_delete(self, tmp_path):
        from ownscribe.pipeline import run_purge

        meeting_dir = tmp_path / "2026-01-01_1200"
        meeting_dir.mkdir()
        audio_path = meeting_dir / "recording.wav"
        audio_path.write_bytes(b"fake audio")

        config = Config()
        config.output.dir = str(tmp_path)

        run_purge(config, older_than_days=None, purge_all=True, dry_run=True)

        assert audio_path.exists()

    def test_directories_without_audio_are_skipped_not_errored(self, tmp_path):
        from ownscribe.pipeline import run_purge

        empty_dir = tmp_path / "2026-01-01_1200"
        empty_dir.mkdir()
        (empty_dir / "transcript.md").write_text("hello")

        config = Config()
        config.output.dir = str(tmp_path)

        run_purge(config, older_than_days=None, purge_all=True, dry_run=False)

    def test_missing_output_base_dir_is_a_noop(self, tmp_path):
        from ownscribe.pipeline import run_purge

        config = Config()
        config.output.dir = str(tmp_path / "does-not-exist")

        run_purge(config, older_than_days=None, purge_all=True, dry_run=False)


class TestRunEnroll:
    def test_errors_without_hf_token(self, tmp_path):
        from ownscribe.pipeline import run_enroll

        config = Config()
        config.diarization.hf_token = ""
        clip = tmp_path / "clip.wav"
        clip.touch()

        with pytest.raises(SystemExit):
            run_enroll(config, "Alice", str(clip))

    def test_saves_embedding_to_db(self, tmp_path):
        from ownscribe.pipeline import run_enroll
        from ownscribe.speakers.base import Voiceprint, VoiceprintDB

        config = Config()
        config.diarization.hf_token = "hf_test_token"
        clip = tmp_path / "clip.wav"
        clip.touch()
        db_path = tmp_path / "voiceprints.json"

        mock_embedder = mock.MagicMock()
        mock_embedder.embed_file.return_value = [0.1, 0.2, 0.3]

        with (
            mock.patch("ownscribe.speakers.embedding.SpeakerEmbedder", return_value=mock_embedder),
            mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path),
        ):
            run_enroll(config, "Alice", str(clip))

        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == [Voiceprint(name="Alice", embedding=[0.1, 0.2, 0.3])]

    def test_embedding_failure_exits_with_error(self, tmp_path):
        from ownscribe.pipeline import run_enroll

        config = Config()
        config.diarization.hf_token = "hf_test_token"
        clip = tmp_path / "clip.wav"
        clip.touch()

        mock_embedder = mock.MagicMock()
        mock_embedder.embed_file.side_effect = RuntimeError("boom")

        with (
            mock.patch("ownscribe.speakers.embedding.SpeakerEmbedder", return_value=mock_embedder),
            pytest.raises(SystemExit),
        ):
            run_enroll(config, "Alice", str(clip))

    def test_reenrolling_same_name_overwrites(self, tmp_path):
        from ownscribe.pipeline import run_enroll
        from ownscribe.speakers.base import VoiceprintDB

        config = Config()
        config.diarization.hf_token = "hf_test_token"
        clip = tmp_path / "clip.wav"
        clip.touch()
        db_path = tmp_path / "voiceprints.json"

        mock_embedder = mock.MagicMock()
        mock_embedder.embed_file.return_value = [1.0, 0.0]

        with (
            mock.patch("ownscribe.speakers.embedding.SpeakerEmbedder", return_value=mock_embedder),
            mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path),
        ):
            run_enroll(config, "Alice", str(clip))

        mock_embedder.embed_file.return_value = [0.0, 1.0]
        with (
            mock.patch("ownscribe.speakers.embedding.SpeakerEmbedder", return_value=mock_embedder),
            mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path),
        ):
            run_enroll(config, "Alice", str(clip))

        db = VoiceprintDB.load(db_path)
        assert len(db.voiceprints) == 1
        assert db.voiceprints[0].embedding == [0.0, 1.0]


class TestRunUnenroll:
    def test_removes_existing_speaker(self, tmp_path):
        from ownscribe.pipeline import run_unenroll
        from ownscribe.speakers.base import VoiceprintDB

        db_path = tmp_path / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0])
        db.save(db_path)

        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            run_unenroll("Alice")

        reloaded = VoiceprintDB.load(db_path)
        assert reloaded.voiceprints == []

    def test_missing_speaker_exits_with_error(self, tmp_path):
        from ownscribe.pipeline import run_unenroll

        db_path = tmp_path / "voiceprints.json"

        with (
            mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path),
            pytest.raises(SystemExit),
        ):
            run_unenroll("Nobody")


class TestRunListEnrolled:
    def test_lists_all_enrolled_names(self, tmp_path, capsys):
        from ownscribe.pipeline import run_list_enrolled
        from ownscribe.speakers.base import VoiceprintDB

        db_path = tmp_path / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [1.0])
        db.upsert("Bob", [0.0, 1.0])
        db.save(db_path)

        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            run_list_enrolled()

        captured = capsys.readouterr()
        assert "Alice" in captured.out
        assert "Bob" in captured.out

    def test_empty_db_reports_none_enrolled(self, tmp_path, capsys):
        from ownscribe.pipeline import run_list_enrolled

        db_path = tmp_path / "voiceprints.json"

        with mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", db_path):
            run_list_enrolled()

        captured = capsys.readouterr()
        assert "No enrolled speakers" in captured.out
