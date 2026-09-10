.PHONY: build run test test-updates share release clean
build:
	bash scripts/build.sh
run: build
	open dist/Ruller.app
test:
	CLANG_MODULE_CACHE_PATH="$${TMPDIR:-/tmp}/ruller-clang-cache" swift test --disable-sandbox
	CLANG_MODULE_CACHE_PATH="$${TMPDIR:-/tmp}/ruller-clang-cache" swiftc -parse-as-library Tests/WindowIntegration/Fixture.swift -o .build/window-fixture
	.build/debug/Ruller --smoke-test
share: build
	bash scripts/package.sh
test-updates:
	python3 scripts/test-updates.py
release:
	bash scripts/release.sh
clean:
	swift package clean
