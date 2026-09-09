.PHONY: build run test share clean
build:
	bash scripts/build.sh
run: build
	open dist/Ruller.app
test:
	CLANG_MODULE_CACHE_PATH="$${TMPDIR:-/tmp}/ruller-clang-cache" swift test --disable-sandbox
	.build/debug/Ruller --smoke-test
share: build
	bash scripts/package.sh
clean:
	swift package clean
