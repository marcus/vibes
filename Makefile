SHELL := /bin/bash

.PHONY: check client server server-dev server-build server-check app-icon deploy mac-bump mac-preflight mac-release mac-publish mac-finish

check: server-check client

client:
	xcodebuild -project client/Vibes.xcodeproj -scheme Vibes -configuration Debug -destination 'platform=macOS' build

server-dev:
	cd server && npm run dev

server-build:
	cd server && npm run build

server: server-build
	cd server && npm start

server-check:
	cd server && npm run check

app-icon:
	@test -n "$(ICON)" || (echo "usage: make app-icon ICON=assets/icons-3.jpeg" >&2; exit 1)
	./scripts/set-app-icon.sh "$(ICON)"

deploy:
	./scripts/deploy-server.sh

# Step 1: bump the version everywhere it lives (project.pbxproj x4, .env.release)
# and scaffold the release notes. BUILD defaults to last published + 1.
#   make mac-bump VERSION=0.12.0 [BUILD=30]
mac-bump:
	@test -n "$(VERSION)" || (echo "usage: make mac-bump VERSION=0.12.0 [BUILD=30]" >&2; exit 1)
	./scripts/bump-version.sh "$(VERSION)" $(BUILD)

# Cheap readiness check (credentials, version sync, build-number advance,
# EdDSA↔SUPublicEDKey match). Run any time without building anything.
mac-preflight:
	scripts/preflight-release.sh

# Full release: preflight runs first (inside release-mac.sh), then build + sign +
# notarize, then sign the appcast and publish.
mac-release:
	VIBES_BUILD_DMG=1 scripts/release-mac.sh
	$(MAKE) mac-publish

# Resume point: sign the staged appcast and publish, reusing the already built +
# notarized artifacts from a prior release-mac.sh run. Use this when a publish-
# time step failed and you don't want to rebuild/re-notarize from scratch.
mac-publish:
	scripts/generate-appcast.sh
	VIBES_BUILD_DMG=1 scripts/publish-mac-release.sh

# Final step, after a successful mac-release: commit the regenerated appcast,
# tag the commit that shipped as v<version>, and push both.
mac-finish:
	scripts/finish-release.sh
