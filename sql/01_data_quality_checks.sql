-- =====================================================================
-- 01. Data quality checks
-- Run BEFORE any analysis. Every issue found here is handled in 02_views.sql.
-- =====================================================================

-- name: row_counts
SELECT 'customers'   AS table_name, COUNT(*) AS row_count FROM customers   UNION ALL
SELECT 'products',                  COUNT(*)              FROM products    UNION ALL
SELECT 'orders',                    COUNT(*)              FROM orders      UNION ALL
SELECT 'order_items',               COUNT(*)              FROM order_items UNION ALL
SELECT 'web_events',                COUNT(*)              FROM web_events;

-- name: orphan_and_null_checks
SELECT 'orders without a valid customer' AS check_name,
       COUNT(*) AS issues
FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'orders without any line items',
       COUNT(*)
FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.order_id
WHERE oi.order_id IS NULL
UNION ALL
SELECT 'order lines with non-positive quantity or price',
       COUNT(*)
FROM order_items WHERE quantity <= 0 OR unit_price <= 0
UNION ALL
SELECT 'orders dated before customer first_seen_date',
       COUNT(*)
FROM orders o JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_date < c.first_seen_date;

-- name: test_account_impact
-- Internal QA accounts place fake orders. How much would they distort the numbers?
SELECT c.is_test_account,
       COUNT(DISTINCT c.customer_id)                         AS customers,
       COUNT(DISTINCT o.order_id)                            AS orders,
       ROUND(1.0 * COUNT(DISTINCT o.order_id)
                 / COUNT(DISTINCT c.customer_id), 1)         AS orders_per_customer
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.is_test_account;

-- name: duplicate_events
-- The same event recorded twice (identical session, timestamp and name) = tag fired twice.
SELECT COUNT(*)                     AS duplicate_rows,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM web_events), 2) AS pct_of_events
FROM (
    SELECT session_id, event_time, event_name, COUNT(*) AS n
    FROM web_events
    GROUP BY session_id, event_time, event_name
    HAVING COUNT(*) > 1
);
