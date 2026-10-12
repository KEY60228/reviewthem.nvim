.PHONY: test

# Headless functional checks. Requires Neovim >= 0.10.0 on PATH.
test:
	nvim --headless -l tests/inline_comments_spec.lua
