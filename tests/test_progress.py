"""Tests for progress parsing and TUI rendering helpers."""

from __future__ import annotations

import io
import json
from unittest import mock

from clew.progress import (
    _BRAILLE,
    DownloadProgressEvent,
    DownloadProgressWriter,
    JsonProgress,
    PipelineProgress,
    download_event_fraction,
    format_download_progress,
    parse_download_progress,
)


class TestDownloadProgressParsing:
    def test_parses_tqdm_style_line(self):
        event = parse_download_progress("model.bin: 26%|##5       | 123MB/466MB [00:10<00:20, 12.3MB/s]")

        assert event is not None
        assert event.filename == "model.bin"
        assert event.percent == 26.0
        assert event.bytes_done is not None
        assert event.bytes_total is not None
        assert format_download_progress(event).startswith("model.bin")

    def test_ignores_non_progress_noise(self):
        assert parse_download_progress("Some unrelated log line") is None

    def test_writer_handles_partial_carriage_return_updates(self):
        events = []
        writer = DownloadProgressWriter(events.append)

        writer.write("model.bin: 12%|##")
        writer.write("         | 12MB/100MB [00:01<00:08, 10MB/s]\r")
        writer.flush()

        assert events
        assert events[-1].percent == 12.0
        assert events[-1].filename == "model.bin"

    def test_writer_ignores_unknown_size_units_without_crashing(self):
        events = []
        writer = DownloadProgressWriter(events.append)

        writer.write("model.bin: 10%|#         | 1EiB/2EiB [00:01<00:09]\r")
        writer.flush()

        assert events == []


class TestDownloadProgressFraction:
    def test_prefers_bytes_ratio(self):
        event = parse_download_progress("model.bin: 26%|##5| 123MB/466MB [00:10<00:20]")
        assert event is not None
        fraction = download_event_fraction(event)
        assert fraction is not None
        assert 0.26 < fraction < 0.27

    def test_uses_percent_when_bytes_missing(self):
        event = parse_download_progress("Progress 75% complete")
        assert event is not None
        assert download_event_fraction(event) == 0.75

    def test_clamps_fraction(self):
        from clew.progress import DownloadProgressEvent

        assert download_event_fraction(DownloadProgressEvent(percent=150)) == 1.0
        assert download_event_fraction(DownloadProgressEvent(percent=-5)) == 0.0

    def test_returns_none_without_progress_numbers(self):
        assert download_event_fraction(DownloadProgressEvent(filename="model.bin")) is None


class TestDownloadProgressFormatting:
    def test_can_omit_percent_when_bar_already_shows_it(self):
        event = DownloadProgressEvent(
            filename="model.bin",
            percent=10.0,
            bytes_done=10 * 1024**2,
            bytes_total=100 * 1024**2,
        )
        text = format_download_progress(event, include_percent=False)

        assert "model.bin" in text
        assert "%" not in text


class TestPipelineProgressDetails:
    def test_renders_detail_line_for_active_step(self):
        progress = PipelineProgress(transcribe=False, include_prepare=True)
        progress._stderr = io.StringIO()
        progress.begin("preparing_models")
        progress.set_detail("preparing_models", "Downloading model.bin 12 MB / 100 MB (12%)")

        progress._render_all(final=True)
        output = progress._stderr.getvalue()

        assert "Preparing models" in output
        assert "Downloading model.bin" in output

        progress._stop.set()
        if progress._thread is not None:
            progress._thread.join()

    def test_detail_clears_on_complete(self):
        progress = PipelineProgress(transcribe=False, include_prepare=True)
        progress._stderr = io.StringIO()
        progress.begin("preparing_models")
        progress.set_detail("preparing_models", "Downloading...")
        progress.complete("preparing_models")

        progress._render_all(final=True)
        output = progress._stderr.getvalue()

        assert "Downloading..." not in output

        progress._stop.set()
        if progress._thread is not None:
            progress._thread.join()

    def test_determinate_active_row_includes_spinner_glyph(self):
        progress = PipelineProgress(transcribe=False, include_prepare=True)
        progress._stderr = io.StringIO()
        progress.begin("preparing_models")
        progress.update("preparing_models", 0.1)

        with mock.patch("clew.progress.time.time", return_value=0.0):
            progress._render_all(final=False)

        output = progress._stderr.getvalue()
        assert f"  {_BRAILLE[0]} Preparing models" in output
        assert "[██" in output or "[█" in output

        progress._stop.set()
        if progress._thread is not None:
            progress._thread.join()

    def test_renderer_clears_each_line_and_stale_rows_when_detail_disappears(self):
        progress = PipelineProgress(transcribe=False, include_prepare=True)
        progress._stderr = io.StringIO()
        progress.begin("preparing_models")
        progress.set_detail("preparing_models", "Downloading...")

        progress._render_all(final=True)
        first = progress._stderr.getvalue()
        first_len = len(first)
        assert first.count("\033[K\n") >= 2

        progress.set_detail("preparing_models", None)
        progress._render_all(final=True)
        second_delta = progress._stderr.getvalue()[first_len:]

        assert "\033[2A" in second_delta
        # One real line + one blank clearing line for the removed detail row.
        assert second_delta.count("\033[K\n") == 2
        assert "Downloading..." not in second_delta

        progress._stop.set()
        if progress._thread is not None:
            progress._thread.join()

    def test_preparing_models_is_not_included_by_default(self):
        progress = PipelineProgress(transcribe=True)
        assert "preparing_models" not in progress._step_map

    def test_preparing_models_can_be_enabled_explicitly(self):
        progress = PipelineProgress(transcribe=False, include_prepare=True)
        assert "preparing_models" in progress._step_map


def _read_events(stream: io.StringIO) -> list[dict]:
    return [json.loads(line) for line in stream.getvalue().strip().splitlines()]


class TestJsonProgress:
    def test_begin_emits_one_json_line(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.begin("transcribing")

        events = _read_events(progress._stream)
        assert events == [{"event": "begin", "step": "transcribing"}]

    def test_complete_emits_complete_event(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.complete("transcribing")

        events = _read_events(progress._stream)
        assert events == [{"event": "complete", "step": "transcribing"}]

    def test_fail_emits_fail_event(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.fail("diarizing")

        events = _read_events(progress._stream)
        assert events == [{"event": "fail", "step": "diarizing"}]

    def test_update_emits_clamped_fraction(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.update("transcribing", 0.42)
        progress.update("transcribing", 1.5)
        progress.update("transcribing", -0.5)

        events = _read_events(progress._stream)
        assert events[0] == {"event": "update", "step": "transcribing", "fraction": 0.42}
        assert events[1]["fraction"] == 1.0
        assert events[2]["fraction"] == 0.0

    def test_set_detail_emits_detail_event(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.set_detail("transcribing", "loading model")

        events = _read_events(progress._stream)
        assert events == [{"event": "detail", "step": "transcribing", "detail": "loading model"}]

    def test_set_detail_with_none_emits_null_detail(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.set_detail("transcribing", None)

        events = _read_events(progress._stream)
        assert events == [{"event": "detail", "step": "transcribing", "detail": None}]

    def test_full_pipeline_step_ordering(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        with progress:
            progress.begin("transcribing")
            progress.update("transcribing", 0.5)
            progress.complete("transcribing")
            progress.begin("summarizing")
            progress.complete("summarizing")

        events = _read_events(progress._stream)
        assert [(e["event"], e["step"]) for e in events] == [
            ("begin", "transcribing"),
            ("update", "transcribing"),
            ("complete", "transcribing"),
            ("begin", "summarizing"),
            ("complete", "summarizing"),
        ]

    def test_diarization_hook_begins_step_once_and_updates_fraction(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.diarization_hook("speaker_diarization/segmentation", None, completed=3, total=10)
        progress.diarization_hook("speaker_diarization/segmentation", None, completed=10, total=10)

        events = _read_events(progress._stream)
        assert events[0] == {"event": "begin", "step": "segmentation"}
        assert events[1] == {"event": "update", "step": "segmentation", "fraction": 0.3}
        assert events[2] == {"event": "update", "step": "segmentation", "fraction": 1.0}

    def test_diarization_hook_maps_discrete_diarization_to_clustering(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.diarization_hook("discrete_diarization", None, completed=1, total=1)

        events = _read_events(progress._stream)
        assert events[0]["step"] == "clustering"

    def test_diarization_hook_without_total_only_begins(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.diarization_hook("embeddings", None)

        events = _read_events(progress._stream)
        assert events == [{"event": "begin", "step": "embeddings"}]

    def test_complete_allows_a_step_to_begin_again(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        progress.diarization_hook("segmentation", None, completed=1, total=1)
        progress.complete("segmentation")
        progress.diarization_hook("segmentation", None, completed=1, total=2)

        events = _read_events(progress._stream)
        assert [(e["event"], e["step"]) for e in events] == [
            ("begin", "segmentation"),
            ("update", "segmentation"),
            ("complete", "segmentation"),
            ("begin", "segmentation"),
            ("update", "segmentation"),
        ]

    def test_context_manager_does_not_emit_extra_events(self):
        progress = JsonProgress()
        progress._stream = io.StringIO()

        with progress as p:
            p.begin("transcribing")

        events = _read_events(progress._stream)
        assert events == [{"event": "begin", "step": "transcribing"}]

    def test_constructor_accepts_pipeline_progress_style_kwargs(self):
        progress = JsonProgress(diarize=True, summarize=True, download_summarizer=True)
        assert isinstance(progress, JsonProgress)
