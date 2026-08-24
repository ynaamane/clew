"""Local summarization via llama-cpp-python."""

from __future__ import annotations

import contextlib
import logging
import os
from collections.abc import Callable
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import TYPE_CHECKING

from clew.progress import DownloadProgressEvent, DownloadProgressWriter
from clew.summarization.base import SummarizationContextError, Summarizer
from clew.summarization.prompts import clean_response

if TYPE_CHECKING:
    from llama_cpp import Llama

    from clew.config import SummarizationConfig, TemplateConfig

logger = logging.getLogger(__name__)

# Short name → (HuggingFace repo, GGUF filename)
_MODEL_REGISTRY: dict[str, tuple[str, str]] = {
    "phi-4-mini": (
        "unsloth/Phi-4-mini-instruct-GGUF",
        "Phi-4-mini-instruct-Q4_K_M.gguf",
    ),
}

# Cheap first load used to read the model's tokenizer and trained context length
# (n_ctx_train) -- vocab_only=True reports n_ctx_train as 0 (measured against
# phi-4-mini Q4_K_M, llama-cpp-python 0.3.16), so this must be a real, if small, load.
# Reused as the actual inference instance whenever it already covers what's needed.
_PROBE_N_CTX = 512

# Headroom reserved for the model's own reply, on top of the prompt's token count.
_OUTPUT_MARGIN_TOKENS = 1024


def _ensure_model(
    model_name: str,
    on_progress: Callable[[DownloadProgressEvent], None] | None = None,
) -> Path:
    """Download the GGUF model if not already cached. Returns the local path."""
    from huggingface_hub import hf_hub_download

    if model_name.startswith("hf:"):
        # Format: "hf:owner/repo/filename.gguf"
        parts = model_name[3:]  # strip "hf:"
        slash_idx = parts.rfind("/")
        if slash_idx == -1:
            raise ValueError(
                f"Invalid HuggingFace model spec '{model_name}'. Expected format: hf:owner/repo/filename.gguf"
            )
        repo_id = parts[:slash_idx]
        filename = parts[slash_idx + 1 :]
    elif model_name in _MODEL_REGISTRY:
        repo_id, filename = _MODEL_REGISTRY[model_name]
    else:
        # Treat as a direct path to a GGUF file
        path = Path(model_name).expanduser()
        if path.exists():
            return path
        raise FileNotFoundError(
            f"Unknown model '{model_name}'. "
            f"Available: {', '.join(_MODEL_REGISTRY)}, "
            "a path to a GGUF file, or hf:owner/repo/filename.gguf"
        )

    try:
        if on_progress is not None:
            writer = DownloadProgressWriter(on_progress)
            with redirect_stdout(writer), redirect_stderr(writer):
                path = Path(hf_hub_download(repo_id=repo_id, filename=filename))
            writer.flush()
            return path
        return Path(hf_hub_download(repo_id=repo_id, filename=filename))
    except Exception as exc:
        raise RuntimeError(
            f"Failed to download model '{model_name}' from {repo_id}: {exc}\n"
            "Check your internet connection and try again."
        ) from exc


@contextlib.contextmanager
def _suppress_stderr():
    """Redirect fd 2 to /dev/null to silence C-level stderr (e.g. ggml_metal_init).

    Falls back to a no-op if fd manipulation is unavailable.
    """
    try:
        devnull_fd = os.open(os.devnull, os.O_WRONLY)
        old_fd = os.dup(2)
    except OSError:
        yield
        return
    os.dup2(devnull_fd, 2)
    try:
        yield
    finally:
        os.dup2(old_fd, 2)
        os.close(devnull_fd)
        os.close(old_fd)


class LlamaCppSummarizer(Summarizer):
    """Summarizes transcripts using a local GGUF model via llama-cpp-python."""

    def __init__(
        self,
        config: SummarizationConfig,
        templates: dict[str, TemplateConfig] | None = None,
    ) -> None:
        self._config = config
        self._templates = templates or {}
        self._llm: Llama | None = None

    def close(self) -> None:
        """Free the loaded model deterministically. Idempotent."""
        llm = self._llm
        self._llm = None
        if llm is not None:
            # Plain try/except, not contextlib.suppress: this runs from __del__ at
            # interpreter shutdown when the `contextlib` global is already None.
            try:  # noqa: SIM105
                llm.close()
            except Exception:
                pass

    def __del__(self) -> None:
        try:  # noqa: SIM105
            self.close()
        except Exception:
            pass

    def _get_llm(self, min_ctx: int = _PROBE_N_CTX) -> Llama:
        """Lazy-load the model, sized to at least min_ctx tokens of context.

        Reuses the cached instance when its context already covers min_ctx.
        Otherwise (re)loads with a bigger n_ctx -- llama.cpp's KV cache is fixed
        at construction, so a cached small-context instance must never silently
        serve a request it cannot cover.
        """
        if self._llm is not None and self._llm.n_ctx() >= min_ctx:
            return self._llm

        from llama_cpp import Llama

        if self._llm is not None:
            self._llm.close()
            self._llm = None

        model_path = _ensure_model(self._config.model)
        n_ctx = max(min_ctx, _PROBE_N_CTX)
        logger.info("Loading model from %s (n_ctx=%d)", model_path, n_ctx)
        with _suppress_stderr():
            self._llm = Llama(
                model_path=str(model_path),
                n_ctx=n_ctx,
                n_gpu_layers=-1,  # auto: offloads to Metal/CUDA when available, falls back to CPU
                verbose=False,
            )
        return self._llm

    def _required_ctx(self, *texts: str) -> int:
        """Tokenize these prompt texts with the model's own tokenizer and return the
        context window they need (prompt tokens + a generation margin).

        context_size > 0 is used as-is (an explicit budget the caller committed to);
        context_size == 0 (auto) sizes to min(need, the model's trained context
        length). Raises SummarizationContextError -- before any inference call --
        when the requirement cannot be met either way.
        """
        import llama_cpp

        probe = self._get_llm()
        combined = "\n".join(texts).encode("utf-8")
        prompt_tokens = len(probe.tokenize(combined, add_bos=True))
        needed = prompt_tokens + _OUTPUT_MARGIN_TOKENS

        if self._config.context_size > 0:
            limit = self._config.context_size
            if needed > limit:
                raise SummarizationContextError(
                    f"This transcript needs about {needed} tokens of context "
                    f"({prompt_tokens} prompt + {_OUTPUT_MARGIN_TOKENS} output margin), "
                    f"but [summarization] context_size is set to {limit}. Increase "
                    "context_size in your config, or summarize a shorter transcript."
                )
            return limit

        model_limit = llama_cpp.llama_model_n_ctx_train(probe.model)
        if needed > model_limit:
            raise SummarizationContextError(
                f"This transcript needs about {needed} tokens of context "
                f"({prompt_tokens} prompt + {_OUTPUT_MARGIN_TOKENS} output margin), "
                f"but model '{self._config.model}' supports at most {model_limit} "
                "tokens. Use a model with a longer context window, or summarize a "
                "shorter transcript."
            )
        return min(needed, model_limit)

    def chat(
        self,
        system_prompt: str,
        user_prompt: str,
        json_mode: bool = False,
        json_schema: dict | None = None,
    ) -> str:
        try:
            min_ctx = self._required_ctx(system_prompt, user_prompt)
            llm = self._get_llm(min_ctx)
        except SummarizationContextError:
            return ""
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]
        if json_mode:
            if json_schema is not None:
                formats_to_try: list[dict | None] = [
                    {"type": "json_object", "schema": json_schema},
                    {"type": "json_object"},
                    None,
                ]
            else:
                formats_to_try = [{"type": "json_object"}, None]
        else:
            formats_to_try = [None]

        for fmt in formats_to_try:
            try:
                kwargs: dict = {}
                if fmt is not None:
                    kwargs["response_format"] = fmt
                response = llm.create_chat_completion(messages=messages, **kwargs)
                return clean_response(response["choices"][0]["message"]["content"] or "")
            except Exception:
                continue
        return ""

    def is_available(self) -> bool:
        try:
            import llama_cpp  # noqa: F401

            return True
        except ImportError:
            return False

    def summarize(self, transcript_text: str, language: str | None = None) -> str:
        from clew.summarization.prompts import language_instruction, resolve_template

        system, prompt = resolve_template(self._config.template, self._templates)
        system += language_instruction(language or "")
        user = prompt.format(transcript=transcript_text)
        min_ctx = self._required_ctx(system, user)
        llm = self._get_llm(min_ctx)
        response = llm.create_chat_completion(
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        )
        return clean_response(response["choices"][0]["message"]["content"] or "")

    def generate_title(self, summary_text: str) -> str:
        from clew.summarization.prompts import TITLE_PROMPT, TITLE_SYSTEM

        user = TITLE_PROMPT.format(summary=summary_text)
        min_ctx = self._required_ctx(TITLE_SYSTEM, user)
        llm = self._get_llm(min_ctx)
        response = llm.create_chat_completion(
            messages=[
                {"role": "system", "content": TITLE_SYSTEM},
                {"role": "user", "content": user},
            ],
        )
        return clean_response(response["choices"][0]["message"]["content"] or "").strip()
