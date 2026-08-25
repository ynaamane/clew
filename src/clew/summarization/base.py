"""Abstract base class for summarizers."""

from __future__ import annotations

import abc


class SummarizationContextError(RuntimeError):
    """Raised when a prompt cannot fit in the backend's context window.

    Callers must be able to catch this specifically and report it before any
    inference is attempted -- it signals a sizing problem, not a backend failure.
    """


class Summarizer(abc.ABC):
    """Base class for summarization backends."""

    @abc.abstractmethod
    def summarize(self, transcript_text: str, language: str | None = None) -> str:
        """Summarize a transcript and return the summary text.

        When language (an ISO 639-1 code, e.g. "fr") is given, the summary is
        written in that language. An unset language never forces one.
        """

    @abc.abstractmethod
    def generate_title(self, summary_text: str) -> str:
        """Generate a short meeting title from a summary."""

    @abc.abstractmethod
    def chat(
        self,
        system_prompt: str,
        user_prompt: str,
        json_mode: bool = False,
        json_schema: dict | None = None,
    ) -> str:
        """Send a chat completion request and return the response text."""

    @abc.abstractmethod
    def is_available(self) -> bool:
        """Check if the summarization backend is reachable."""

    def native_context_length(self) -> int | None:
        """Best-effort context window the underlying model itself supports, or None
        when the backend has no way to know (a remote API with no introspection, or a
        lookup that failed). Concrete with a None default -- not abstract -- so every
        existing subclass, including duck-typed test fakes that don't inherit from
        Summarizer at all, keeps working without edits; only a backend that knows its
        own limit overrides it. Independent of any explicit context_size override a
        caller may have configured -- callers apply that separately."""
        return None

    def close(self) -> None:  # noqa: B027 — intentional optional hook, not abstract
        """Release any native resources. No-op by default; must be idempotent."""

    def __enter__(self) -> Summarizer:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()
