NAME    := great-theft-auto-7
BUILD   := build
LOVE    ?= love
SOURCES := main.lua conf.lua src lib assets

.PHONY: run check fmt build clean

run:            ## Run the game
	$(LOVE) .

check:          ## Lint with luacheck
	luacheck .

fmt:            ## Format with stylua (if installed)
	stylua .

build: clean    ## Package a .love archive into build/
	mkdir -p $(BUILD)
	zip -9 -r $(BUILD)/$(NAME).love $(SOURCES) -x '*.gitkeep' -x '*/README.md'
	@echo "Built $(BUILD)/$(NAME).love"

clean:
	rm -rf $(BUILD)
