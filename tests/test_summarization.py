"""Tests for summarization helpers and backends."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from clew.config import Config, SummarizationConfig, TemplateConfig
from clew.summarization import create_summarizer
from clew.summarization.base import SummarizationContextError
from clew.summarization.prompts import (
    LECTURE_SUMMARY_SYSTEM,
    MEETING_SUMMARY_SYSTEM,
    clean_response,
)


class TestCreateSummarizerMissingDeps:
    """Test that create_summarizer raises helpful errors when optional deps are missing."""

    @pytest.mark.parametrize(
        "backend,module,extra",
        [
            ("ollama", "clew.summarization.ollama_summarizer", "ollama"),
            ("openai", "clew.summarization.openai_summarizer", "openai"),
        ],
    )
    def test_missing_backend_dep(self, backend, module, extra):
        config = Config()
        config.summarization.backend = backend

        with patch.dict("sys.modules", {module: None}), pytest.raises(ImportError, match=f"clew\\[{extra}\\]"):
            create_summarizer(config)


class TestCleanResponse:
    def test_strips_think_tags(self):
        raw = "<think>reasoning about the meeting</think>\n## Summary\nclean"
        assert clean_response(raw) == "## Summary\nclean"

    def test_no_tags_unchanged(self):
        text = "## Summary\nNo thinking here."
        assert clean_response(text) == text

    def test_multiline_thinking_block(self):
        raw = "<think>\nline1\nline2\nline3\n</think>\n## Summary\nActual content"
        assert clean_response(raw) == "## Summary\nActual content"

    def test_case_insensitive(self):
        raw = "<THINK>stuff</THINK>\nresult"
        assert clean_response(raw) == "result"

    def test_empty_think_block(self):
        raw = "<think></think>result"
        assert clean_response(raw) == "result"

    def test_orphaned_close_think_tag(self):
        raw = "1. Analyze\n2. Plan\n</think>\n## Summary\nActual content"
        assert clean_response(raw) == "## Summary\nActual content"


class TestOllamaCustomPrompts:
    """Test that custom prompts via user-defined templates are passed through to Ollama."""

    def test_custom_system_and_user_prompt(self, httpserver):
        import json

        response_body = {
            "message": {"role": "assistant", "content": "Custom summary."},
            "done": True,
        }
        httpserver.expect_request("/api/chat", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(
            host=httpserver.url_for(""),
            backend="ollama",
            model="test-model",
            template="pirate",
        )
        templates = {
            "pirate": TemplateConfig(
                system_prompt="You are a pirate.",
                prompt="Arr! Summarize: {transcript}",
            ),
        }

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config, templates)
        summarizer.summarize("Alice: Hello")

        request = httpserver.log[0][0]
        body = json.loads(request.data)
        assert body["messages"][0]["content"] == "You are a pirate."
        assert body["messages"][1]["content"] == "Arr! Summarize: Alice: Hello"


class TestOpenAICustomPrompts:
    """Test that custom prompts via user-defined templates are passed through to OpenAI."""

    def test_custom_system_and_user_prompt(self, httpserver):
        import json

        response_body = {
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "Custom summary."},
                    "finish_reason": "stop",
                }
            ],
            "model": "test-model",
        }
        httpserver.expect_request("/v1/chat/completions", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(
            host=httpserver.url_for(""),
            backend="openai",
            model="test-model",
            template="pirate",
        )
        templates = {
            "pirate": TemplateConfig(
                system_prompt="You are a pirate.",
                prompt="Arr! Summarize: {transcript}",
            ),
        }

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config, templates)
        summarizer.summarize("Alice: Hello")

        request = httpserver.log[0][0]
        body = json.loads(request.data)
        assert body["messages"][0]["content"] == "You are a pirate."
        assert body["messages"][1]["content"] == "Arr! Summarize: Alice: Hello"


class TestOllamaTemplatePassthrough:
    """Test that built-in templates are resolved correctly by Ollama."""

    def test_lecture_template(self, httpserver):
        import json

        response_body = {
            "message": {"role": "assistant", "content": "Lecture notes."},
            "done": True,
        }
        httpserver.expect_request("/api/chat", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(
            host=httpserver.url_for(""),
            backend="ollama",
            model="test-model",
            template="lecture",
        )

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config)
        summarizer.summarize("Today we discuss photosynthesis.")

        request = httpserver.log[0][0]
        body = json.loads(request.data)
        assert body["messages"][0]["content"] == LECTURE_SUMMARY_SYSTEM
        assert "Today we discuss photosynthesis." in body["messages"][1]["content"]
        assert "Key Concepts" in body["messages"][1]["content"]


class TestOpenAITemplatePassthrough:
    """Test that built-in templates are resolved correctly by OpenAI."""

    def test_lecture_template(self, httpserver):
        import json

        response_body = {
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "Lecture notes."},
                    "finish_reason": "stop",
                }
            ],
            "model": "test-model",
        }
        httpserver.expect_request("/v1/chat/completions", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(
            host=httpserver.url_for(""),
            backend="openai",
            model="test-model",
            template="lecture",
        )

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config)
        summarizer.summarize("Today we discuss photosynthesis.")

        request = httpserver.log[0][0]
        body = json.loads(request.data)
        assert body["messages"][0]["content"] == LECTURE_SUMMARY_SYSTEM
        assert "Today we discuss photosynthesis." in body["messages"][1]["content"]
        assert "Key Concepts" in body["messages"][1]["content"]


class TestOllamaGenerateTitle:
    """Test OllamaSummarizer.generate_title against a mock HTTP server."""

    def test_generate_title(self, httpserver):
        import json

        response_body = {
            "message": {"role": "assistant", "content": "Q3 Budget Review"},
            "done": True,
        }
        httpserver.expect_request("/api/chat", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="ollama", model="test-model")

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config)
        result = summarizer.generate_title("The meeting covered Q3 budget.")

        assert result == "Q3 Budget Review"

        request = httpserver.log[0][0]
        body = json.loads(request.data)
        assert body["messages"][0]["content"] == "You generate short meeting titles."
        assert "Q3 budget" in body["messages"][1]["content"]

    def test_generate_title_strips_think_tags(self, httpserver):
        response_body = {
            "message": {"role": "assistant", "content": "<think>hmm</think>\nBudget Planning"},
            "done": True,
        }
        httpserver.expect_request("/api/chat", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="ollama", model="test-model")

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config)
        result = summarizer.generate_title("summary text")

        assert "<think>" not in result
        assert result == "Budget Planning"


class TestOllamaSummarizer:
    """Test OllamaSummarizer against a mock HTTP server."""

    def test_summarize(self, httpserver):
        response_body = {
            "message": {"role": "assistant", "content": "<think>reasoning</think>\n## Summary\nMeeting went well."},
            "done": True,
        }
        httpserver.expect_request("/api/chat", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="ollama", model="test-model")

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config)
        result = summarizer.summarize("Alice: Hello\nBob: Hi")

        # Verify think tags are cleaned
        assert "<think>" not in result
        assert "## Summary" in result
        assert "Meeting went well." in result

    def test_is_available_success(self, httpserver):
        httpserver.expect_request("/api/tags", method="GET").respond_with_json({"models": []})

        config = SummarizationConfig(host=httpserver.url_for(""), backend="ollama", model="test-model")

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config)
        assert summarizer.is_available() is True

    def test_is_available_failure(self):
        config = SummarizationConfig(host="http://localhost:1", backend="ollama", model="test-model")

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config)
        assert summarizer.is_available() is False


class TestOpenAIGenerateTitle:
    """Test OpenAISummarizer.generate_title against a mock HTTP server."""

    def test_generate_title(self, httpserver):
        import json

        response_body = {
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "Q3 Budget Review"},
                    "finish_reason": "stop",
                }
            ],
            "model": "test-model",
        }
        httpserver.expect_request("/v1/chat/completions", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="openai", model="test-model")

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config)
        result = summarizer.generate_title("The meeting covered Q3 budget.")

        assert result == "Q3 Budget Review"

        request = httpserver.log[0][0]
        body = json.loads(request.data)
        assert body["messages"][0]["content"] == "You generate short meeting titles."
        assert "Q3 budget" in body["messages"][1]["content"]

    def test_generate_title_strips_think_tags(self, httpserver):
        response_body = {
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "<think>hmm</think>\nBudget Planning"},
                    "finish_reason": "stop",
                }
            ],
            "model": "test-model",
        }
        httpserver.expect_request("/v1/chat/completions", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="openai", model="test-model")

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config)
        result = summarizer.generate_title("summary text")

        assert "<think>" not in result
        assert result == "Budget Planning"


class TestOpenAISummarizer:
    """Test OpenAISummarizer against a mock HTTP server."""

    def test_summarize(self, httpserver):
        response_body = {
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "## Summary\nDecisions were made."},
                    "finish_reason": "stop",
                }
            ],
            "model": "test-model",
        }
        httpserver.expect_request("/v1/chat/completions", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="openai", model="test-model")

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config)
        result = summarizer.summarize("Alice: Hello\nBob: Hi")

        assert "## Summary" in result
        assert "Decisions were made." in result

    def test_is_available_success(self, httpserver):
        httpserver.expect_request("/v1/models", method="GET").respond_with_json({"data": [], "object": "list"})

        config = SummarizationConfig(host=httpserver.url_for(""), backend="openai", model="test-model")

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config)
        assert summarizer.is_available() is True

    def test_is_available_failure(self):
        config = SummarizationConfig(host="http://localhost:1", backend="openai", model="test-model")

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config)
        assert summarizer.is_available() is False

    def test_summarize_cleans_think_tags(self, httpserver):
        response_body = {
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "<think>internal reasoning</think>\n## Summary\nCleaned output.",
                    },
                    "finish_reason": "stop",
                }
            ],
            "model": "test-model",
        }
        httpserver.expect_request("/v1/chat/completions", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="openai", model="test-model")

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config)
        result = summarizer.summarize("transcript text")

        assert "<think>" not in result
        assert "## Summary" in result
        assert "Cleaned output." in result


# ---------------------------------------------------------------------------
# LlamaCppSummarizer tests
# ---------------------------------------------------------------------------


def _mock_llm_response(content: str) -> dict:
    """Build a fake llama-cpp create_chat_completion return value."""
    return {"choices": [{"message": {"content": content}}]}


@pytest.fixture()
def mock_llama():
    """Patch llama_cpp.Llama and _ensure_model so no real model is loaded.

    Also stubs tokenize()/n_ctx()/model and the llama_model_n_ctx_train binding
    that _required_ctx() (llama_cpp_summarizer.py) consults before every call --
    without these, .model is an unconfigured MagicMock and the real C binding
    segfaults trying to dereference it as a llama_model_p. Tests that care about
    context sizing use the dedicated llama_stub_factory fixture instead.
    """
    llm_instance = MagicMock()
    llm_instance.n_ctx.return_value = 131072
    llm_instance.model = object()
    llm_instance.tokenize.return_value = [1] * 10
    with (
        patch(
            "clew.summarization.llama_cpp_summarizer._ensure_model",
            return_value="/fake/model.gguf",
        ),
        patch(
            "clew.summarization.llama_cpp_summarizer.Llama",
            return_value=llm_instance,
            create=True,
        ) as llama_cls,
        patch(
            "llama_cpp.Llama",
            llama_cls,
            create=True,
        ),
        patch(
            "llama_cpp.llama_model_n_ctx_train",
            return_value=131072,
            create=True,
        ),
    ):
        yield llm_instance


class TestLlamaCppSummarizer:
    """Test LlamaCppSummarizer.summarize."""

    def test_summarize(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response("## Summary\nMeeting went well.")

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.summarize("Alice: Hello\nBob: Hi")

        assert "## Summary" in result
        assert "Meeting went well." in result
        mock_llama.create_chat_completion.assert_called_once()

    def test_summarize_cleans_think_tags(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response(
            "<think>reasoning</think>\n## Summary\nCleaned."
        )

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.summarize("transcript")

        assert "<think>" not in result
        assert "## Summary" in result
        assert "Cleaned." in result

    def test_is_available(self, mock_llama):
        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        assert summarizer.is_available() is True

    def test_is_available_without_llama_cpp(self):
        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        with patch.dict("sys.modules", {"llama_cpp": None}):
            assert summarizer.is_available() is False


class TestLlamaCppGenerateTitle:
    """Test LlamaCppSummarizer.generate_title."""

    def test_generate_title(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response("Q3 Budget Review")

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.generate_title("The meeting covered Q3 budget.")

        assert result == "Q3 Budget Review"
        call_args = mock_llama.create_chat_completion.call_args
        assert call_args[1]["messages"][0]["content"] == "You generate short meeting titles."
        assert "Q3 budget" in call_args[1]["messages"][1]["content"]

    def test_generate_title_strips_think_tags(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response("<think>hmm</think>\nBudget Planning")

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.generate_title("summary text")

        assert "<think>" not in result
        assert result == "Budget Planning"


class TestLlamaCppChat:
    """Test LlamaCppSummarizer.chat with json_mode and json_schema."""

    def test_chat(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response("Hello!")

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.chat("system", "user")

        assert result == "Hello!"
        call_kwargs = mock_llama.create_chat_completion.call_args[1]
        assert "response_format" not in call_kwargs

    def test_chat_json_mode(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response('{"key": "value"}')

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.chat("system", "user", json_mode=True)

        assert result == '{"key": "value"}'
        call_kwargs = mock_llama.create_chat_completion.call_args[1]
        assert call_kwargs["response_format"] == {"type": "json_object"}

    def test_chat_json_schema_fallback(self, mock_llama):
        """When json_schema format fails, should fall back to json_object."""
        schema = {"type": "object", "properties": {"key": {"type": "string"}}}
        # First call with schema raises, second with json_object succeeds
        mock_llama.create_chat_completion.side_effect = [
            Exception("schema not supported"),
            _mock_llm_response('{"key": "val"}'),
        ]

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.chat("system", "user", json_mode=True, json_schema=schema)

        assert result == '{"key": "val"}'
        assert mock_llama.create_chat_completion.call_count == 2


class TestLlamaCppCustomPrompts:
    """Test that custom prompts via user-defined templates are passed through."""

    def test_custom_system_and_user_prompt(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response("Custom summary.")

        config = SummarizationConfig(backend="local", model="phi-4-mini", template="pirate")
        templates = {
            "pirate": TemplateConfig(
                system_prompt="You are a pirate.",
                prompt="Arr! Summarize: {transcript}",
            ),
        }

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config, templates)
        summarizer.summarize("Alice: Hello")

        call_args = mock_llama.create_chat_completion.call_args
        assert call_args[1]["messages"][0]["content"] == "You are a pirate."
        assert call_args[1]["messages"][1]["content"] == "Arr! Summarize: Alice: Hello"


class TestLlamaCppTemplatePassthrough:
    """Test that built-in templates are resolved correctly."""

    def test_lecture_template(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response("Lecture notes.")

        config = SummarizationConfig(backend="local", model="phi-4-mini", template="lecture")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.summarize("Today we discuss photosynthesis.")

        call_args = mock_llama.create_chat_completion.call_args
        assert call_args[1]["messages"][0]["content"] == LECTURE_SUMMARY_SYSTEM
        assert "Today we discuss photosynthesis." in call_args[1]["messages"][1]["content"]
        assert "Key Concepts" in call_args[1]["messages"][1]["content"]


class TestOllamaLanguageInstruction:
    """Item 7: language=... must reach the system prompt sent to the backend."""

    def test_language_appends_instruction_to_system_prompt(self, httpserver):
        import json

        response_body = {"message": {"role": "assistant", "content": "Resume."}, "done": True}
        httpserver.expect_request("/api/chat", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="ollama", model="test-model")

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config)
        summarizer.summarize("Bonjour tout le monde", language="fr")

        request = httpserver.log[0][0]
        body = json.loads(request.data)
        assert body["messages"][0]["content"].startswith(MEETING_SUMMARY_SYSTEM)
        assert "French" in body["messages"][0]["content"]


class TestOpenAILanguageInstruction:
    """Item 7: language=... must reach the system prompt sent to the backend."""

    def test_language_appends_instruction_to_system_prompt(self, httpserver):
        import json

        response_body = {
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": "Resume."}, "finish_reason": "stop"}],
            "model": "test-model",
        }
        httpserver.expect_request("/v1/chat/completions", method="POST").respond_with_json(response_body)

        config = SummarizationConfig(host=httpserver.url_for(""), backend="openai", model="test-model")

        from clew.summarization.openai_summarizer import OpenAISummarizer

        summarizer = OpenAISummarizer(config)
        summarizer.summarize("Bonjour tout le monde", language="fr")

        request = httpserver.log[0][0]
        body = json.loads(request.data)
        assert body["messages"][0]["content"].startswith(MEETING_SUMMARY_SYSTEM)
        assert "French" in body["messages"][0]["content"]


class TestLlamaCppLanguageInstruction:
    """Item 7: language=... must reach the system prompt sent to the backend."""

    def test_language_appends_instruction_to_system_prompt(self, mock_llama):
        mock_llama.create_chat_completion.return_value = _mock_llm_response("Resume.")

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.summarize("Bonjour tout le monde", language="fr")

        call_args = mock_llama.create_chat_completion.call_args
        assert call_args[1]["messages"][0]["content"].startswith(MEETING_SUMMARY_SYSTEM)
        assert "French" in call_args[1]["messages"][0]["content"]

    def test_no_language_leaves_system_prompt_unchanged(self, mock_llama):
        """No detected language must never force one -- Yanis's decision: infer, never force."""
        mock_llama.create_chat_completion.return_value = _mock_llm_response("Summary.")

        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.summarize("Hello everyone")

        call_args = mock_llama.create_chat_completion.call_args
        assert call_args[1]["messages"][0]["content"] == MEETING_SUMMARY_SYSTEM


@pytest.fixture()
def llama_stub_factory():
    """Patch llama_cpp.Llama with a per-call factory (unlike mock_llama's single fixed
    instance) so context-sizing tests can inspect every construction's n_ctx kwarg and
    control tokenize()/n_ctx_train() independently. Also patches _ensure_model and the
    low-level llama_cpp.llama_model_n_ctx_train binding.

    Yields (constructions, state): constructions is a list of the n_ctx kwarg passed to
    each Llama(...) call, in order; state["tokens"] controls what tokenize() returns
    (as a token-id list) and state["n_ctx_train"] controls the model's reported trained
    context length.
    """
    constructions: list[int] = []
    state = {"tokens": [1] * 10, "n_ctx_train": 131072}
    instances: list[MagicMock] = []

    def _make_instance(*args, **kwargs):
        constructions.append(kwargs.get("n_ctx"))
        instance = MagicMock()
        instance.n_ctx.return_value = kwargs.get("n_ctx")
        instance.model = object()
        instance.tokenize.side_effect = lambda *a, **k: list(state["tokens"])
        instance.create_chat_completion.return_value = _mock_llm_response("Summary.")
        instances.append(instance)
        return instance

    with (
        patch(
            "clew.summarization.llama_cpp_summarizer._ensure_model",
            return_value="/fake/model.gguf",
        ),
        patch("clew.summarization.llama_cpp_summarizer.Llama", side_effect=_make_instance, create=True),
        patch("llama_cpp.Llama", side_effect=_make_instance, create=True),
        patch("llama_cpp.llama_model_n_ctx_train", side_effect=lambda model: state["n_ctx_train"], create=True),
    ):
        yield constructions, state, instances


class TestLlamaCppContextSizing:
    """Item: n_ctx=8192 was hardcoded (llama_cpp_summarizer.py), while
    SummarizationConfig.context_size existed with zero consumers -- the exact
    'dead consumer' pattern documented in ownscribe-pipeline-traps. Real repro:
    2026-08-24_1104 meeting, 36676 measured prompt tokens, crashed against the
    hardcoded 8192 window. phi-4-mini Q4_K_M's real n_ctx_train measured this
    session = 131072."""

    def test_explicit_context_size_is_used_as_is(self, llama_stub_factory):
        constructions, state, _ = llama_stub_factory
        state["tokens"] = [1] * 100  # small need -- explicit config must still win

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=4096)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.summarize("short transcript")

        assert constructions[-1] == 4096

    def test_explicit_context_size_too_small_raises_before_inference(self, llama_stub_factory):
        constructions, state, instances = llama_stub_factory
        state["tokens"] = [1] * 5000  # needs 5000 + margin > 2048

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=2048)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        with pytest.raises(SummarizationContextError):
            summarizer.summarize("a very long transcript")

        assert all(i.create_chat_completion.call_count == 0 for i in instances)
        assert 2048 not in constructions

    def test_explicit_context_size_boundary_exact_fit_succeeds(self, llama_stub_factory):
        constructions, state, _ = llama_stub_factory
        state["tokens"] = [1] * 1000  # needs exactly 1000 + 1024 margin = 2024

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=2024)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.summarize("transcript")  # must not raise

        assert constructions[-1] == 2024

    def test_explicit_context_size_boundary_one_over_raises(self, llama_stub_factory):
        _constructions, state, _ = llama_stub_factory
        state["tokens"] = [1] * 1000  # needs 1000 + 1024 margin = 2024

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=2023)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        with pytest.raises(SummarizationContextError):
            summarizer.summarize("transcript")

    def test_auto_context_size_uses_min_of_need_and_model_limit(self, llama_stub_factory):
        constructions, state, _ = llama_stub_factory
        state["tokens"] = [1] * 2000
        state["n_ctx_train"] = 131072

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=0)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.summarize("transcript")

        assert constructions[-1] == 2000 + 1024

    def test_auto_context_size_need_exceeds_model_limit_raises(self, llama_stub_factory):
        _constructions, state, instances = llama_stub_factory
        state["tokens"] = [1] * 200000
        state["n_ctx_train"] = 131072

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=0)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        with pytest.raises(SummarizationContextError):
            summarizer.summarize("an unsummarizably long transcript")

        assert all(i.create_chat_completion.call_count == 0 for i in instances)

    def test_reproduces_real_meeting_now_succeeds(self, llama_stub_factory):
        """The exact real-world repro: 36676 measured prompt tokens against
        phi-4-mini's measured n_ctx_train of 131072, in auto (0) mode."""
        constructions, state, _ = llama_stub_factory
        state["tokens"] = [1] * 36676
        state["n_ctx_train"] = 131072

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=0)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.summarize("the real 68-minute transcript text")

        assert "Summary" in result
        assert constructions[-1] == 36676 + 1024

    def test_cached_instance_reused_when_it_already_covers_a_smaller_later_need(self, llama_stub_factory):
        constructions, state, _ = llama_stub_factory
        state["tokens"] = [1] * 50000  # first call needs a big context

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=0)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.summarize("big transcript")
        constructions_after_first = list(constructions)

        state["tokens"] = [1] * 50  # second call needs far less
        summarizer.generate_title("short summary")

        assert constructions == constructions_after_first  # no new construction

    def test_cached_small_instance_is_replaced_not_reused_for_a_bigger_later_prompt(self, llama_stub_factory):
        """Item 3's exact concern: a cached small-context instance must never
        silently serve a request it cannot cover."""
        constructions, state, instances = llama_stub_factory
        state["tokens"] = [1] * 50  # first call: small

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=0)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.generate_title("short summary")
        first_instance = instances[-1]

        state["tokens"] = [1] * 50000  # second call: big
        summarizer.summarize("big transcript")

        assert constructions[-1] == 50000 + 1024
        assert first_instance.close.call_count >= 1

    def test_chat_is_sized_but_never_raises_returns_empty_when_too_large(self, llama_stub_factory):
        """chat() feeds search.py's ask() and correction.py, neither of which wraps it
        in a try/except -- it must keep its long-standing 'never raises, returns "" on
        any failure' contract even when the failure is a sizing problem, not just a
        backend error. summarize()/generate_title() are the ones allowed to raise,
        because their pipeline.py callers are built to catch it."""
        _constructions, state, instances = llama_stub_factory
        state["tokens"] = [1] * 5000

        config = SummarizationConfig(backend="local", model="phi-4-mini", context_size=1024)

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        result = summarizer.chat("system prompt", "a very long user prompt")

        assert result == ""
        assert all(i.create_chat_completion.call_count == 0 for i in instances)


class TestLlamaCppClose:
    """Test deterministic cleanup of the local model."""

    def test_close_frees_loaded_model(self, mock_llama):
        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer._get_llm()
        summarizer.close()

        mock_llama.close.assert_called_once()
        assert summarizer._llm is None

    def test_close_is_idempotent(self, mock_llama):
        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer._get_llm()
        summarizer.close()
        summarizer.close()

        mock_llama.close.assert_called_once()

    def test_close_without_load_is_noop(self, mock_llama):
        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer.close()

        mock_llama.close.assert_not_called()

    def test_close_suppresses_errors(self, mock_llama):
        mock_llama.close.side_effect = RuntimeError("boom")
        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        summarizer = LlamaCppSummarizer(config)
        summarizer._get_llm()
        summarizer.close()

        assert summarizer._llm is None

    def test_context_manager_closes_model(self, mock_llama):
        config = SummarizationConfig(backend="local", model="phi-4-mini")

        from clew.summarization.llama_cpp_summarizer import LlamaCppSummarizer

        with LlamaCppSummarizer(config) as summarizer:
            assert summarizer._get_llm() is mock_llama

        mock_llama.close.assert_called_once()


class TestSummarizerCloseContract:
    """Backends without native resources inherit a no-op close + context manager."""

    def test_ollama_close_is_noop_and_context_manager(self):
        config = SummarizationConfig(host="http://localhost:1", backend="ollama", model="x")

        from clew.summarization.ollama_summarizer import OllamaSummarizer

        summarizer = OllamaSummarizer(config)
        with summarizer as entered:
            assert entered is summarizer
        summarizer.close()


class TestEnsureModel:
    """Test _ensure_model with various model specifications."""

    def test_hf_prefix_parsing(self):
        with patch(
            "huggingface_hub.hf_hub_download",
            return_value="/fake/path.gguf",
        ) as mock_dl:
            from clew.summarization.llama_cpp_summarizer import _ensure_model

            result = _ensure_model("hf:myorg/myrepo/model.gguf")

        mock_dl.assert_called_once_with(repo_id="myorg/myrepo", filename="model.gguf")
        assert str(result) == "/fake/path.gguf"

    def test_hf_prefix_invalid(self):
        from clew.summarization.llama_cpp_summarizer import _ensure_model

        with pytest.raises(ValueError, match="Invalid HuggingFace model spec"):
            _ensure_model("hf:noslash")

    def test_registry_lookup(self):
        with patch(
            "huggingface_hub.hf_hub_download",
            return_value="/fake/phi.gguf",
        ) as mock_dl:
            from clew.summarization.llama_cpp_summarizer import _ensure_model

            result = _ensure_model("phi-4-mini")

        mock_dl.assert_called_once_with(
            repo_id="unsloth/Phi-4-mini-instruct-GGUF",
            filename="Phi-4-mini-instruct-Q4_K_M.gguf",
        )
        assert str(result) == "/fake/phi.gguf"

    def test_direct_path(self, tmp_path):
        model_file = tmp_path / "my_model.gguf"
        model_file.touch()

        from clew.summarization.llama_cpp_summarizer import _ensure_model

        result = _ensure_model(str(model_file))
        assert result == model_file

    def test_unknown_model(self):
        from clew.summarization.llama_cpp_summarizer import _ensure_model

        with pytest.raises(FileNotFoundError, match="Unknown model"):
            _ensure_model("nonexistent-model")
