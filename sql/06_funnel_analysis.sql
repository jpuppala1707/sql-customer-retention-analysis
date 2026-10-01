-- =====================================================================
-- 06. Conversion funnel (2025 web sessions): where do shoppers drop off?
-- Techniques: conditional aggregation, pivoting events to session level
-- =====================================================================

-- name: funnel_by_device
WITH session_steps AS (           -- one row per session with a 0/1 flag per funnel step
    SELECT  session_id,
            device,
            MAX(event_name = 'session_start')   AS s1_session,
            MAX(event_name = 'product_view')    AS s2_product_view,
            MAX(event_name = 'add_to_cart')     AS s3_add_to_cart,
            MAX(event_name = 'begin_checkout')  AS s4_checkout,
            MAX(event_name = 'purchase')        AS s5_purchase
    FROM v_events
    GROUP BY session_id, device
)
SELECT  device,
        SUM(s1_session)                                                     AS sessions,
        SUM(s2_product_view)                                                AS product_views,
        SUM(s3_add_to_cart)                                                 AS add_to_carts,
        SUM(s4_checkout)                                                    AS checkouts,
        SUM(s5_purchase)                                                    AS purchases,
        ROUND(100.0 * SUM(s2_product_view) / SUM(s1_session), 1)            AS view_rate_pct,
        ROUND(100.0 * SUM(s3_add_to_cart)  / SUM(s2_product_view), 1)       AS cart_rate_pct,
        ROUND(100.0 * SUM(s4_checkout)     / SUM(s3_add_to_cart), 1)        AS checkout_rate_pct,
        ROUND(100.0 * SUM(s5_purchase)     / SUM(s4_checkout), 1)           AS checkout_completion_pct,
        ROUND(100.0 * SUM(s5_purchase)     / SUM(s1_session), 2)            AS session_conversion_pct
FROM session_steps
GROUP BY device
ORDER BY sessions DESC;

-- name: funnel_by_channel
WITH session_steps AS (
    SELECT  session_id,
            traffic_channel,
            MAX(event_name = 'add_to_cart') AS added_to_cart,
            MAX(event_name = 'purchase')    AS purchased
    FROM v_events
    GROUP BY session_id, traffic_channel
)
SELECT  traffic_channel,
        COUNT(*)                                                AS sessions,
        ROUND(100.0 * SUM(added_to_cart) / COUNT(*), 1)         AS add_to_cart_pct,
        ROUND(100.0 * SUM(purchased)     / COUNT(*), 2)         AS conversion_pct
FROM session_steps
GROUP BY traffic_channel
ORDER BY conversion_pct DESC;

-- name: lost_checkout_opportunity
-- If mobile checkout completion matched desktop, how many extra orders would there be?
WITH steps AS (
    SELECT  session_id, device,
            MAX(event_name = 'begin_checkout') AS checkout,
            MAX(event_name = 'purchase')       AS purchase
    FROM v_events GROUP BY session_id, device
),
by_device AS (
    SELECT device, SUM(checkout) AS checkouts, 1.0 * SUM(purchase) / SUM(checkout) AS completion
    FROM steps GROUP BY device
),
aov AS (SELECT AVG(order_value) AS aov FROM v_completed_orders WHERE order_date >= '2025-01-01')
SELECT  m.checkouts                                                     AS mobile_checkouts,
        ROUND(100 * m.completion, 1)                                    AS mobile_completion_pct,
        ROUND(100 * d.completion, 1)                                    AS desktop_completion_pct,
        ROUND(m.checkouts * (d.completion - m.completion))              AS extra_orders_if_matched,
        ROUND(m.checkouts * (d.completion - m.completion) * aov.aov, 0) AS est_revenue_opportunity
FROM by_device m, by_device d, aov
WHERE m.device = 'Mobile' AND d.device = 'Desktop';
