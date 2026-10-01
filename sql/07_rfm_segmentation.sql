-- =====================================================================
-- 07. RFM segmentation: who are our best customers, and who are we losing?
-- Recency / Frequency / Monetary scores, snapshot date = 2026-01-01
-- Techniques: NTILE(), CASE-based scoring, segment rules
-- =====================================================================

-- name: rfm_customers
WITH base AS (
    SELECT  customer_id,
            CAST(julianday('2026-01-01') - julianday(MAX(order_date)) AS INTEGER) AS recency_days,
            COUNT(*)                                                             AS frequency,
            ROUND(SUM(order_value), 2)                                           AS monetary
    FROM v_completed_orders
    GROUP BY customer_id
),
scored AS (
    SELECT  *,
            NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- more recent = higher
            -- Most customers have 1-2 orders, so NTILE() would split identical
            -- frequencies into different scores. Fixed business thresholds instead:
            CASE WHEN frequency >= 6 THEN 5
                 WHEN frequency >= 4 THEN 4
                 WHEN frequency  = 3 THEN 3
                 WHEN frequency  = 2 THEN 2
                 ELSE 1 END                            AS f_score,
            NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM base
)
SELECT  *,
        CASE
            WHEN r_score >= 4 AND f_score >= 4                  THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2                  THEN 'New & Promising'
            WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk (high value)'
            WHEN r_score  = 3 AND f_score <= 2                  THEN 'Needs Attention'
            ELSE                                                     'Hibernating'
        END AS segment
FROM scored;

-- name: rfm_segment_summary
-- (re-uses the logic above, summarised per segment)
WITH base AS (
    SELECT  customer_id,
            CAST(julianday('2026-01-01') - julianday(MAX(order_date)) AS INTEGER) AS recency_days,
            COUNT(*) AS frequency, SUM(order_value) AS monetary
    FROM v_completed_orders GROUP BY customer_id
),
scored AS (
    SELECT *, NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
           CASE WHEN frequency >= 6 THEN 5 WHEN frequency >= 4 THEN 4 WHEN frequency = 3 THEN 3
                WHEN frequency = 2 THEN 2 ELSE 1 END AS f_score
    FROM base
),
segmented AS (
    SELECT *, CASE
            WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New & Promising'
            WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk (high value)'
            WHEN r_score  = 3 AND f_score <= 2 THEN 'Needs Attention'
            ELSE 'Hibernating' END AS segment
    FROM scored
)
SELECT  segment,
        COUNT(*)                                                        AS customers,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)              AS pct_customers,
        ROUND(SUM(monetary), 0)                                         AS revenue,
        ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)    AS pct_revenue,
        ROUND(AVG(recency_days), 0)                                     AS avg_recency_days,
        ROUND(AVG(frequency), 1)                                        AS avg_orders,
        ROUND(AVG(monetary), 0)                                         AS avg_revenue
FROM segmented
GROUP BY segment
ORDER BY revenue DESC;
