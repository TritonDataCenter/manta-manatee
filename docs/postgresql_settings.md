# PostgreSQL Settings

This document highlights some important deviations from PostgreSQL's defaults in
the postgresql.conf files in this repository.

## autovacuum

- `vacuum_freeze_min_age`
- `vacuum_freeze_table_age`
- `autovacuum_vacuum_cost_delay`

The values for these settings (see ./etc/) allow our vacuums to take ~1-3d in
duration (for both aggressive and normal vacuums, dependant on region's
workload) while also not causing too much impact to database performance.  They
allow us to keep up with XID usage without ever performing a vacuum "to prevent
wraparound" (i.e. when the age of a relation is greater than
`vacuum_freeze_max_age`), and ultimately result in our databases nearly always
having some type of vacuum running.

These must also be paired with some relation-specific settings which cannot be
expressed in these configuration files.  The settings are as follows and should
be set via `psql`:

- `autovacuum_vacuum_scale_factor: 0`
- `autovacuum_vacuum_threshold`
- `autovacuum_analyze_scale_factor: 0`
- `autovacuum_analyze_threshold`

The intention of these settings is to allow autovacuum to trigger vacuums based
on a constant rate of dead tuple accumulation in a given relation.
