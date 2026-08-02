# bedit (bedit) — build & install the standalone `bedit` editor binary.
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
#     make install                 # -> ~/.local/bin/bedit + desktop entry & icon
#     make install PREFIX=/usr/local
#     make install NAME=bedit     # install under a different command name
#     make build                   # a local ./bedit, without installing
#     make install-desktop         # just the desktop entry + icon
#     make uninstall
#     make test / make check
#     make drive                   # live pty drivers (tools/README.md)

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
NAME   ?= bedit

# The desktop identity (assets/README.md). APPID is the application id the window
# declares — src/main.blsp's `:app-id` — and the desktop entry MUST be named after
# it, since that name is the only thing tying the running window to its icon. It is
# therefore independent of NAME (the command), which may be renamed freely.
APPID   ?= bedit
DATADIR ?= $(PREFIX)/share
APPSDIR ?= $(DATADIR)/applications
ICONDIR ?= $(DATADIR)/icons/hicolor/scalable/apps

.PHONY: all build install install-bin install-desktop uninstall test drive check clean

all: build

# A local standalone binary at ./$(NAME) (gitignored), without installing.
build:
	nest release -o $(NAME)

# The whole desktop app: the binary, then the entry + icon that name it. In that
# order — an entry installed ahead of a `nest release` that then fails would point at
# a binary that isn't there.
install: install-bin install-desktop

# Bundle straight into $(BINDIR) (default ~/.local/bin/bedit — put it on PATH).
install-bin:
	mkdir -p $(DESTDIR)$(BINDIR)
	nest release -o $(DESTDIR)$(BINDIR)/$(NAME)
	@echo "installed $(NAME) -> $(DESTDIR)$(BINDIR)/$(NAME)"

# The desktop entry + icon: what makes the window show up in the dash / alt-tab as
# bedit with its own icon instead of an unidentified window with the generic
# fallback one. `Exec=` is rewritten to the *installed path* — a desktop launch does
# not inherit a login shell's PATH (a GNOME session's is often missing ~/.local/bin),
# so the bare command in the committed file would launch nothing. DESTDIR is a
# staging root, never part of the installed path, so it is left out here.
install-desktop:
	mkdir -p $(DESTDIR)$(APPSDIR) $(DESTDIR)$(ICONDIR)
	install -m644 assets/$(APPID).svg $(DESTDIR)$(ICONDIR)/$(APPID).svg
	sed 's|^Exec=bedit|Exec=$(BINDIR)/$(NAME)|' assets/$(APPID).desktop \
	  > $(DESTDIR)$(APPSDIR)/$(APPID).desktop
	chmod 644 $(DESTDIR)$(APPSDIR)/$(APPID).desktop
	$(refresh-desktop-caches)
	@echo "installed $(APPID).desktop + icon -> $(DESTDIR)$(APPSDIR)"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(NAME)
	rm -f $(DESTDIR)$(APPSDIR)/$(APPID).desktop $(DESTDIR)$(ICONDIR)/$(APPID).svg
	$(refresh-desktop-caches)

# Make the desktop pick up an entry/icon that just appeared or vanished, without a
# re-login. Both tools are optional and both are advisory — a desktop with neither
# still finds the files by scanning — so neither failure is fatal (`-`). Shared by
# install-desktop and uninstall so the two can't drift.
define refresh-desktop-caches
	-command -v update-desktop-database >/dev/null && update-desktop-database $(DESTDIR)$(APPSDIR)
	-command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf $(DESTDIR)$(DATADIR)/icons/hicolor
endef

test:
	nest test

# Drive the REAL editor on a pty and assert on what it paints — the wiring `nest test`
# cannot see (a key reaching its command, an async sandbox reply, a buffer actually gone
# from the screen). See tools/README.md. Slow by nature: each one starts an editor.
drive:
	@for d in tools/drive_*.py; do echo "== $$d"; python3 $$d || exit 1; done

check:
	nest check

clean:
	rm -f $(NAME)
