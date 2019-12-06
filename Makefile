#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2019 Joyent, Inc.
#

NAME = manta-manatee

#
# Tools
#
TAR = tar
UNAME := $(shell uname)

ifeq ($(UNAME), SunOS)
	TAR = gtar
endif

#
# Files
#
SMF_MANIFESTS_IN =		smf/manifests/backupserver.xml.in \
				smf/manifests/sitter.xml.in \
				smf/manifests/snapshotter.xml.in \
				smf/manifests/pg_prefaulter.xml.in

#
# Variables
#

NODE_PREBUILT_VERSION :=	v0.10.48
NODE_PREBUILT_TAG :=		zone
# sdc-minimal-multiarch-lts@15.4.1
NODE_PREBUILT_IMAGE =		18b094b0-eb01-11e5-80c1-175dac7ddf02

#
# The PostgreSQL prefaulter program is implemented in Go, so we will need
# an appropriate Go toolchain to build it.  In addition, we will need to
# know what the fully qualified import path is called in order to arrange
# the GOPATH directory in the way the toolchain expects.
#
GO_PREBUILT_VERSION =		1.9.2
PG_PREFAULTER_IMPORT =		github.com/joyent/pg_prefaulter
PG_PREFAULTER =			pg_prefaulter

CLEAN_FILES +=			$(PG_PREFAULTER)

ENGBLD_USE_BUILDIMAGE =		true
ENGBLD_REQUIRE :=		$(shell git submodule update --init deps/eng)
include ./deps/eng/tools/mk/Makefile.defs
TOP ?= $(error Unable to access eng.git submodule Makefiles.)

include ./deps/eng/tools/mk/Makefile.go_prebuilt.defs
include ./deps/eng/tools/mk/Makefile.node_prebuilt.defs
include ./deps/eng/tools/mk/Makefile.agent_prebuilt.defs
include ./deps/eng/tools/mk/Makefile.node_modules.defs
include ./deps/eng/tools/mk/Makefile.smf.defs

RELEASE_TARBALL :=		$(NAME)-pkg-$(STAMP).tar.gz
ROOT :=				$(shell pwd)
RELSTAGEDIR :=			/tmp/$(NAME)-$(STAMP)

BASE_IMAGE_UUID = 04a48d7d-6bb5-4e83-8c3b-e60a99e0f48f
BUILDIMAGE_NAME = mantav2-postgres
BUILDIMAGE_DESC	= Manta manatee
BUILDIMAGE_PKGSRC = lz4-131nb1
AGENTS		= amon config registrar waferlock

#
# Repo-specific targets
#
.PHONY: all
all: $(SMF_MANIFESTS) $(STAMP_NODE_MODULES) $(PG_PREFAULTER) manta-scripts

.PHONY: manta-scripts
manta-scripts: deps/manta-scripts/.git
	mkdir -p $(BUILD)/scripts
	cp deps/manta-scripts/*.sh $(BUILD)/scripts

.PHONY: release
release: all deps docs pg
	@echo "Building $(RELEASE_TARBALL)"
	@mkdir -p $(RELSTAGEDIR)/root/opt/smartdc/manatee/deps
	@mkdir -p $(RELSTAGEDIR)/root/opt/smartdc/boot
	@mkdir -p $(RELSTAGEDIR)/site
	@touch $(RELSTAGEDIR)/site/.do-not-delete-me
	@mkdir -p $(RELSTAGEDIR)/root
	cp -r \
	    $(ROOT)/build \
	    $(ROOT)/bin \
	    $(ROOT)/node_modules \
	    $(ROOT)/package.json \
	    $(ROOT)/pg_dump \
	    $(ROOT)/sapi_manifests \
	    $(ROOT)/smf \
	    $(ROOT)/etc \
	    $(RELSTAGEDIR)/root/opt/smartdc/manatee/
	cp $(PG_PREFAULTER) $(RELSTAGEDIR)/root/opt/smartdc/manatee/bin/
	cp -r $(ROOT)/deps/manta-scripts \
	    $(RELSTAGEDIR)/root/opt/smartdc/manatee/deps
	mkdir -p $(RELSTAGEDIR)/root/opt/smartdc/boot/scripts
	cp -R $(RELSTAGEDIR)/root/opt/smartdc/manatee/build/scripts/* \
	    $(RELSTAGEDIR)/root/opt/smartdc/boot/scripts/
	cp -R $(ROOT)/boot/* \
	    $(RELSTAGEDIR)/root/opt/smartdc/boot/
	cd $(RELSTAGEDIR) && $(TAR) -I pigz -cf $(ROOT)/$(RELEASE_TARBALL) root site
	@rm -rf $(RELSTAGEDIR)

.PHONY: publish
publish: release
	mkdir -p $(ENGBLD_BITS_DIR)/$(NAME)
	cp $(ROOT)/$(RELEASE_TARBALL) \
	    $(ENGBLD_BITS_DIR)/$(NAME)/$(RELEASE_TARBALL)

.PHONY: pg
pg: all deps/postgresql92/.git deps/postgresql96/.git deps/postgresql12/.git \
    deps/pg_repack/.git
	$(MAKE) -C node_modules/manatee -f Makefile.postgres \
	    RELSTAGEDIR="$(RELSTAGEDIR)" \
	    DEPSDIR="$(ROOT)/deps"

#
# Link the "pg_prefaulter" submodule into the correct place within our
# project-local GOPATH, then build the binary.
#
$(PG_PREFAULTER): deps/pg_prefaulter/.git $(STAMP_GO_TOOLCHAIN)
	$(GO) version
	mkdir -p $(GO_GOPATH)/src/$(dir $(PG_PREFAULTER_IMPORT))
	rm -f $(GO_GOPATH)/src/$(PG_PREFAULTER_IMPORT)
	ln -s $(ROOT)/deps/pg_prefaulter \
	    $(GO_GOPATH)/src/$(PG_PREFAULTER_IMPORT)
	$(GO) build \
	    -ldflags "-X main.commit=$(shell cd $(ROOT)/deps/pg_prefaulter && \
	    git describe --tags --always) \
	    -X main.date=$(shell /usr/bin/date -u +%FT%TZ)" \
	    -o $@ $(PG_PREFAULTER_IMPORT)

include ./deps/eng/tools/mk/Makefile.deps
include ./deps/eng/tools/mk/Makefile.go_prebuilt.targ
include ./deps/eng/tools/mk/Makefile.node_prebuilt.targ
include ./deps/eng/tools/mk/Makefile.agent_prebuilt.targ
include ./deps/eng/tools/mk/Makefile.node_modules.targ
include ./deps/eng/tools/mk/Makefile.smf.targ
include ./deps/eng/tools/mk/Makefile.targ
