#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2019 Joyent, Inc.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

SOURCE="${BASH_SOURCE[0]}"
if [[ -h $SOURCE ]]; then
    SOURCE="$(readlink "$SOURCE")"
fi
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
PROFILE=/root/.bashrc
SVC_ROOT=/opt/smartdc/manatee
role=manatee
REGISTRAR_CFG=/opt/smartdc/registrar/etc/config.json

export PATH=$SVC_ROOT/build/node/bin:/opt/local/bin:/usr/sbin/:/usr/bin:$PATH

# Install zookeeper package, need to touch this file to disable the license prompt
touch /opt/local/.dli_license_accepted


function manta_manatee_setup {
    echo "Running common setup scripts"
    manta_common_presetup

    echo "Adding local manifest directories"
    manta_add_manifest_dir "/opt/smartdc/manatee"
    manta_add_manifest_dir "/opt/smartdc/waferlock"

    # MANTA-1360 no args to manta_common_setup so we don't rotate the 'manatee'
    # entry which stomps over the other manatee logs
    manta_common_setup
    manta_setup_manatee_env

    PARENT_DATASET=zones/$(zonename)/data
    PG_LOG_DIR=/var/pg
    ZONE_IP=`ifconfig net0 | nawk '{if ($1 == "inet") print $2}'`
    SITTER_CFG_FILE=/opt/smartdc/manatee/etc/sitter.json
    SNAPSHOT_CFG_FILE=/opt/smartdc/manatee/etc/snapshotter.json
    BACKUP_CFG_FILE=/opt/smartdc/manatee/etc/backupserver.json
    SHARD=$(json -f /var/tmp/metadata.json SERVICE_NAME)

    common_manatee_setup

    # ZK configs
    ZK_TIMEOUT=30000

    manta_ensure_zk

    common_enable_services

    manta_common_setup_end
}

function common_enable_services {
    # import services
    echo "Starting snapshotter"
    svccfg import /opt/smartdc/manatee/smf/manifests/snapshotter.xml
    svcadm enable manatee-snapshotter

    echo "Starting backupserver"
    svccfg import /opt/smartdc/manatee/smf/manifests/backupserver.xml
    svcadm enable manatee-backupserver

    svccfg import /opt/smartdc/manatee/smf/manifests/sitter.xml

    # With Manta we *always* want sitter.
    echo "Starting sitter"
    svcadm enable manatee-sitter

    #
    # Import the PostgreSQL prefaulter service.
    #
    echo "Starting prefaulter"
    svccfg import /opt/smartdc/manatee/smf/manifests/pg_prefaulter.xml

    echo "Starting waferlock"
    svccfg import /opt/smartdc/waferlock/smf/manifests/waferlock.xml
}

function common_manatee_setup {
    #
    # Enable LZ4 compression and set the recordsize to 8KB on the top-level
    # delegated dataset.  The Manatee dataset is a child dataset, and will
    # inherit these properties -- even if it is subsequently recreated by a
    # rebuild operation.
    #
    echo "enabling LZ4 compression on manatee dataset"
    zfs set compress=lz4 "$PARENT_DATASET"

    echo "setting recordsize to 8K on manatee dataset"
    zfs set recordsize=8k "$PARENT_DATASET"

    # create postgres group
    echo "creating postgres group (gid=907)"
    groupadd -g 907 postgres

    # create postgres user
    echo "creating postgres user (uid=907)"
    useradd -u 907 -g postgres -m postgres

    # grant postgres user chmod chown privileges with sudo
    echo "postgres    ALL=(ALL) NOPASSWD: /usr/bin/chown, /usr/bin/chmod, /opt/local/bin/chown, /opt/local/bin/chmod" >> /opt/local/etc/sudoers

    # give postgres user zfs permmissions.
    echo "grant postgres user zfs perms"
    zfs allow -ld postgres create,destroy,diff,hold,release,rename,setuid,rollback,share,snapshot,mount,promote,send,receive,clone,mountpoint,canmount $PARENT_DATASET

    # add pg log dir
    mkdir -p $PG_LOG_DIR
    chown -R postgres $PG_LOG_DIR
    chmod 700 $PG_LOG_DIR
}

function add_manatee_profile_functions {
    ZK_IPS=$(json -f ${METADATA} ZK_SERVERS | json -a host)

    # get correct ZK_IPS
    echo "source /opt/smartdc/etc/zk_ips.sh" >> $PROFILE
    echo "export ZK_IPS=\"\$(echo \$ZK_IPS | cut -d' ' -f1)\"" >> $PROFILE

    # export shard
    local shard=$(cat /opt/smartdc/manatee/etc/sitter.json | json shardPath | \
        cut -d '/' -f3)
    echo "export SHARD=$shard" >> $PROFILE

    # export sitter config
    echo "export MANATEE_SITTER_CONFIG=/opt/smartdc/manatee/etc/sitter.json" \
        >> $PROFILE

    #functions
    echo "zbunyan() { bunyan -c \"this.component !== 'ZKPlus'\"; }" >> $PROFILE
    echo "mbunyan() { bunyan -c \"this.component !== 'ZKPlus'\"  -c 'level >= 30'; }" >> $PROFILE
    echo "msitter(){ tail -f \`svcs -L manatee-sitter\` | mbunyan; }" >> $PROFILE
    echo "mbackupserver(){ tail -f \`svcs -L manatee-backupserver\` | mbunyan; }" >> $PROFILE
    echo "msnapshotter(){ tail -f \`svcs -L manatee-snapshotter\` | mbunyan; }" >> $PROFILE
    echo "manatee-stat(){ manatee-adm status; }" >> $PROFILE
}


function manta_setup_manatee_env {
    mkdir -p /var/log/manatee

    #.bashrc
    echo "export PATH=\$PATH:/opt/smartdc/manatee/bin/:/opt/smartdc/manatee/pg_dump/:/opt/smartdc/manatee/node_modules/manatee/bin:/opt/postgresql/current/bin" >> /root/.bashrc
    echo "export MANPATH=\$MANPATH:/opt/smartdc/manatee/node_modules/manatee/man" >> /root/.bashrc
    echo "alias psql='sudo -u postgres psql'" >>/root/.bashrc

    #cron
    local crontab=/tmp/.manta_manatee_cron
    crontab -l > $crontab

    #Before you change cron scheduling, please consult the Mola System "Crons"
    # Overview documentation (manta-mola.git/docs/system-crons)

    echo "0 0 * * * /opt/smartdc/manatee/pg_dump/pg_dump.sh >> /var/log/manatee/pgdump.log 2>&1" >> $crontab
    [[ $? -eq 0 ]] || fatal "Unable to write to $crontab"
    crontab $crontab
    [[ $? -eq 0 ]] || fatal "Unable import crons"

    manta_add_logadm_entry "manatee-sitter"
    manta_add_logadm_entry "manatee-backupserver"
    manta_add_logadm_entry "manatee-snapshotter"
    manta_add_logadm_entry "waferlock"
    manta_add_logadm_entry "postgresql" "/var/pg"
    manta_add_logadm_entry "pgdump" "/var/log/manatee"
}


source ${DIR}/scripts/util.sh
source ${DIR}/scripts/services.sh

manta_manatee_setup
add_manatee_profile_functions

exit 0
