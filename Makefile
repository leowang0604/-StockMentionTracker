PYTHON ?= /Users/leowang/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
CASE ?=

.PHONY: replay
replay:
	$(PYTHON) scanner/tools/replay_scan_fixture.py $(CASE)
