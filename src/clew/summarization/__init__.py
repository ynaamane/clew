from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from clew.config import Config
    from clew.summarization.base import Summarizer


_INSTALL_HINTS = {
    "openai": "uv add 'clew[openai]'",
    "ollama": "uv add 'clew[ollama]'",
}


def create_summarizer(config: Config) -> Summarizer:
    """Create the appropriate summarizer based on config."""
    backend = config.summarization.backend
    if backend == "local":
        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        return LlamaCppSummarizer(config.summarization, config.templates)
    try:
        if backend == "openai":
            from clew.summarization.openai_summarizer import OpenAISummarizer

            return OpenAISummarizer(config.summarization, config.templates)
        else:
            from clew.summarization.ollama_summarizer import OllamaSummarizer

            return OllamaSummarizer(config.summarization, config.templates)
    except ImportError as exc:
        hint = _INSTALL_HINTS.get(backend, f"uv add 'clew[{backend}]'")
        raise ImportError(
            f"The '{backend}' summarization backend requires additional dependencies.\nInstall with: {hint}"
        ) from exc
