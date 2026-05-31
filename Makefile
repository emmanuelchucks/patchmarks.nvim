MASON_BIN ?= $(HOME)/.local/share/nvim/mason/bin
STYLUA ?= $(shell command -v stylua 2>/dev/null || printf '%s/stylua' '$(MASON_BIN)')
SELENE ?= $(shell command -v selene 2>/dev/null || printf '%s/selene' '$(MASON_BIN)')
NVIM ?= nvim
LUA_SOURCES := lua plugin tests

.PHONY: format format-check lint test check

format:
	$(STYLUA) $(LUA_SOURCES)

format-check:
	$(STYLUA) --check $(LUA_SOURCES)

lint:
	$(SELENE) .

test:
	$(NVIM) --headless -u NONE -i NONE -c "lua dofile('tests/run.lua')" -c qall!

check: format-check lint test
