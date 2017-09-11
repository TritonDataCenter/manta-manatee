#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2017, Joyent, Inc.
#

PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export PS4
set -o xtrace

#
# Disable the protection against RST reflection denial-of-service attacks.
# In order for system liveliness when PostgreSQL is not running, we need to
# be able to send a RST for every inbound connection to a closed port.  This
# is only safe because we run Manatee on an isolated network.
#
# The long-term stability of this interface is not completely clear, so we
# ignore the exit status of ndd(1M).  To do otherwise may unintentionally
# create a flag day with future platform versions.
#
/usr/sbin/ndd -set /dev/tcp tcp_rst_sent_rate_enabled 0

exit 0
