include .bingo/Variables.mk
FILES_TO_FMT      ?= $(shell find . -path ./vendor -prune -o -name '*.go' -print)

GO111MODULE       ?= on
export GO111MODULE

GOBIN             ?= $(firstword $(subst :, ,${GOPATH}))/bin

# Tools.
GIT               ?= $(shell which git)

# Support gsed on OSX (installed via brew), falling back to sed. On Linux
# systems gsed won't be installed, so will use sed as expected.
SED ?= $(shell which gsed 2>/dev/null || which sed)

define require_clean_work_tree
	@git update-index -q --ignore-submodules --refresh

    @if ! git diff-files --quiet --ignore-submodules --; then \
        echo >&2 "cannot $1: you have unstaged changes."; \
        git diff-files --name-status -r --ignore-submodules -- >&2; \
        echo >&2 "Please commit or stash them."; \
        exit 1; \
    fi

    @if ! git diff-index --cached --quiet HEAD --ignore-submodules --; then \
        echo >&2 "cannot $1: your index contains uncommitted changes."; \
        git diff-index --cached --name-status -r --ignore-submodules HEAD -- >&2; \
        echo >&2 "Please commit or stash them."; \
        exit 1; \
    fi

endef

help: ## Displays help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: all
all: format build

.PHONY: build
build: ## Build bingo.
	@echo ">> Building bingo"
	@go install github.com/bwplotka/bingo

.PHONY: deps
deps: ## Ensures fresh go.mod and go.sum.
	@go mod tidy
	@go mod verify

.PHONY: check-comments
check-comments: ## Checks Go code comments if they have trailing period (excludes protobuffers and vendor files). Comments with more than 3 spaces at beginning are omitted from the check, example: '//    - foo'.
	@echo ">> checking Go comments trailing periods\n\n\n"
	@./scripts/build-check-comments.sh

.PHONY: format
format: ## Formats Go code including imports and cleans up white noise.
format: $(GOIMPORTS)
	@echo ">> formatting code"
	@$(GOIMPORTS) -w $(FILES_TO_FMT)
	@SED_BIN="$(SED)" scripts/cleanup-white-noise.sh $(FILES_TO_FMT)

.PHONY: test
test: ## Runs all Go unit tests.
test:
	@echo ">> running unit tests"
	@go test $(shell go list ./... | grep -v /vendor/);

.PHONY: check-git
check-git:
ifneq ($(GIT),)
	@test -x $(GIT) || (echo >&2 "No git executable binary found at $(GIT)."; exit 1)
else
	@echo >&2 "No git binary found."; exit 1
endif

# PROTIP:
# Add
#      --cpu-profile-path string   Path to CPU profile output file
#      --mem-profile-path string   Path to memory profile output file
# to debug big allocations during linting.
lint: ## Runs various static analysis against our code.
lint: $(FAILLINT) $(GOLANGCI_LINT) $(COPYRIGHT) $(MISSPELL) format check-git deps
	$(call require_clean_work_tree,"detected not clean master before running lint")
	@echo ">> verifying modules being imported"
	@$(FAILLINT) -paths "errors=github.com/pkg/errors" ./...
	@$(FAILLINT) -paths "fmt.{Print,PrintfPrintln,Sprint}" -ignore-tests ./...
	@echo ">> examining all of the Go files"
	@go vet -stdmethods=false ./...
	@echo ">> linting all of the Go files GOGC=${GOGC}"
	@$(GOLANGCI_LINT) run
	@echo ">> detecting misspells"
	@find . -type f | grep -v vendor/ | grep -vE '\./\..*' | xargs $(MISSPELL) -error
	@echo ">> detecting white noise"
	@find . -type f \( -name "*.md" -o -name "*.go" \) | SED_BIN="$(SED)" xargs scripts/cleanup-white-noise.sh
	@echo ">> ensuring Copyright headers"
	@$(COPYRIGHT)
	$(call require_clean_work_tree,"detected white noise or/and files without copyright; run 'make lint' file and commit changes.")
