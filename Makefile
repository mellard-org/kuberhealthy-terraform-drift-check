# Make does not offer a recursive wildcard function, so here's one:
rwildcard=$(wildcard $1$2) $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2))

SHELL := /bin/bash
NAME = terraform-drift-check
BINARY_NAME = terraform-drift-check
GO := GO111MODULE=on go
GO_NOMOD :=GO111MODULE=off go
MAIN_SRC_FILE=main.go
export REV := $(shell git rev-parse --short HEAD 2> /dev/null || echo 'unknown')
ORG := jenkins-x-plugins
ORG_REPO := $(ORG)/$(NAME)
export ROOT_PACKAGE := github.com/$(ORG_REPO)
export GO_VERSION := 1.15
GO_DEPENDENCIES := $(call rwildcard,pkg/,*.go) $(call rwildcard,cmd/,*.go)

export BRANCH     := $(shell git rev-parse --abbrev-ref HEAD 2> /dev/null  || echo 'unknown')
export BUILD_DATE := $(shell date +%Y%m%d-%H:%M:%S)

# set dev version unless VERSION is explicitly set via environment
export VERSION ?= $(shell echo "$$(git for-each-ref refs/tags/ --count=1 --sort=-version:refname --format='%(refname:short)' 2>/dev/null)-dev+$(REV)" | sed 's/^v//')

# Full build flags used when building binaries. Not used for test compilation/execution.
BUILDFLAGS :=  -ldflags \
  " -X $(ROOT_PACKAGE)/pkg/cmd/version.Version=$(VERSION)\
		-X github.com/jenkins-x/jx-pipeline/pkg/cmd/version.Version=$(VERSION)\
		-X $(ROOT_PACKAGE)/pkg/cmd/version.Revision='$(REV)'\
		-X $(ROOT_PACKAGE)/pkg/cmd/version.Branch='$(BRANCH)'\
		-X $(ROOT_PACKAGE)/pkg/cmd/version.BuildDate='$(BUILD_DATE)'\
		-X $(ROOT_PACKAGE)/pkg/cmd/version.GoVersion='$(GO_VERSION)'\
		$(BUILD_TIME_CONFIG_FLAGS)"

# Some tests expect default values for version.*, so just use the config package values there.
TEST_BUILDFLAGS :=  -ldflags "$(BUILD_TIME_CONFIG_FLAGS)"

.PHONY: list
list: ## List all make targets
	@$(MAKE) -pRrn : -f $(MAKEFILE_LIST) 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' | sort

.PHONY: help
.DEFAULT_GOAL := help
help:
	@grep -h -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: release
release: clean linux test

.PHONY: clean
clean: ## Clean the generated artifacts
	rm -rf build release dist

.PHONY: goreleaser
goreleaser:
	step-go-releaser --organisation=$(ORG) --revision=$(REV) --branch=$(BRANCH) --build-date=$(BUILD_DATE) --go-version=$(GO_VERSION) --root-package=$(ROOT_PACKAGE) --version=$(VERSION)

get-fmt-deps: ## Install test dependencies
	$(GO_NOMOD) get golang.org/x/tools/cmd/goimports

.PHONY: fmt
fmt: importfmt ## Format the code
	$(eval FORMATTED = $(shell $(GO) fmt ./...))
	@if [ "$(FORMATTED)" == "" ]; \
      	then \
      	    echo "All Go files properly formatted"; \
      	else \
      		echo "Fixed formatting for: $(FORMATTED)"; \
      	fi

.PHONY: importfmt
importfmt: get-fmt-deps
	@echo "Formatting the imports..."
	goimports -w $(GO_DEPENDENCIES)

.PHONY: lint
lint: ## Lint the code
	./hack/gofmt.sh
	./hack/linter.sh
	./hack/generate.sh

.PHONY: all
all: fmt lint

.PHONY: test
test: ## Run tests with the "unit" build tag
	KUBECONFIG=/cluster/connections/not/allowed $(GO) test --tags=unit -failfast -short ./... $(TEST_BUILDFLAGS)

.PHONY: build
build: $(GO_DEPENDENCIES) clean ## Build jx-labs binary for current OS
	$(GO) build $(BUILDFLAGS) -o build/$(BINARY_NAME) $(MAIN_SRC_FILE)

.PHONY: linux
linux: ## Build for Linux
	$(GO) build $(BUILDFLAGS) -o build/linux/$(BINARY_NAME) $(MAIN_SRC_FILE)
	chmod +x build/linux/$(BINARY_NAME)


