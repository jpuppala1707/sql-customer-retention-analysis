-- =====================================================================
-- 03. KPI overview: how is the business trending?
-- Techniques: aggregation, CTEs, LAG() window function for MoM and YoY growth
-- =====================================================================

-- name: monthly_kpis
WITH monthly AS (
    SELECT  order_month,
            COUNT(*)                                    AS orders,
            COUNT(DISTINCT customer_id)                 AS active_customers,
            ROUND(SUM(order_value), 2)                  AS net_revenue,
            ROUND(SUM(order_value - order_cost), 2)     AS gross_profit
    FROM v_completed_orders
    GROUP BY order_month
)
SELECT  order_month,
        orders,
        active_customers,
        net_revenue,
        ROUND(net_revenue / orders, 2)                                  AS avg_order_value,
        ROUND(100.0 * gross_profit / net_revenue, 1)                    AS gross_margin_pct,
        ROUND(100.0 * (net_revenue - LAG(net_revenue, 1)  OVER w)
                    / LAG(net_revenue, 1)  OVER w, 1)                   AS revenue_mom_pct,
        ROUND(100.0 * (net_revenue - LAG(net_revenue, 12) OVER w)
                    / LAG(net_revenue, 12) OVER w, 1)                   AS revenue_yoy_pct
FROM monthly
WINDOW w AS (ORDER BY order_month)
ORDER BY order_month;

-- name: yearly_kpis
WITH new_customers AS (
    SELECT strftime('%Y', first_order_date) AS year, COUNT(*) AS new_customers
    FROM v_customer_summary GROUP BY 1
)
-- "Active" = placed at least one non-cancelled order in the year (same rule as new customers)
SELECT  strftime('%Y', o.order_date)                                    AS year,
        COUNT(*)                                                        AS orders,
        COUNT(DISTINCT o.customer_id)                                   AS active_customers,
        n.new_customers,
        COUNT(DISTINCT o.customer_id) - n.new_customers                 AS returning_customers,
        ROUND(SUM(CASE WHEN o.status = 'Completed' THEN o.order_value END), 0) AS net_revenue,
        ROUND(AVG(CASE WHEN o.status = 'Completed' THEN o.order_value END), 2) AS avg_order_value,
        ROUND(1.0 * COUNT(*) / COUNT(DISTINCT o.customer_id), 2)        AS orders_per_customer
FROM v_orders o
JOIN new_customers n ON n.year = strftime('%Y', o.order_date)
WHERE o.status <> 'Cancelled'
GROUP BY 1
ORDER BY 1;

-- name: order_status_mix
SELECT  status,
        COUNT(*)                                                        AS orders,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)              AS pct_of_orders,
        ROUND(SUM(order_value), 0)                                      AS order_value
FROM v_orders
GROUP BY status
ORDER BY orders DESC;
