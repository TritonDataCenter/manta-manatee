#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2017, Joyent, Inc.
#

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

NODE_PREBUILT_VERSION :=	v0.10.26
NODE_PREBUILT_TAG :=		zone
# Allow building on a SmartOS image other than sdc-multiarch/13.3.1.
NODE_PREBUILT_IMAGE =		b4bdc598-8939-11e3-bea4-8341f6861379

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


include ./tools/mk/Makefile.defs
include ./tools/mk/Makefile.go_prebuilt.defs
include ./tools/mk/Makefile.node_prebuilt.defs
include ./tools/mk/Makefile.node_modules.defs
include ./tools/mk/Makefile.smf.defs

RELEASE_TARBALL :=		manta-manatee-pkg-$(STAMP).tar.bz2
ROOT :=				$(shell pwd)
RELSTAGEDIR :=			/tmp/$(STAMP)

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
	cd $(RELSTAGEDIR) && $(TAR) -jcf $(ROOT)/$(RELEASE_TARBALL) root site
	@rm -rf $(RELSTAGEDIR)

.PHONY: publish
publish: release
	@if [[ -z "$(BITS_DIR)" ]]; then \
		echo "error: 'BITS_DIR' must be set for 'publish' target"; \
		exit 1; \
	fi
	mkdir -p $(BITS_DIR)/manta-manatee
	cp $(ROOT)/$(RELEASE_TARBALL) \
	    $(BITS_DIR)/manta-manatee/$(RELEASE_TARBALL)

.PHONY: pg
pg: all deps/postgresql92/.git deps/postgresql96/.git deps/postgresql11/.git \
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

include ./tools/mk/Makefile.deps
include ./tools/mk/Makefile.go_prebuilt.targ
include ./tools/mk/Makefile.node_prebuilt.targ
include ./tools/mk/Makefile.node_modules.targ
include ./tools/mk/Makefile.smf.targ
include ./tools/mk/Makefile.targ
