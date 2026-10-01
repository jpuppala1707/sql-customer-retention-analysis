-- =====================================================================
-- 02. Clean analytical views: a single source of truth for every analysis
-- * Excludes internal test accounts
-- * Rolls order lines up to order level with revenue, cost and margin
-- * De-duplicates double-fired tracking events
-- =====================================================================

DROP VIEW IF EXISTS v_orders;
CREATE VIEW v_orders AS
SELECT  o.order_id,
        o.customer_id,
        DATE(o.order_date)                              AS order_date,
        DATE(o.order_date, 'start of month')            AS order_month,
        o.status,
        c.acquisition_channel,
        c.region,
        SUM(oi.quantity)                                AS units,
        ROUND(SUM(oi.quantity * oi.unit_price), 2)      AS order_value,
        ROUND(SUM(oi.quantity * p.unit_cost), 2)        AS order_cost
FROM orders o
JOIN customers   c  ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id   = o.order_id
JOIN products    p  ON p.product_id  = oi.product_id
WHERE c.is_test_account = 0
GROUP BY o.order_id;

-- Revenue is only recognised on completed orders (returns are refunded, cancellations never shipped)
DROP VIEW IF EXISTS v_completed_orders;
CREATE VIEW v_completed_orders AS
SELECT * FROM v_orders WHERE status = 'Completed';

-- One row per customer: first purchase and lifetime figures
DROP VIEW IF EXISTS v_customer_summary;
CREATE VIEW v_customer_summary AS
SELECT  c.customer_id,
        c.acquisition_channel,
        c.region,
        MIN(o.order_date)                               AS first_order_date,
        DATE(MIN(o.order_date), 'start of month')       AS cohort_month,
        MAX(o.order_date)                               AS last_order_date,
        COUNT(o.order_id)                               AS orders,
        ROUND(SUM(CASE WHEN o.status = 'Completed' THEN o.order_value ELSE 0 END), 2) AS net_revenue
FROM customers c
JOIN v_orders o ON o.customer_id = c.customer_id
WHERE o.status <> 'Cancelled'
GROUP BY c.customer_id;

DROP VIEW IF EXISTS v_events;
CREATE VIEW v_events AS
SELECT DISTINCT session_id, customer_id, event_time, event_name, device, traffic_channel
FROM web_events;
