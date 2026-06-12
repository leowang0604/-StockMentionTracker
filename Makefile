PYTHON ?= /Users/leowang/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
CASE ?=

.PHONY: setup-python test-scanner replay
setup-python:
	$(PYTHON) -m pip install -r scanner/requirements.txt

test-scanner:
	$(PYTHON) -m unittest scanner.tests.test_validator_regressions -v

replay:
	$(PYTHON) scanner/tools/replay_scan_fixture.py $(CASE)
