PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

.PHONY: build install uninstall clean test

build:
	swift build -c release --disable-sandbox

install: build
	install -d "$(BINDIR)"
	install ".build/release/cmdspeak" "$(BINDIR)/cmdspeak"

uninstall:
	rm -f "$(BINDIR)/cmdspeak"

clean:
	rm -rf .build

test:
	swift test
