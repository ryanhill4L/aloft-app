.PHONY: help proto proto-lint dev-backend test test-backend test-backend-db test-strap \
        ios-project build-ios run-ios sim shots infra-init infra-plan infra-up

IOS_SIMULATOR ?= iPhone 17 Pro
IOS_BUNDLE_ID ?= invalid.aloft.local
DERIVED := ios/build
APP := $(DERIVED)/Build/Products/Debug-iphonesimulator/Aloft.app

PURPLE := \033[0;35m
BLUE := \033[0;34m
GREEN := \033[0;32m
RESET := \033[0m

help:
	@echo "proto            lint and generate Go + Swift from proto/"
	@echo "dev-backend      run the Go API on :9090 (reads backend/.env)"
	@echo "test             strap package tests + backend unit tests"
	@echo "test-backend-db  backend store tests against ALOFT_TEST_DATABASE_URL"
	@echo "infra-init       set up Terraform against the state bucket (see infra/README.md)"
	@echo "infra-plan       show what infra-up would change on Cloud Run"
	@echo "infra-up         build, push, and deploy the API to Cloud Run"
	@echo "ios-project      regenerate ios/Aloft.xcodeproj from ios/project.yml"
	@echo "run-ios          build, install, and launch on IOS_SIMULATOR"

# ---------------------------------------------------------------------------
# Proto (source of truth for the API)
# ---------------------------------------------------------------------------

proto: proto-lint
	@echo "$(PURPLE)[proto]$(RESET) generating"
	@PATH="$$HOME/.local/bin:$$HOME/go/bin:$$PATH" buf generate

proto-lint:
	@buf lint

# ---------------------------------------------------------------------------
# Backend
# ---------------------------------------------------------------------------

dev-backend:
	@echo "$(BLUE)[backend]$(RESET) http://localhost:9090"
	@cd backend && go run .

test-backend:
	@cd backend && go vet ./... && go test ./...

test-backend-db:
	@cd backend && set -a && . ./.env && set +a && ALOFT_TEST_DATABASE_URL="$${ALOFT_TEST_DATABASE_URL:-$$DATABASE_URL}" go test -count=1 ./internal/store/

# ---------------------------------------------------------------------------
# Infra (Cloud Run, see infra/README.md)
# ---------------------------------------------------------------------------

infra-init:
	@cd infra && terraform init -backend-config=backend.hcl

infra-plan:
	@cd infra && terraform plan

infra-up:
	@echo "$(BLUE)[infra]$(RESET) deploying to Cloud Run"
	@cd infra && terraform apply

# ---------------------------------------------------------------------------
# iOS
# ---------------------------------------------------------------------------

test-strap:
	@cd ios/Packages/AloftStrap && swift test

test: test-strap test-backend

ios-project:
	@cd ios && xcodegen generate

build-ios: ios-project
	@echo "$(GREEN)[ios]$(RESET) building"
	@xcodebuild -project ios/Aloft.xcodeproj -scheme Aloft -configuration Debug \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED) build | tail -1

sim:
	@xcrun simctl boot "$(IOS_SIMULATOR)" 2>/dev/null || true
	@open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null || true

run-ios: build-ios
	@xcrun simctl boot "$(IOS_SIMULATOR)" 2>/dev/null || true
	@xcrun simctl bootstatus "$(IOS_SIMULATOR)" -b >/dev/null
	@xcrun simctl install "$(IOS_SIMULATOR)" $(APP)
	@xcrun simctl launch "$(IOS_SIMULATOR)" $(IOS_BUNDLE_ID) $(ARGS)

# Debug builds only: open one screen with sample data and no network, e.g.
#   make run-ios ARGS="-AloftPreview home"
# Screens: landing signup signin verify name basics band health crew nights home home-empty
