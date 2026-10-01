-- =====================================================================
-- 04. Cohort retention: do customers come back?
-- A cohort = customers whose first purchase was in the same month.
-- Techniques: multi-step CTEs, date arithmetic, self-referencing cohort joins
-- =====================================================================

-- name: cohort_retention
WITH activity AS (               -- every month in which a customer purchased
    SELECT DISTINCT customer_id, order_month AS activity_month
    FROM v_orders
    WHERE status <> 'Cancelled'
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM v_customer_summary
    GROUP BY cohort_month
),
retention AS (
    SELECT  s.cohort_month,
            (CAST(strftime('%Y', a.activity_month) AS INTEGER) - CAST(strftime('%Y', s.cohort_month) AS INTEGER)) * 12
          + (CAST(strftime('%m', a.activity_month) AS INTEGER) - CAST(strftime('%m', s.cohort_month) AS INTEGER))
                                                    AS month_number,
            COUNT(DISTINCT a.customer_id)           AS active_customers
    FROM activity a
    JOIN v_customer_summary s ON s.customer_id = a.customer_id
    GROUP BY 1, 2
)
SELECT  r.cohort_month,
        cs.cohort_customers,
        r.month_number,
        r.active_customers,
        ROUND(1.0 * r.active_customers / cs.cohort_customers, 4) AS retention_rate
FROM retention r
JOIN cohort_size cs ON cs.cohort_month = r.cohort_month
ORDER BY r.cohort_month, r.month_number;

-- name: repeat_rate_by_quarter
-- % of new customers who place a 2nd order within 90 days of their first.
-- Only complete quarters whose customers all have a full 90-day observation window
-- are included (data ends 2025-12-31, so the last usable quarter is 2025-Q3).
WITH ranked AS (
    SELECT  customer_id,
            order_date,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS order_seq
    FROM v_orders
    WHERE status <> 'Cancelled'
),
first_second AS (
    SELECT  customer_id,
            MAX(CASE WHEN order_seq = 1 THEN order_date END) AS first_order,
            MAX(CASE WHEN order_seq = 2 THEN order_date END) AS second_order
    FROM ranked
    WHERE order_seq <= 2
    GROUP BY customer_id
)
SELECT  strftime('%Y', first_order) || '-Q' || ((CAST(strftime('%m', first_order) AS INTEGER) + 2) / 3) AS cohort_quarter,
        COUNT(*)                                                                    AS new_customers,
        SUM(CASE WHEN julianday(second_order) - julianday(first_order) <= 90 THEN 1 ELSE 0 END) AS repeat_90d,
        ROUND(100.0 * SUM(CASE WHEN julianday(second_order) - julianday(first_order) <= 90 THEN 1 ELSE 0 END)
                    / COUNT(*), 1)                                                  AS repeat_rate_90d_pct,
        CASE WHEN MIN(first_order) >= '2025-03-01' THEN 'After Cartwise Plus'
             WHEN MAX(first_order) <  '2025-03-01' THEN 'Before Cartwise Plus'
             ELSE 'Launch quarter' END                                              AS period
FROM first_second
WHERE first_order < '2025-10-01'
GROUP BY cohort_quarter
ORDER BY cohort_quarter;
