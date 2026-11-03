.DEFAULT_GOAL := help
XCODEPROJ = Doni.xcodeproj
SCHEME = Doni
PACKAGES = Support TelegramDesignSystem TdSession

help: ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-14s %s\n", $$1, $$2}'

vendor: ## Build tdlib + OpenSSL xcframework from pinned tags (first run: ~20 min)
	./Scripts/build-tdlib.sh all

reference: ## Sparse-fetch Telegram-iOS as a design-token spec (GPL: read-only, never linked)
	./Scripts/fetch-design-reference.sh

project: Config/Tdlib.xcconfig Config/Signing.xcconfig ## Generate Doni.xcodeproj from project.yml
	@DONI_TEAM_ID=$$(sed -n 's/^DONI_TEAM_ID=//p' Config/Signing.xcconfig); \
	export DONI_TEAM_ID; \
	xcodegen --spec project.yml

# project.yml points configFiles at these, so they have to exist even on a
# fresh clone. cp -n: never clobber values that are already there.
Config/Tdlib.xcconfig:
	@cp -n Config/Tdlib.example.xcconfig $@ \
		&& echo ">> created $@ from the example — put your api_id/api_hash in it (it is gitignored)" \
		|| echo ">> $@ present"

Config/Signing.xcconfig:
	@cp -n Config/Signing.example.xcconfig $@ \
		&& echo ">> created $@ from the example — put your Apple team id in it (it is gitignored)" \
		|| echo ">> $@ present"

build: project ## Compile for iOS; the build is a warning-free gate
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
		-sdk iphoneos -destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO build

device: project ## Compile signed for real hardware with your free personal team
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
		-sdk iphoneos -destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=YES \
		-allowProvisioningUpdates build

test: ## Run package tests on the host toolchain (no simulator)
	for p in $(PACKAGES); do (cd Packages/$$p && swift test) || exit 1; done

check: build test ## Everything a commit has to survive

clean: ## Remove generated project and host build output
	rm -rf $(XCODEPROJ)
	for p in $(PACKAGES); do rm -rf Packages/$$p/.build; done
