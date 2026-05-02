PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
BIN ?= ydl
INSTALL ?= install

.PHONY: help test install diff-installed

help:
	@printf '%s\n' \
		'Targets:' \
		'  make test            Run local tests with stubbed external tools' \
		'  make install         Install ./ydl to $(BINDIR)/$(BIN)' \
		'  make diff-installed  Compare ./ydl with $(BINDIR)/$(BIN)'

test:
	./tests/run.zsh

install:
	$(INSTALL) -m 755 ./ydl "$(BINDIR)/$(BIN)"

diff-installed:
	diff -u ./ydl "$(BINDIR)/$(BIN)"
