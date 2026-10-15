NAME    := great-theft-auto-7
BUILD   := build
LOVE    ?= love
SOURCES := main.lua conf.lua CHANGELOG.md src lib assets

.PHONY: run check audit fmt build clean

run:            ## Run the game
	$(LOVE) .

check:          ## Lint with luacheck
	luacheck .

audit:          ## Rate this branch out of 10 against origin/staging (docs/audit.md)
	luajit tools/audit/run.lua --md build/audit/report.md

fmt:            ## Format with stylua (if installed)
	stylua .

build: clean    ## Package a .love archive into build/
	mkdir -p $(BUILD)
	zip -9 -r $(BUILD)/$(NAME).love $(SOURCES) -x '*.gitkeep' -x '*/README.md'
	@echo "Built $(BUILD)/$(NAME).love"

clean:
	rm -rf $(BUILD)
