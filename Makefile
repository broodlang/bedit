# brood-edit (myedit) — build & install the standalone `bedit` editor binary.
#
# `nest release` bundles the project (manifest + every src/**) onto the
# GUI-enabled `brood` runtime embedded in the installed `nest`, producing one
# self-contained executable that runs from any directory with no interpreter,
# project dir, or source alongside it.
#
# Requires a GUI-enabled `nest` on PATH — build it in ../brood:
#     ./configure --with-gui && make install
#
# Usage:
#     make install                 # -> ~/.local/bin/bedit
#     make install PREFIX=/usr/local
#     make install NAME=myedit     # install under a different command name
#     make build                   # a local ./bedit, without installing
#     make uninstall
#     make test / make check

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
NAME   ?= bedit

.PHONY: all build install uninstall test check clean

all: build

# A local standalone binary at ./$(NAME) (gitignored), without installing.
build:
	nest release -o $(NAME)

# Bundle straight into $(BINDIR) (default ~/.local/bin/bedit — put it on PATH).
install:
	mkdir -p $(DESTDIR)$(BINDIR)
	nest release -o $(DESTDIR)$(BINDIR)/$(NAME)
	@echo "installed $(NAME) -> $(DESTDIR)$(BINDIR)/$(NAME)"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(NAME)

test:
	nest test

check:
	nest check

clean:
	rm -f $(NAME)
