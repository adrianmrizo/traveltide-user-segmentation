-- Calcutalting booking rate per session bucket
WITH sessions_per_user AS (
    SELECT
        user_id,
        COUNT(*) AS total_sessions
    FROM sessions
    WHERE session_start >= '2023-01-05'
    GROUP BY user_id
),
sessions_enriched AS (
    SELECT
        s.session_id,
        s.user_id,
        spu.total_sessions,
        CASE WHEN s.trip_id IS NOT NULL THEN 1 ELSE 0 END AS is_booking
    FROM sessions s
    JOIN sessions_per_user spu
        ON s.user_id = spu.user_id
    WHERE s.session_start >= '2023-01-05'
)
SELECT
    total_sessions,
    COUNT(*) AS total_sessions_count,
    SUM(is_booking) AS total_bookings,
    ROUND(SUM(is_booking)::decimal / COUNT(*) * 100, 2) AS booking_rate
FROM sessions_enriched
GROUP BY total_sessions
ORDER BY total_sessions;