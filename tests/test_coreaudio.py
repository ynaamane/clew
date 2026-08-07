"""Tests for CoreAudioRecorder's binary version-compat probe and mic fail-loud gate."""

from __future__ import annotations

from unittest import mock

import pytest

from clew.audio.coreaudio import CoreAudioRecorder, binary_supports_separate_tracks


class TestBinarySupportsSeparateTracks:
    def test_true_when_binary_reports_the_patched_error_string(self, tmp_path):
        binary = tmp_path / "patched.sh"
        binary.write_text("#!/bin/sh\necho 'Error: --sustained-seconds requires a number of seconds'\nexit 1\n")
        binary.chmod(0o755)

        assert binary_supports_separate_tracks(binary) is True

    def test_false_when_binary_reports_unknown_command(self, tmp_path):
        binary = tmp_path / "unpatched.sh"
        binary.write_text('#!/bin/sh\necho "Unknown command: $1"\nexit 1\n')
        binary.chmod(0o755)

        assert binary_supports_separate_tracks(binary) is False

    def test_false_when_binary_prints_nothing(self, tmp_path):
        binary = tmp_path / "silent.sh"
        binary.write_text("#!/bin/sh\nexit 0\n")
        binary.chmod(0o755)

        assert binary_supports_separate_tracks(binary) is False

    def test_false_when_binary_echoes_its_own_arguments(self, tmp_path):
        binary = tmp_path / "echo_args.sh"
        binary.write_text('#!/bin/sh\necho "$@"\n')
        binary.chmod(0o755)

        assert binary_supports_separate_tracks(binary) is False

    def test_false_when_path_does_not_exist(self, tmp_path):
        assert binary_supports_separate_tracks(tmp_path / "does-not-exist") is False

    def test_false_when_path_is_not_executable(self, tmp_path):
        not_executable = tmp_path / "not_executable.txt"
        not_executable.write_text("hello")

        assert binary_supports_separate_tracks(not_executable) is False

    def test_false_on_timeout(self, tmp_path):
        import subprocess

        binary = tmp_path / "hangs.sh"
        binary.write_text("#!/bin/sh\nsleep 999\n")
        binary.chmod(0o755)

        with mock.patch(
            "clew.audio.coreaudio.subprocess.run",
            side_effect=subprocess.TimeoutExpired(cmd="x", timeout=5),
        ):
            assert binary_supports_separate_tracks(binary) is False


class TestCoreAudioRecorderMicFailLoud:
    """CoreAudioRecorder.start() refuses to silently degrade separate-track retention."""

    def _make_recorder(self, mic: bool = True, binary_path=None):
        with mock.patch("clew.audio.coreaudio._find_binary", return_value=binary_path):
            return CoreAudioRecorder(mic=mic)

    def test_start_with_mic_raises_when_binary_lacks_separate_tracks(self, tmp_path):
        binary = tmp_path / "unpatched.sh"
        binary.write_text('#!/bin/sh\necho "Unknown command: $1"\nexit 1\n')
        binary.chmod(0o755)

        recorder = self._make_recorder(mic=True, binary_path=binary)

        with pytest.raises(RuntimeError, match="separate mic/system tracks"):
            recorder.start(tmp_path / "recording.wav")

    def test_start_without_mic_does_not_probe_binary(self, tmp_path):
        binary = tmp_path / "unpatched.sh"
        binary.write_text('#!/bin/sh\necho "Unknown command: $1"\nexit 1\n')
        binary.chmod(0o755)

        recorder = self._make_recorder(mic=False, binary_path=binary)

        with mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen:
            recorder.start(tmp_path / "recording.wav")
            mock_popen.assert_called_once()

    def test_start_with_mic_succeeds_when_binary_supports_separate_tracks(self, tmp_path):
        binary = tmp_path / "patched.sh"
        binary.touch()
        binary.chmod(0o755)

        recorder = self._make_recorder(mic=True, binary_path=binary)

        with (
            mock.patch("clew.audio.coreaudio.binary_supports_separate_tracks", return_value=True),
            mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen,
        ):
            recorder.start(tmp_path / "recording.wav")
            mock_popen.assert_called_once()
            cmd = mock_popen.call_args[0][0]
            assert "--mic" in cmd

    def test_mic_device_alone_also_triggers_the_probe(self, tmp_path):
        binary = tmp_path / "unpatched.sh"
        binary.write_text('#!/bin/sh\necho "Unknown command: $1"\nexit 1\n')
        binary.chmod(0o755)

        with mock.patch("clew.audio.coreaudio._find_binary", return_value=binary):
            recorder = CoreAudioRecorder(mic=False, mic_device="USB Mic")

        with pytest.raises(RuntimeError, match="separate mic/system tracks"):
            recorder.start(tmp_path / "recording.wav")

    def test_start_without_binary_raises_the_original_not_found_error(self, tmp_path):
        recorder = self._make_recorder(mic=True, binary_path=None)

        with pytest.raises(RuntimeError, match="binary not found"):
            recorder.start(tmp_path / "recording.wav")


class TestCoreAudioRecorderCaptureBackend:
    """CoreAudioRecorder.start() defaults to the CoreAudio tap and only adds
    ScreenCaptureKit-specific flags when explicitly asked for the SCK fallback."""

    def _make_recorder(self, capture_backend: str = "coreaudio", capture_mode: str = "all", binary_path=None):
        with mock.patch("clew.audio.coreaudio._find_binary", return_value=binary_path):
            return CoreAudioRecorder(capture_backend=capture_backend, capture_mode=capture_mode)

    def test_default_backend_omits_capture_backend_and_capture_mode_flags(self, tmp_path):
        binary = tmp_path / "patched.sh"
        binary.touch()
        binary.chmod(0o755)
        recorder = self._make_recorder(binary_path=binary)

        with mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen:
            recorder.start(tmp_path / "recording.wav")
            cmd = mock_popen.call_args[0][0]
            assert "--capture-backend" not in cmd
            assert "--capture-mode-all" not in cmd

    def test_screencapturekit_backend_passes_capture_backend_flag(self, tmp_path):
        binary = tmp_path / "patched.sh"
        binary.touch()
        binary.chmod(0o755)
        recorder = self._make_recorder(capture_backend="screencapturekit", binary_path=binary)

        with mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen:
            recorder.start(tmp_path / "recording.wav")
            cmd = mock_popen.call_args[0][0]
            assert "--capture-backend" in cmd
            assert cmd[cmd.index("--capture-backend") + 1] == "screencapturekit"

    def test_screencapturekit_backend_with_capture_mode_all_passes_both_flags(self, tmp_path):
        binary = tmp_path / "patched.sh"
        binary.touch()
        binary.chmod(0o755)
        recorder = self._make_recorder(capture_backend="screencapturekit", capture_mode="all", binary_path=binary)

        with mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen:
            recorder.start(tmp_path / "recording.wav")
            cmd = mock_popen.call_args[0][0]
            assert "--capture-backend" in cmd
            assert "--capture-mode-all" in cmd

    def test_screencapturekit_backend_with_picker_mode_omits_capture_mode_all(self, tmp_path):
        binary = tmp_path / "patched.sh"
        binary.touch()
        binary.chmod(0o755)
        recorder = self._make_recorder(capture_backend="screencapturekit", capture_mode="picker", binary_path=binary)

        with mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen:
            recorder.start(tmp_path / "recording.wav")
            cmd = mock_popen.call_args[0][0]
            assert "--capture-backend" in cmd
            assert "--capture-mode-all" not in cmd


class TestCoreAudioRecorderEchoCancellation:
    """--echo-cancellation is only ever passed when --mic is also active (the
    Swift binary's own flag has no effect without a mic input to process) and
    is omitted entirely for the "off" default, matching --capture-backend's
    omit-by-default convention."""

    def _make_patched_binary(self, tmp_path):
        binary = tmp_path / "patched.sh"
        binary.write_text("#!/bin/sh\necho 'Error: --sustained-seconds requires a number of seconds'\nexit 1\n")
        binary.chmod(0o755)
        return binary

    def test_default_off_omits_the_flag_even_with_mic(self, tmp_path):
        binary = self._make_patched_binary(tmp_path)
        with mock.patch("clew.audio.coreaudio._find_binary", return_value=binary):
            recorder = CoreAudioRecorder(mic=True)

        with (
            mock.patch("clew.audio.coreaudio.binary_supports_separate_tracks", return_value=True),
            mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen,
        ):
            recorder.start(tmp_path / "recording.wav")
            cmd = mock_popen.call_args[0][0]
            assert "--echo-cancellation" not in cmd

    def test_on_mode_passes_the_flag_with_mic(self, tmp_path):
        binary = self._make_patched_binary(tmp_path)
        with mock.patch("clew.audio.coreaudio._find_binary", return_value=binary):
            recorder = CoreAudioRecorder(mic=True, echo_cancellation="on")

        with (
            mock.patch("clew.audio.coreaudio.binary_supports_separate_tracks", return_value=True),
            mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen,
        ):
            recorder.start(tmp_path / "recording.wav")
            cmd = mock_popen.call_args[0][0]
            assert "--echo-cancellation" in cmd
            assert cmd[cmd.index("--echo-cancellation") + 1] == "on"

    def test_auto_mode_passes_the_flag_with_mic(self, tmp_path):
        binary = self._make_patched_binary(tmp_path)
        with mock.patch("clew.audio.coreaudio._find_binary", return_value=binary):
            recorder = CoreAudioRecorder(mic=True, echo_cancellation="auto")

        with (
            mock.patch("clew.audio.coreaudio.binary_supports_separate_tracks", return_value=True),
            mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen,
        ):
            recorder.start(tmp_path / "recording.wav")
            cmd = mock_popen.call_args[0][0]
            assert "--echo-cancellation" in cmd
            assert cmd[cmd.index("--echo-cancellation") + 1] == "auto"

    def test_on_mode_without_mic_never_passes_the_flag(self, tmp_path):
        binary = self._make_patched_binary(tmp_path)
        with mock.patch("clew.audio.coreaudio._find_binary", return_value=binary):
            recorder = CoreAudioRecorder(mic=False, echo_cancellation="on")

        with mock.patch("clew.audio.coreaudio.subprocess.Popen") as mock_popen:
            recorder.start(tmp_path / "recording.wav")
            cmd = mock_popen.call_args[0][0]
            assert "--echo-cancellation" not in cmd
