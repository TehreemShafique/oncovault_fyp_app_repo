# oncovault_nlp/tests/conftest.py
import os
import pytest

@pytest.fixture(autouse=True)
def setup_test_environment(monkeypatch):
    """Explicitly enables test tokens via environment variable for tests."""
    monkeypatch.setenv("ALLOW_TEST_TOKENS", "true")
    monkeypatch.setenv("ENVIRONMENT", "test")
