SHELL := /bin/bash

.PHONY: check client server server-dev server-build server-check app-icon deploy mac-preflight mac-release mac-publish

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

# Cheap readiness check (credentials, version sync, EdDSA↔SUPublicEDKey match).
# Run any time without building anything.
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
