# PostgreSQL Settings

This document intends to walk through the postgresql*.conf configuration files
in this repository and explain the reasoning behind the choices.

## Vacuums

### History

Under high write workloads to Manta, we have found that tuning of vacuum-related
settings has been required in order to keep up with the constant rate of change
in the database.  Prior to the settings outlined in this document, vacuums
appeared to only run when the age of a relation breached
`autovacuum_freeze_max_age`, essentially making PostgreSQL think we're running
out of XIDs.  This meant that we would see disruptive aggressive vacuums "to
prevent wraparound" that had a lot of work to do in order to freeze and remove
enough dead tuples (it seems they always freeze 450M tuples).

This scenario is one of two ways that a vacuum can be triggered.  The other is
when the number of dead tuples in a relation exceeds a given threshold.  This
threshold is relation-specific, and was set to the defaults that PostgreSQL
ships with.  Because this threshold was set to a percentage of change in the
relation, this value ended up being far too high for our dead tuple accumulation
and was never reached.

Resharding is another reason for these types of vacuums, but this scenario has
not been taking into account with these settings.  It is quite possible that
these settings are not enough to keep up with the amount of DELETE statements
that a reshard procedure performs and we must modify these settings to take this
into account.  Since making these changes, we have not performed a reshard of
the metadata tier in order to observe the impact.

What this configuration lead to was a situation where a given shard would have
great performance (low latencies) for a period of time, then for ~30-60d we
would see an aggressive type of vacuum on the relation that would bring
latencies up to troublesome levels.  Spread across hundreds of shards, this lead
to a high level of unpredictability for the user of Manta.

### Goal of vacuum-related changes

Some changes have been made to PostgreSQL's vacuum-related tunables in order to
gain control over the above situation.  The goal was to vacuum more often and
have the work required by vacuuming impact us at a constant level.  We didn't
want to have to deal with a "special" vacuum happening on a certain cadence
(e.g. Sunday is our bad vacuum day, where latencies are higher on this day of
the week).

The result of this might mean a higher lower bound of latencies (when previously
not vacuuming), but will also reduce the upper bound (when previously
vacuuming), essentially sitting at some level between the two.  This would be
much more predicatable for users of Manta.

### How was that done?

We set the following tunables:

- autovacuum_freeze_min_age
- autovacuum_freeze_table_age
- (relation-specific) autovacuum_vacuum_threshold
- (relation-specific) autovacuum_vacuum_scale_factor

We left autovacuum_freeze_max_age untouched.  We plan never to hit this
threshold ever again ever.

autovacuum_freeze_min_age was set to XXX, which denotes the minimum age of a
tuple that should be frozen when vacuuming.

autovacuum_vacuum_scale_factor is now 0, and autovacuum_vacuum_threshold is set
at a value specific to how much dead tuple accumulation a relation now goes
through.  This means that a vacuum is now triggered on a fixed rate of change in
the relation, not dependant on the overall size of the relation.

When autovacuum_vacuum_threshold is reached, autovacuum will trigger a vacuum.
The type of vacuum that is triggered depends on the age of the relation at the
time of vacuum start.

If the age is less than autovacuum_freeze_table_age, it will be a normal vacuum.
This type of vacuum doesn't need to see every tuple in the heap, and so cannot
(and does not) make a decision on the new age of the relation.  It will
opportunistically freeze tuples as it needs to dirty pages for dead tuple
cleanup, and it freezes based on the value of autovacuum_freeze_min_age.

If the age is greater than autovacuum_freeze_table_age, it will be an aggressive
vacuum.  This type of vacuum necessarily needs to see everything in the
relation, because its primary goal is to reduce the age of the relation.  It
will do the same task as a normal vacuum, but it will also dirty pages even if
just to freeze a tuple.

### Findings

What we have found is that vacuums are now running nearly all the time.
Depending on the region we see these vacuums take 1-3d.  Every 5-6 vacuums of
this type, we see the vacuum become aggressive, but the impact of this
aggressive vacuum is the same as a normal vacuum.

### What's next

There is still work to do in smoothing out this vacuuming per region, where
perhaps 3d is still too long for us.  However, it is putting us in the position
where we no longer need to be considerate of vacuums running when performing
maintenance tasks on a shard.

It would be great if PostgreSQL could report on how many tuples it froze
opportunistically while vacuuming normally.

We currently have no way of controling relation-specific tunables in code; they
must be performed via {{ALTER TABLE ...}} commands on the database via Change
Management tickets.

Nearly all of these settings will need to change depending on incoming workload
to the region.  Ideally this would be automatic, but we have no mechanism to do
this.  We might also want to have a system that senses a lack of write workload
and responds by performing manual vacuums to the shards to allow some catchup
time.  It is worth noting that a vacuum that is run via the {{VACUUM}} command
will not back down in the face of certain operations on the database, such as
{{REINDEX}}.  autovacuum-triggered vacuums aparently will.
