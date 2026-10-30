-- Run this whole script in one psql session. All table data is temporary.

CREATE TEMPORARY TABLE orders (
    order_id BIGINT PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    status TEXT NOT NULL
);

INSERT INTO orders (order_id, customer_id, status)
SELECT
    order_id,
    ((order_id::BIGINT * 7919) % 30000)::INTEGER + 1,
    CASE
        WHEN order_id % 7 < 5 THEN 'completed'
        WHEN order_id % 7 = 5 THEN 'pending'
        ELSE 'cancelled'
    END
FROM generate_series(1, 300000) AS generated(order_id);

ANALYZE orders;

-- Baseline: no composite index.
EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT *
FROM orders
WHERE customer_id = 451
  AND status = 'completed';

-- Candidate with status as the leading column.
CREATE INDEX orders_status_customer_idx
    ON orders (status, customer_id);
ANALYZE orders;

EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT *
FROM orders
WHERE customer_id = 451
  AND status = 'completed';

-- Demonstrate the left-most-prefix difference: customer_id is not the first
-- key in the candidate index above.
EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT *
FROM orders
WHERE customer_id = 451;

-- Candidate with customer_id as the leading column.
DROP INDEX orders_status_customer_idx;
CREATE INDEX orders_customer_status_idx
    ON orders (customer_id, status);
ANALYZE orders;

EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT *
FROM orders
WHERE customer_id = 451
  AND status = 'completed';

EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT *
FROM orders
WHERE customer_id = 451;
