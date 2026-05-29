# Coworld Marketboard — development helpers
#
# Primary target: `make check` runs fast `nim check` over all important
# entrypoints so we catch type errors, import problems, and config.nims issues
# before trying to run anything.

NIM ?= nim
NIMFLAGS ?= --hints:off

# All the things we want to keep compiling cleanly.
# These are the actual runnable entrypoints + the main server.
CHECK_TARGETS := \
	src/marketboard.nim \
	src/marketboard/fullmap_viewer.nim \
	src/marketboard/replay_viewer.nim \
	tools/quick_replay.nim \
	tools/quick_market.nim \
	tools/headless_sim.nim \
	tools/batch_market.nim \
	tools/diagnose_bots.nim \
	tools/analyze_legends.nim \
	players/still_forge.nim \
	players/iron_works.nim \
	players/colm.nim \
	players/zorori.nim \
	players/solenne.nim \
	players/rkhenna.nim \
	players/pipitori.nim \
	players/utility.nim

.PHONY: check
check:
	@echo "==> nim check on all entrypoints (using config.nims + nimby nim.cfg)"
	@for t in $(CHECK_TARGETS); do \
		echo "  check $$t"; \
		$(NIM) check $(NIMFLAGS) $$t || exit 1; \
	done
	@echo "==> All clear."

# Optional: also check the test suite
.PHONY: check-tests
check-tests:
	@echo "==> Checking tests/"
	@for t in tests/test_*.nim; do \
		echo "  check $$t"; \
		$(NIM) check $(NIMFLAGS) $$t || exit 1; \
	done
	@echo "==> Tests check OK."

# Convenience: full check including tests
.PHONY: check-all
check-all: check check-tests
