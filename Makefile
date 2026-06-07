SHELL := /bin/bash

.PHONY: check client server server-dev server-build server-check deploy

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

deploy:
	./scripts/deploy-server.sh
