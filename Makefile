NAME    := great-theft-auto-7
BUILD   := build
LOVE    ?= love
SOURCES := main.lua conf.lua CHANGELOG.md src lib assets

.PHONY: run check audit wiki wiki-portraits fmt build clean

run:            ## Run the game
	$(LOVE) .

check:          ## Lint with luacheck
	luacheck .

audit:          ## Rate this branch out of 10 against origin/staging (docs/audit.md)
	luajit tools/audit/run.lua --md build/audit/report.md

wiki:           ## Write the wiki's pages in docs/wiki from the game's code (docs/wiki.md)
	luajit tools/wiki/run.lua

wiki-portraits: ## Draw the wiki's missing enemy portraits (WIKI_ALL=1 for all, WIKI_ONLY="city karen" for some)
	rm -rf $(BUILD)/wiki-love && mkdir -p $(BUILD)/wiki-love
	ln -s ../../tools/wiki/portraits/main.lua ../../tools/wiki/portraits/conf.lua ../../src ../../lib ../../assets \
		$(BUILD)/wiki-love/
	$(LOVE) $(BUILD)/wiki-love
	luajit tools/wiki/run.lua

fmt:            ## Format with stylua (if installed)
	stylua .

build: clean    ## Package a .love archive into build/
	mkdir -p $(BUILD)
	zip -9 -r $(BUILD)/$(NAME).love $(SOURCES) -x '*.gitkeep' -x '*/README.md'
	@echo "Built $(BUILD)/$(NAME).love"

clean:
	rm -rf $(BUILD)
