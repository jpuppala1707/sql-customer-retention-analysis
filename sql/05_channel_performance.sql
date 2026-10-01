-- =====================================================================
-- 05. Acquisition channel quality: which channels bring customers who stay?
-- Marketing usually optimises for cost per *first* order. This query compares
-- channels on what happens after the first order.
-- =====================================================================

-- name: channel_quality
WITH second_orders AS (
    SELECT  s.customer_id,
            MIN(o.order_date) AS second_order_date
    FROM v_customer_summary s
    JOIN v_orders o
      ON o.customer_id = s.customer_id
     AND o.status <> 'Cancelled'
     AND o.order_date > s.first_order_date
    GROUP BY s.customer_id
),
rev_12m AS (                      -- revenue in each customer's first 365 days
    SELECT  s.customer_id,
            SUM(o.order_value) AS revenue_12m
    FROM v_customer_summary s
    JOIN v_completed_orders o
      ON o.customer_id = s.customer_id
     AND o.order_date < DATE(s.first_order_date, '+365 days')
    GROUP BY s.customer_id
)
SELECT  s.acquisition_channel,
        COUNT(*)                                                                        AS customers,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                              AS pct_of_new_customers,
        -- 90-day repeat rate (customers with a full 90-day window)
        ROUND(100.0 * SUM(CASE WHEN julianday(so.second_order_date) - julianday(s.first_order_date) <= 90 THEN 1 ELSE 0 END)
                    / SUM(CASE WHEN s.first_order_date <= DATE('2025-12-31', '-90 days') THEN 1 ELSE 0 END), 1)
                                                                                        AS repeat_rate_90d_pct,
        -- 12-month value: only customers acquired in 2024 (full year observed)
        ROUND(AVG(CASE WHEN s.first_order_date < '2025-01-01' THEN COALESCE(r.revenue_12m, 0) END), 2)
                                                                                        AS avg_12m_revenue,
        ROUND(AVG(s.orders), 2)                                                         AS avg_lifetime_orders
FROM v_customer_summary s
LEFT JOIN second_orders so ON so.customer_id = s.customer_id
LEFT JOIN rev_12m       r  ON r.customer_id  = s.customer_id
GROUP BY s.acquisition_channel
ORDER BY avg_12m_revenue DESC;
