# PostgreSQL Settings

This document highlights some important deviations from PostgreSQL's defaults in
the postgresql.conf files (see etc/) in this repository.

## autovacuum

To allow autovacuum to keep up with dead tuple accumulation and XID consumption
on a regular basis, we have tuned the folllowing settings:

- `vacuum_freeze_min_age`
- `vacuum_freeze_table_age`

`vacuum_freeze_table_age` denotes the threshold for when an aggressive vacuum
will be triggered by autovacuum, otherwise the vacuum will be a normal, dead
tuple-cleaning vacuum.  `vacuum_freeze_min_age` is set as such to allow even
normal vacuums to do some amount of opportunistic tuple freezing.  At the
current settings and workload we have found that both normal and aggressive
vacuums take the same amount of time and impact database performance similarly.
With these settings we never intend to hit `vacuum_freeze_max_age` (i.e. a
vacuum "to prevent wraparound").

These must also be paired with some relation-specific settings which cannot be
expressed per relation in these configuration files.  The settings are as
follows and should be set via an `ALTER TABLE` command:

- `autovacuum_vacuum_scale_factor: 0`
- `autovacuum_vacuum_threshold`
- `autovacuum_analyze_scale_factor: 0`
- `autovacuum_analyze_threshold`

Note: These relation-specific changes only need to be applied to the primary
database.  The other peers in a cluster will get these settings over the
replication stream.

The intention of these settings is to allow autovacuum to trigger vacuums based
on a constant rate of change in the relation.
