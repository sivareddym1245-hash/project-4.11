# Index Order Investigation

## Query under investigation

```sql
SELECT *
FROM orders
WHERE customer_id = 451
  AND status = 'completed';
```

The experiment in [`experiment.sql`](./experiment.sql) creates a temporary
table, runs the query without an index, tests `(status, customer_id)`, then
tests `(customer_id, status)`. Each plan uses `EXPLAIN (ANALYZE, BUFFERS)`;
the script also tests a query that filters only on `customer_id`.

## Findings

The original candidate index is:

```sql
CREATE INDEX orders_status_customer_idx ON orders (status, customer_id);
```

It sorts entries by `status` first and then `customer_id`. The proposed
customer-first index is:

```sql
CREATE INDEX orders_customer_status_idx ON orders (customer_id, status);
```

It sorts by `customer_id` first and then `status`.

### Important PostgreSQL behavior

The two-column query has an equality condition on **both** index columns.
PostgreSQL can use either composite B-tree index for this query: the equality
condition on the first key narrows the search, and the equality condition on
the second key narrows it further. Therefore, the claim that
`(status, customer_id)` must be ignored or cause a sequential scan for this
exact query is too broad. Whether PostgreSQL chooses an index scan or a
sequential scan depends on the table, data distribution, statistics, and
estimated cost. An index existing does not guarantee that the planner will
choose it.

Column order matters when a query does not constrain every indexed key. For
example, `(customer_id, status)` has `customer_id` as its left-most prefix and
can directly support the customer-only query in the script. With
`(status, customer_id)`, `customer_id` is not the leading key, so that index
is generally a poorer fit for a customer-only lookup. PostgreSQL versions
with B-tree skip-scan support may sometimes use a non-leading key when the
leading key has few distinct values; inspect the plan instead of treating the
left-most-prefix rule as an absolute prohibition.

## Conclusion

For a workload that commonly filters by `customer_id`, placing it first is a
reasonable design:

```sql
CREATE INDEX orders_customer_status_idx ON orders (customer_id, status);
```

It supports the stated two-column equality query and customer-only lookups.
The best order depends on the workload: if queries commonly filter on
`status` alone, a status-first index may better serve those queries. Choose
the order from the access patterns and measured plans, not a rule that
equality predicates are inherently unusable when reversed.

## Plan results

The script was run against a temporary PostgreSQL 18 instance with its
generated 300,000-row table. One run produced these plans:

| Index state | Query | Observed plan | Actual rows | Execution time |
|---|---|---|---:|---:|
| No composite index | Both equality filters | Sequential scan | 7 | 27.013 ms |
| `(status, customer_id)` | Both equality filters | Index Scan | 7 | 0.083 ms |
| `(status, customer_id)` | `customer_id` only | Index Scan (7 index searches) | 10 | 0.200 ms |
| `(customer_id, status)` | Both equality filters | Bitmap Heap Scan + Bitmap Index Scan | 7 | 0.089 ms |
| `(customer_id, status)` | `customer_id` only | Bitmap Heap Scan + Bitmap Index Scan | 10 | 0.054 ms |

These results were collected by running `experiment.sql` against a disposable
PostgreSQL 18.4 instance. They directly show that the status-first index was
**not ignored** for the stated two-equality query. PostgreSQL 18 also used a
skip scan for the customer-only query, as shown by its seven index searches;
this is a version- and data-dependent optimization, not the same direct
left-most prefix as the customer-first index. The customer-first index
supported that lookup with one index search.

The timings are from one run on a disposable local instance. They are not a
benchmark: cache state, hardware, PostgreSQL version, statistics, and data
distribution can change the plan and execution time. Re-run the script in
the target environment and use its actual plan output when presenting the
assignment.
