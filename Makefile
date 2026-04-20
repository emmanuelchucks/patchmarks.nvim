STYLUA ?= stylua
SELENE ?= selene
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

