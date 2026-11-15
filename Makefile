SHELLCHECK ?= shellcheck
SCRIPTS := install.sh bin/7z-context-helper tests/run.sh tests/lib.sh tests/helper_tests.sh tests/install_tests.sh tests/fixtures/make_fixtures.sh

.PHONY: test lint check install uninstall status

test:
	SHELLCHECK=$(SHELLCHECK) ./tests/run.sh

lint:
	$(SHELLCHECK) -x -S style $(SCRIPTS)

check: lint test

install:
	./install.sh install

uninstall:
	./install.sh uninstall

status:
	./install.sh status
