--Cumulative revenue per Sessions Bucket
WITH filtered_sessions AS (
    SELECT *
    FROM sessions
    WHERE session_start >= '2023-01-05'
),
sessions_per_user AS (
    SELECT
        user_id,
        COUNT(*) AS total_sessions
    FROM filtered_sessions
    GROUP BY user_id
),
booking_sessions AS (
    SELECT DISTINCT
        trip_id,
        user_id,
        flight_discount_amount,
        hotel_discount_amount
    FROM filtered_sessions
    WHERE trip_id IS NOT NULL
      AND cancellation = FALSE
),
trip_revenue AS (
    SELECT
        bs.user_id,
        bs.trip_id,
        COALESCE(
            f.base_fare_usd *
            GREATEST(f.seats,1) *
            (1 - COALESCE(bs.flight_discount_amount,0)),
            0
        )
        +
        COALESCE(
            h.hotel_per_room_usd *
            GREATEST(h.rooms,1) *
            GREATEST(ABS(h.nights),1) *
            (1 - COALESCE(bs.hotel_discount_amount,0)),
            0
        ) AS trip_revenue
    FROM booking_sessions bs
    LEFT JOIN flights f ON bs.trip_id = f.trip_id
    LEFT JOIN hotels h ON bs.trip_id = h.trip_id
),
revenue_per_user AS (
    SELECT
        user_id,
        SUM(trip_revenue) AS total_revenue
    FROM trip_revenue
    GROUP BY user_id
),
user_bucket_revenue AS (
    SELECT
        spu.total_sessions,
        ROUND(SUM(COALESCE(rpu.total_revenue,0))) AS bucket_revenue
    FROM sessions_per_user spu
    LEFT JOIN revenue_per_user rpu
        ON spu.user_id = rpu.user_id
    GROUP BY spu.total_sessions
)
SELECT
    total_sessions,
    bucket_revenue,
    ROUND(SUM(bucket_revenue) OVER (ORDER BY total_sessions DESC)) AS cumulative_revenue,
    ROUND(SUM(bucket_revenue) OVER (ORDER BY total_sessions DESC) / SUM(bucket_revenue) OVER () * 100 ,4) AS cumulative_revenue_pct
FROM user_bucket_revenue
ORDER BY total_sessions DESC;