.DEFAULT_GOAL := help
XCODEPROJ = Doni.xcodeproj
SCHEME = Doni
PACKAGES = Support TelegramDesignSystem

help: ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-14s %s\n", $$1, $$2}'

vendor: ## Build tdlib + OpenSSL xcframework from pinned tags (first run: ~20 min)
	./Scripts/build-tdlib.sh all

reference: ## Sparse-fetch Telegram-iOS as a design-token spec (GPL: read-only, never linked)
	./Scripts/fetch-design-reference.sh

project: ## Generate Doni.xcodeproj from project.yml
	xcodegen --spec project.yml

build: project ## Compile for iOS; the build is a warning-free gate
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
		-sdk iphoneos -destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO build

test: ## Run package tests on the host toolchain (no simulator)
	for p in $(PACKAGES); do (cd Packages/$$p && swift test) || exit 1; done

check: build test ## Everything a commit has to survive

clean: ## Remove generated project and host build output
	rm -rf $(XCODEPROJ)
	for p in $(PACKAGES); do rm -rf Packages/$$p/.build; done
