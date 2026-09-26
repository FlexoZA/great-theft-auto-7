NAME    := great-theft-auto-7
BUILD   := build
LOVE    ?= love
SOURCES := main.lua conf.lua src lib assets
WORLD   ?= world
IMAGE   ?= gta7-server

.PHONY: run server check fmt build docker clean

run:            ## Run the game
	$(LOVE) .

server:         ## Run a headless dedicated server (docs/dedicated-server.md)
	GTA7_SERVER=1 GTA7_WORLD=$(WORLD) $(LOVE) .

check:          ## Lint with luacheck
	luacheck .

fmt:            ## Format with stylua (if installed)
	stylua .

build: clean    ## Package a .love archive into build/
	mkdir -p $(BUILD)
	zip -9 -r $(BUILD)/$(NAME).love $(SOURCES) -x '*.gitkeep' -x '*/README.md'
	@echo "Built $(BUILD)/$(NAME).love"

docker:         ## Build the dedicated server image
	docker build -t $(IMAGE) .

clean:
	rm -rf $(BUILD)
