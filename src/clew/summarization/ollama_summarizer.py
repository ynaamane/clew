"""Ollama-based summarization."""

from __future__ import annotations

import ollama

from clew.config import SummarizationConfig
from clew.summarization.base import SummarizationContextError, Summarizer
from clew.summarization.prompts import clean_response

# Ollama exposes no local tokenizer (unlike llama-cpp, which reads the GGUF's own
# vocab in LlamaCppSummarizer._required_ctx) -- ~4 chars/token is the standard
# rough estimate, and the output margin mirrors llama_cpp_summarizer.py's.
_CHARS_PER_TOKEN_ESTIMATE = 4
_OUTPUT_MARGIN_TOKENS = 1024


def _estimate_tokens(text: str) -> int:
    return len(text) // _CHARS_PER_TOKEN_ESTIMATE


class OllamaSummarizer(Summarizer):
    """Summarizes transcripts using a local Ollama model."""

    def __init__(self, config: SummarizationConfig, templates: dict | None = None) -> None:
        self._config = config
        self._templates = templates or {}
        self._client = ollama.Client(host=config.host)
        self._auto_context_limit: int | None = None
        self._auto_context_queried = False

    def native_context_length(self) -> int | None:
        """Best-effort native context window for the configured model, independent of
        any explicit config.context_size override (see base class contract).

        Queried once via /api/show and memoized per instance: this runs on every
        summarize/chat/generate_title call via _context_limit() below, and a model's
        context length cannot change mid-session, so re-querying on every call would
        be a real added round-trip for no new information. If the lookup fails (model
        not pulled, server unreachable, an Ollama version without the field) the limit
        is unknown and callers must degrade gracefully rather than guess at it.
        """
        if self._auto_context_queried:
            return self._auto_context_limit
        self._auto_context_queried = True
        try:
            info = self._client.show(self._config.model)
        except Exception:
            return None
        # ollama's ShowResponse aliases its `model_info` JSON field to the Python
        # attribute `modelinfo` (no underscore) -- `.get("model_info")` on the
        # response object looks up the Python name and silently returns nothing.
        model_info = getattr(info, "modelinfo", None)
        if model_info is None and isinstance(info, dict):
            model_info = info.get("model_info") or info.get("modelinfo")
        for key, value in (model_info or {}).items():
            if "context_length" in key:
                try:
                    self._auto_context_limit = int(value)
                    break
                except (TypeError, ValueError):
                    continue
        return self._auto_context_limit

    def _context_limit(self) -> int | None:
        """The effective context budget for this call: an explicit config.context_size
        is a budget the caller committed to and is used as-is; otherwise falls back to
        the auto-detected native_context_length()."""
        if self._config.context_size > 0:
            return self._config.context_size
        return self.native_context_length()

    def _guarded_kwargs(self, *prompt_texts: str) -> dict:
        """Raise SummarizationContextError before any request goes out when the
        estimated prompt size exceeds the model's context window. Otherwise
        return the `options` kwargs that pin Ollama's num_ctx to that window,
        so the server doesn't silently fall back to its own (often smaller)
        default and truncate the prompt with no warning.
        """
        limit = self._context_limit()
        if limit is None:
            return {}
        prompt_tokens = sum(_estimate_tokens(t) for t in prompt_texts)
        needed = prompt_tokens + _OUTPUT_MARGIN_TOKENS
        if needed > limit:
            raise SummarizationContextError(
                f"This transcript needs an estimated {needed} tokens of context "
                f"(~{prompt_tokens} prompt + {_OUTPUT_MARGIN_TOKENS} output margin), but "
                f"model '{self._config.model}' is configured for {limit} tokens. Increase "
                "[summarization] context_size in your config, or summarize a shorter "
                "transcript. (Ollama has no local tokenizer, so this is an estimate.)"
            )
        return {"options": {"num_ctx": limit}}

    def chat(
        self,
        system_prompt: str,
        user_prompt: str,
        json_mode: bool = False,
        json_schema: dict | None = None,
    ) -> str:
        kwargs = self._guarded_kwargs(system_prompt, user_prompt)
        if json_mode:
            kwargs["format"] = "json"
        response = self._client.chat(
            model=self._config.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            **kwargs,
        )
        return clean_response(response["message"]["content"])

    def is_available(self) -> bool:
        try:
            self._client.list()
            return True
        except Exception:
            return False

    def summarize(self, transcript_text: str, language: str | None = None) -> str:
        from clew.summarization.prompts import language_instruction, resolve_template

        system, prompt = resolve_template(self._config.template, self._templates)
        system += language_instruction(language or "")
        user = prompt.format(transcript=transcript_text)

        kwargs = self._guarded_kwargs(system, user)
        response = self._client.chat(
            model=self._config.model,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            **kwargs,
        )
        return clean_response(response["message"]["content"])

    def generate_title(self, summary_text: str) -> str:
        from clew.summarization.prompts import TITLE_PROMPT, TITLE_SYSTEM

        user = TITLE_PROMPT.format(summary=summary_text)
        kwargs = self._guarded_kwargs(TITLE_SYSTEM, user)
        response = self._client.chat(
            model=self._config.model,
            messages=[
                {"role": "system", "content": TITLE_SYSTEM},
                {"role": "user", "content": user},
            ],
            **kwargs,
        )
        return clean_response(response["message"]["content"]).strip()
