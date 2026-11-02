.PHONY: generate test-core open clean

# Generates DJSyncToggle.xcodeproj from project.yml (needs: brew install xcodegen)
generate: Config/Secrets.xcconfig
	xcodegen generate

Config/Secrets.xcconfig:
	cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
	@echo "Created Config/Secrets.xcconfig - fill in DEVELOPMENT_TEAM before building to a device."

# Runs the platform-independent parser/matcher tests (works on macOS and Linux)
test-core:
	swift test --package-path Packages/SetlistCore

open: generate
	open DJSyncToggle.xcodeproj

clean:
	rm -rf DJSyncToggle.xcodeproj Packages/SetlistCore/.build
