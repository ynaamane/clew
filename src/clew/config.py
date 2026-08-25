"""Configuration management with TOML loading and defaults."""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

CONFIG_DIR = Path("~/.config/clew").expanduser()
CONFIG_PATH = CONFIG_DIR / "config.toml"

# Legacy layout from the ownscribe/meeting-scribe era. Read only by clew.cli.main()'s
# one-time startup migration -- Config.load() itself never looks here, so migration
# must run (and complete) before Config.load() is called for the result to be correct.
LEGACY_CONFIG_DIR = Path("~/.config/ownscribe").expanduser()

BILINGUAL_INITIAL_PROMPT = (
    "On continue le sprint review, on regarde le backend et le pipeline de deployment. "
    "Let's also check the roadmap and merge the feedback from last time."
)

DEFAULT_CONFIG_TOML = """\
[audio]
backend = "coreaudio"     # "coreaudio" (default) or "sounddevice"
device = ""               # empty = system audio; or device name/index for sounddevice
mic = false               # also capture microphone input
mic_device = ""           # specific mic device name (empty = default)
echo_cancellation = "off"
capture_mode = "all"      # "all" = capture all system audio directly (default); "picker" = show source picker
capture_backend = "coreaudio"  # ownscribe-audio's mechanism: "coreaudio" (tap, macOS 14.2+) or "screencapturekit"
silence_timeout = 300     # seconds of silence before auto-stop; 0 = disabled

[transcription]
model = "large-v3"        # whisper model: tiny, base, small, medium, large-v3
language = ""             # empty = auto-detect (locked per-file from the first ~30s, not per-segment)
initial_prompt = "__BILINGUAL_INITIAL_PROMPT__"
# hotwords = ""           # comma-separated words to boost recognition (softer hint than initial_prompt)
# cpu_threads = 0         # CTranslate2 threads; 0 = auto-detect (performance core count), or explicit positive int
engine = "whisperx"

[canary]
repo = "CogniSoftOrg/canary-1b-v2-mlx-bf16"
max_segment_seconds = 10.0
max_tokens_per_segment = 200

[diarization]
enabled = false           # set to true + provide hf_token to enable
hf_token = ""             # HuggingFace token for pyannote models
min_speakers = 0          # 0 = auto-detect
max_speakers = 0
telemetry = false         # set to true to allow HuggingFace Hub + pyannote metrics telemetry
device = "auto"           # "auto" (MPS if available, else CPU), "cpu", or "mps"

[correction]
enabled = false           # opt-in LLM post-correction pass over the transcript text
max_length_delta_ratio = 0.4  # reject a segment fix that changes length by more than this fraction

[summarization]
enabled = true
backend = "local"         # "local" (built-in, no server needed), "ollama", or "openai"
model = "phi-4-mini"      # local: "phi-4-mini", path to GGUF, or hf:owner/repo/file.gguf; ollama/openai: model name
# host = "http://localhost:11434"  # only for ollama/openai backends
# api_key = ""            # only for openai backend; required by servers like oMLX (or set OPENAI_API_KEY)
# template = "meeting"    # built-in: "meeting", "lecture", or "brief"
# context_size = 0        # 0 = auto-detect from model; set manually for OpenAI-compatible backends

# Custom templates (optional):
# [templates.my-notes]
# system_prompt = "You are a helpful assistant."
# prompt = "Summarize:\\n{transcript}"

[output]
dir = "~/clew"            # base output directory
audio_dir = ""            # directory for audio recordings; empty = same as dir
format = "markdown"       # "markdown" or "json"
keep_recording = true     # keep WAV files after transcription; false = auto-delete
retention_days = 0        # days before `clew purge` may remove audio; 0 = keep forever (manual purge only)
""".replace("__BILINGUAL_INITIAL_PROMPT__", BILINGUAL_INITIAL_PROMPT)


@dataclass
class AudioConfig:
    backend: str = "coreaudio"
    device: str = ""
    mic: bool = False
    mic_device: str = ""
    echo_cancellation: str = "off"
    capture_mode: str = "all"  # "all" = all system audio (default); "picker" = show source picker
    capture_backend: str = "coreaudio"  # ownscribe-audio mechanism: "coreaudio" (tap, default) or "screencapturekit"
    silence_timeout: int = 300  # seconds of silence before auto-stop; 0 = disabled


@dataclass
class TranscriptionConfig:
    model: str = "large-v3"
    language: str = ""
    initial_prompt: str = BILINGUAL_INITIAL_PROMPT
    hotwords: str = ""
    engine: str = "whisperx"
    cpu_threads: int = 0


@dataclass
class CanaryConfig:
    repo: str = "CogniSoftOrg/canary-1b-v2-mlx-bf16"
    max_segment_seconds: float = 10.0
    max_tokens_per_segment: int = 200


@dataclass
class DiarizationConfig:
    enabled: bool = False
    hf_token: str = ""
    min_speakers: int = 0
    max_speakers: int = 0
    telemetry: bool = False
    device: str = "auto"


@dataclass
class CorrectionConfig:
    enabled: bool = False
    max_length_delta_ratio: float = 0.4


@dataclass
class SummarizationConfig:
    enabled: bool = True
    backend: str = "local"
    model: str = "phi-4-mini"
    host: str = "http://localhost:11434"
    api_key: str = ""
    template: str = ""
    context_size: int = 0


@dataclass
class TemplateConfig:
    system_prompt: str = ""
    prompt: str = ""


# Legacy default from the ownscribe/meeting-scribe era, compared against verbatim by
# clew.cli.main()'s output-dir migration -- never touched otherwise.
LEGACY_OUTPUT_DEFAULT = "~/ownscribe"


@dataclass
class OutputConfig:
    dir: str = "~/clew"
    audio_dir: str = ""
    format: str = "markdown"
    keep_recording: bool = True
    retention_days: int = 0

    @property
    def resolved_dir(self) -> Path:
        return Path(self.dir).expanduser()

    @property
    def resolved_audio_dir(self) -> Path:
        return Path(self.audio_dir).expanduser() if self.audio_dir else self.resolved_dir

    @property
    def uses_separate_audio_dir(self) -> bool:
        return self.resolved_audio_dir != self.resolved_dir


@dataclass
class Config:
    audio: AudioConfig = field(default_factory=AudioConfig)
    transcription: TranscriptionConfig = field(default_factory=TranscriptionConfig)
    canary: CanaryConfig = field(default_factory=CanaryConfig)
    diarization: DiarizationConfig = field(default_factory=DiarizationConfig)
    correction: CorrectionConfig = field(default_factory=CorrectionConfig)
    summarization: SummarizationConfig = field(default_factory=SummarizationConfig)
    output: OutputConfig = field(default_factory=OutputConfig)
    templates: dict[str, TemplateConfig] = field(default_factory=dict)
    progress_mode: str = "tui"

    @classmethod
    def load(cls) -> Config:
        """Load config from TOML file, falling back to defaults."""
        config = cls()

        if CONFIG_PATH.exists():
            with open(CONFIG_PATH, "rb") as f:
                data = tomllib.load(f)
            config = _merge_toml(config, data)

        # Env var overrides
        if hf_token := os.environ.get("HF_TOKEN"):
            config.diarization.hf_token = hf_token
        if ollama_host := os.environ.get("OLLAMA_HOST"):
            config.summarization.host = ollama_host
        if api_key := os.environ.get("OPENAI_API_KEY"):
            config.summarization.api_key = api_key
        if progress_mode := os.environ.get("CLEW_PROGRESS") or os.environ.get("OWNSCRIBE_PROGRESS"):
            config.progress_mode = progress_mode

        return config


def _validate_cpu_threads(value: int | str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"cpu_threads must be a positive integer, got {value!r}")
    if isinstance(value, float):
        if value != int(value):
            raise ValueError(f"cpu_threads must be a positive integer, got {value!r}")
        value = int(value)
    try:
        threads = int(value)
    except (ValueError, TypeError) as e:
        raise ValueError(f"cpu_threads must be a positive integer, got {value!r}") from e
    if threads < 0:
        raise ValueError(f"cpu_threads must be a positive integer, got {threads}")

    max_threads = (os.cpu_count() or 1) * 4
    if threads > max_threads:
        raise ValueError(f"cpu_threads={threads} exceeds 4x logical cores (max {max_threads} on this machine)")

    return threads


_VALID_DIARIZATION_DEVICES = ("auto", "cpu", "mps")


def _validate_diarization_device(value: str) -> str:
    if value not in _VALID_DIARIZATION_DEVICES:
        raise ValueError(f"diarization.device must be one of {_VALID_DIARIZATION_DEVICES}, got {value!r}")
    return value


def _merge_toml(config: Config, data: dict) -> Config:
    """Merge TOML data into config dataclass."""
    if "audio" in data:
        for k, v in data["audio"].items():
            if hasattr(config.audio, k):
                setattr(config.audio, k, v)

    if "transcription" in data:
        for k, v in data["transcription"].items():
            if hasattr(config.transcription, k):
                if k == "cpu_threads":
                    v = _validate_cpu_threads(v)
                setattr(config.transcription, k, v)

    if "canary" in data:
        for k, v in data["canary"].items():
            if hasattr(config.canary, k):
                setattr(config.canary, k, v)

    if "diarization" in data:
        for k, v in data["diarization"].items():
            if hasattr(config.diarization, k):
                if k == "device":
                    v = _validate_diarization_device(v)
                setattr(config.diarization, k, v)

    if "correction" in data:
        for k, v in data["correction"].items():
            if hasattr(config.correction, k):
                setattr(config.correction, k, v)

    if "summarization" in data:
        for k, v in data["summarization"].items():
            if hasattr(config.summarization, k):
                setattr(config.summarization, k, v)

    if "output" in data:
        for k, v in data["output"].items():
            if hasattr(config.output, k):
                setattr(config.output, k, v)

    if "templates" in data:
        for name, t_data in data["templates"].items():
            config.templates[name] = TemplateConfig(
                system_prompt=t_data.get("system_prompt", ""),
                prompt=t_data.get("prompt", ""),
            )

    return config


def ensure_config_file() -> Path:
    """Create default config file if it doesn't exist. Returns the path."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_PATH.exists():
        CONFIG_PATH.write_text(DEFAULT_CONFIG_TOML)
    return CONFIG_PATH
