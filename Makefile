NVIM := nvim

.PHONY: all test test_file deps clean

all: test

# Run all tests
test: deps
	@echo "Running tests..."
	$(NVIM) --headless --noplugin -u ./tests/minimal_init.lua -c "lua MiniTest.run()" -c "qa!"

# Run a specific test file
test_file: deps
ifndef FILE
	$(error FILE is required. Usage: make test_file FILE=tests/units/test_skill.lua)
endif
	@echo "Testing file: $(FILE)"
	$(NVIM) --headless --noplugin -u ./tests/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')" -c "qa!"

# Install dependencies
deps: deps/mini.nvim deps/plenary.nvim deps/nvim-treesitter deps/codecompanion.nvim

deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $@
	cd $@ && git checkout 402ee6c6ec8ea44b22330446c8fb4e615fd3953e

deps/plenary.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim $@
	cd $@ && git checkout b9fd5226c2f76c951fc8ed5923d85e4de065e509

deps/nvim-treesitter:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-treesitter/nvim-treesitter $@
	cd $@ && git checkout 4916d6592ede8c07973490d9322f187e07dfefac

deps/codecompanion.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/olimorris/codecompanion.nvim $@
	cd $@ && git checkout 4d8449918e136446c2dabe255241fc6b902e22f1

format:
	stylua tests/ lua/

clean:
	rm -rf deps/
