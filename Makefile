# Copyright (c) 2021-2022, NVIDIA CORPORATION.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BUILD_MULTI_ARCH_IMAGES ?= no
DOCKER ?= docker
BUILDX =
ifeq ($(BUILD_MULTI_ARCH_IMAGES),true)
BUILDX = buildx
endif

##### Global variables #####
include $(CURDIR)/versions.mk

ifeq ($(IMAGE_NAME),)
REGISTRY ?= nvidia
IMAGE_NAME := $(REGISTRY)/k8s-cc-manager
endif

IMAGE_VERSION := $(VERSION)

IMAGE_TAG ?= $(IMAGE_VERSION)-$(DIST)
IMAGE = $(IMAGE_NAME):$(IMAGE_TAG)

OUT_IMAGE_NAME ?= $(IMAGE_NAME)
OUT_IMAGE_VERSION ?= $(IMAGE_VERSION)
OUT_IMAGE_TAG = $(OUT_IMAGE_VERSION)-$(DIST)
OUT_IMAGE = $(OUT_IMAGE_NAME):$(OUT_IMAGE_TAG)

##### Public rules #####
DISTRIBUTIONS := ubi8
DEFAULT_PUSH_TARGET := ubi8

PUSH_TARGETS := $(patsubst %, push-%, $(DISTRIBUTIONS))
BUILD_TARGETS := $(patsubst %, build-%, $(DISTRIBUTIONS))
TEST_TARGETS := $(patsubst %, build-%, $(DISTRIBUTIONS))

.PHONY: $(DISTRIBUTIONS) $(PUSH_TARGETS) $(BUILD_TARGETS) $(TEST_TARGETS)

ifneq ($(BUILD_MULTI_ARCH_IMAGES),true)
include $(CURDIR)/deployments/container/native-only.mk
else
include $(CURDIR)/deployments/container/multi-arch.mk
endif

# For the default push target we also push a short tag equal to the version.
# We skip this for the development release
DEVEL_RELEASE_IMAGE_VERSION ?= devel
PUSH_MULTIPLE_TAGS ?= true
ifeq ($(strip $(OUT_IMAGE_VERSION)),$(DEVEL_RELEASE_IMAGE_VERSION))
PUSH_MULTIPLE_TAGS = false
endif
ifeq ($(PUSH_MULTIPLE_TAGS),true)
push-$(DEFAULT_PUSH_TARGET): push-short
endif

push-%: DIST = $(*)
push-short: DIST = $(DEFAULT_PUSH_TARGET)


build-%: DIST = $(*)
build-%: DOCKERFILE_SUFFIX = $(*)
build-%: DOCKERFILE = $(CURDIR)/deployments/container/Dockerfile.$(DOCKERFILE_SUFFIX)

# Both ubi8 and build-ubi8 trigger a build of the relevant image
$(DISTRIBUTIONS): %: build-%
$(BUILD_TARGETS): build-%:
	DOCKER_BUILDKIT=1 \
		$(DOCKER) $(BUILDX) build --pull \
			$(DOCKER_BUILD_OPTIONS) \
			$(DOCKER_BUILD_PLATFORM_OPTIONS) \
			--tag $(IMAGE) \
			--build-arg BASE_DIST="$(DIST)" \
			--build-arg CUDA_VERSION="$(CUDA_VERSION)" \
			--build-arg VERSION="$(VERSION)" \
			--build-arg CVE_UPDATES="$(CVE_UPDATES)" \
			--build-arg GPU_ADMIN_TOOLS_VERSION="$(GPU_ADMIN_TOOLS_VERSION)" \
			--file $(DOCKERFILE) \
			$(CURDIR)

.PHONY: bump-commit
BUMP_COMMIT := Bump to version $(VERSION)
bump-commit:
	@git log | if [ ! -z "$$(grep -o '$(BUMP_COMMIT)' | sort -u)" ]; then \
		echo "\nERROR: '$(BUMP_COMMIT)' already committed\n"; \
		exit 1; \
	fi
	@git add versions.mk
	@git commit -m "$(BUMP_COMMIT)"
	@echo "Applied the diff:"
	@git --no-pager diff HEAD~1
