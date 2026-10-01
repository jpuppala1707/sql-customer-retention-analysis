-- =====================================================================
-- 08. Category economics and revenue concentration
-- Techniques: running totals with window frames, NTILE deciles
-- =====================================================================

-- name: category_performance
-- Revenue, margin and return rate by category (line-level, test accounts excluded)
SELECT  p.category,
        ROUND(SUM(CASE WHEN o.status = 'Completed' THEN oi.quantity * oi.unit_price END), 0)       AS net_revenue,
        ROUND(100.0 * SUM(CASE WHEN o.status = 'Completed' THEN oi.quantity * (oi.unit_price - p.unit_cost) END)
                    / SUM(CASE WHEN o.status = 'Completed' THEN oi.quantity * oi.unit_price END), 1)  AS gross_margin_pct,
        ROUND(100.0 * SUM(CASE WHEN o.status = 'Returned' THEN oi.quantity * oi.unit_price END)
                    / SUM(CASE WHEN o.status <> 'Cancelled' THEN oi.quantity * oi.unit_price END), 1) AS return_rate_pct,
        ROUND(SUM(CASE WHEN o.status = 'Returned' THEN oi.quantity * oi.unit_price END), 0)         AS returned_value
FROM order_items oi
JOIN orders    o ON o.order_id    = oi.order_id
JOIN products  p ON p.product_id  = oi.product_id
JOIN customers c ON c.customer_id = o.customer_id
WHERE c.is_test_account = 0
GROUP BY p.category
ORDER BY net_revenue DESC;

-- name: revenue_concentration
-- What share of revenue comes from the top 10%, 20%, ... of customers?
WITH customer_rev AS (
    SELECT customer_id, SUM(order_value) AS revenue
    FROM v_completed_orders
    GROUP BY customer_id
),
deciles AS (
    SELECT customer_id, revenue, NTILE(10) OVER (ORDER BY revenue DESC) AS decile
    FROM customer_rev
)
SELECT  decile,
        COUNT(*)                                                             AS customers,
        ROUND(SUM(revenue), 0)                                               AS revenue,
        ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)           AS pct_revenue,
        ROUND(100.0 * SUM(SUM(revenue)) OVER (ORDER BY decile ROWS UNBOUNDED PRECEDING)
                    / SUM(SUM(revenue)) OVER (), 1)                          AS cumulative_pct_revenue
FROM deciles
GROUP BY decile
ORDER BY decile;
