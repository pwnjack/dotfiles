# Native Waybar workspace module (cffi/workspaces).
#
# Out-of-tree only: the repository is public and must never hold build
# output, so BUILD is required. build-workspaces.sh and the test suite both
# pass a temporary directory.
#
#   make BUILD=/tmp/ws /tmp/ws/workspaces.so
#   make BUILD=/tmp/ws test

ifndef BUILD
$(error BUILD is required, e.g. make BUILD=/tmp/workspaces-build)
endif

# The repository is public; refuse a BUILD that would put output inside it.
REPO_ROOT := $(or $(shell git -C $(CURDIR) rev-parse --show-toplevel 2>/dev/null),$(CURDIR))
ifneq ($(filter $(REPO_ROOT) $(REPO_ROOT)/%,$(abspath $(BUILD))),)
$(error BUILD must be outside the repository)
endif

.DEFAULT_GOAL := test

CC ?= cc
PKGS := gtk+-3.0 json-glib-1.0
# CFLAGS is the overridable optimisation/debug part; the module's required
# flags live in private variables so a command-line CFLAGS cannot drop them.
CFLAGS ?= -O2 -g
WS_CFLAGS := -std=gnu11 -Wall -Wextra -fPIC $(shell pkg-config --cflags $(PKGS))
# -Werror is for the test suite; build-workspaces.sh passes WS_WERROR= so a
# newer compiler's new warning cannot break an end-user install.
WS_WERROR ?= -Werror
WS_LDLIBS := $(shell pkg-config --libs $(PKGS)) -lm

HEADERS := $(wildcard *.h)
LIB_SRC := model.c anim.c render.c hypr.c module.c
TEST_SRC := $(wildcard test/test_*.c)
TESTS := $(patsubst test/%.c,$(BUILD)/%,$(TEST_SRC))

$(BUILD):
	mkdir -p $@

$(BUILD)/workspaces.so: $(LIB_SRC) $(HEADERS) | $(BUILD)
	$(CC) $(WS_CFLAGS) $(WS_WERROR) $(CFLAGS) -fvisibility=hidden -shared -o $@ $(LIB_SRC) $(WS_LDLIBS) $(LDLIBS)

# Each test links the library sources it needs; hypr's retry is shortened so
# the reconnect test runs in milliseconds.
$(BUILD)/test_%: test/test_%.c test/check.h $(LIB_SRC) $(HEADERS) | $(BUILD)
	$(CC) $(WS_CFLAGS) $(WS_WERROR) $(CFLAGS) -DHYPR_RETRY_MS=50 -DHYPR_TEST -I. -o $@ $< $(filter-out module.c,$(LIB_SRC)) $(WS_LDLIBS) $(LDLIBS) -ldl

test: $(TESTS) $(BUILD)/workspaces.so
	@set -e; for t in $(TESTS); do "$$t" "$(BUILD)"; done

.PHONY: test
