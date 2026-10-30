# Index Order Matters

This experiment compares two PostgreSQL B-tree indexes against an analytics
query on `orders`:

```sql
SELECT *
FROM orders
WHERE customer_id = 451
  AND status = 'completed';
```

## Run the experiment

You need PostgreSQL 12 or later and `psql`. Connect to a disposable database
you can use, then run the script in one session:

```powershell
psql -d your_database -f "experiment.sql"
```

The script creates a temporary `orders` table with deterministic sample data.
It does not create, drop, or modify permanent tables. The temporary table is
removed when the `psql` session ends.

The script:

1. Runs `EXPLAIN (ANALYZE, BUFFERS)` without an index.
2. Adds `(status, customer_id)` and explains the two-column query and a
   customer-only query.
3. Replaces it with `(customer_id, status)` and repeats both plans.

PostgreSQL chooses plans based on table size, statistics, selectivity, and
cost settings. An index scan is not guaranteed; compare the actual plans and
buffer counts from your database rather than assuming an index must be used.

## What to compare

For the query that filters on both columns with equality, PostgreSQL can use
either index ordering. The customer-first index also supports queries that
filter by `customer_id` alone, because that is its left-most column. The
status-first index does not provide the same direct customer-only prefix,
although PostgreSQL 18 used skip scans for that case in the sample run.
See [Changes.md](./Changes.md) for the measured plans and caveats.
