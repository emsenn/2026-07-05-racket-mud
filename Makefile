RACKET ?= racket
RACO ?= raco

.DEFAULT_GOAL := test

check:
	@command -v "$(RACKET)" >/dev/null
	@command -v "$(RACO)" >/dev/null
	@$(RACKET) --version
	@$(RACO) help test >/dev/null 2>&1

test: check
	@$(RACO) test test

docs: check
	@if [ -d doc ]; then rm -r -- doc; fi
	@$(RACO) scribble --htmls --dest doc scribblings/racket-mud.scrbl

repl: check
	@$(RACKET) -i main.rkt

example: check
	@$(RACKET) examples/minimal.rkt

.PHONY: check test docs repl example
