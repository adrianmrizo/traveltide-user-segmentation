WITH filtered_sessions AS (
    SELECT
        *,
        CASE WHEN trip_id IS NOT NULL THEN 1 ELSE 0 END AS is_booking
    FROM sessions
    WHERE session_start >= '2023-01-05'
),
sessions_per_user AS (
    SELECT
        user_id,
        COUNT(*) AS total_sessions,
        SUM(is_booking) AS total_booked_sessions
    FROM filtered_sessions
    GROUP BY user_id
),
trips_per_user AS (
    SELECT
        user_id,
        COUNT(DISTINCT trip_id) AS total_trips,
        COUNT(CASE WHEN cancellation = TRUE THEN 1 END) AS cancelled_trips
    FROM filtered_sessions
    WHERE trip_id IS NOT NULL
    GROUP BY user_id
),
-- trips válidos para revenue
valid_trips AS (
    SELECT DISTINCT
        trip_id,
        user_id,
        flight_discount_amount,
  		hotel_discount_amount
    FROM filtered_sessions
    WHERE trip_id IS NOT NULL
      AND cancellation = FALSE
),
-- revenue vuelo
flight_rev AS (
    SELECT
        vt.trip_id,
        vt.user_id,
        COALESCE(f.base_fare_usd * GREATEST(f.seats,1) * (1 - COALESCE(vt.flight_discount_amount,0)), 0 ) AS flight_revenue
    FROM valid_trips vt
    LEFT JOIN flights f
        ON vt.trip_id = f.trip_id
),
-- revenue hotel
hotel_rev AS (
    SELECT
        vt.trip_id,
        vt.user_id,
        COALESCE( h.hotel_per_room_usd * GREATEST(h.rooms,1) * GREATEST(ABS(h.nights),1) * (1 - COALESCE(vt.hotel_discount_amount,0)), 0 ) AS hotel_revenue
    FROM valid_trips vt
    LEFT JOIN hotels h
        ON vt.trip_id = h.trip_id
),
trip_revenue AS (
    SELECT
        fr.trip_id,
        fr.user_id,
        fr.flight_revenue + hr.hotel_revenue AS trip_revenue
    FROM flight_rev fr
    LEFT JOIN hotel_rev hr
        ON fr.trip_id = hr.trip_id
),
revenue_per_user AS (
    SELECT
        user_id,
        SUM(trip_revenue) AS total_revenue
    FROM trip_revenue
    GROUP BY user_id
),
user_level AS (
    SELECT
        spu.user_id,
        spu.total_sessions,
        spu.total_booked_sessions,
        COALESCE(tpu.total_trips,0) AS total_trips,
        COALESCE(tpu.total_trips,0) - COALESCE(tpu.cancelled_trips,0) AS completed_trips,
        COALESCE(tpu.cancelled_trips,0) AS cancelled_trips,
        COALESCE(rpu.total_revenue,0) AS total_revenue
    FROM sessions_per_user spu
    LEFT JOIN trips_per_user tpu
        ON spu.user_id = tpu.user_id
    LEFT JOIN revenue_per_user rpu
        ON spu.user_id = rpu.user_id
)
SELECT
    total_sessions,
    COUNT(*) AS users,
    SUM(total_trips) AS total_trips,
    SUM(completed_trips) AS total_completed_trips,
    ROUND(AVG(total_trips)::numeric,4) AS avg_trips_per_user,
    ROUND(AVG(completed_trips)::numeric,4) AS avg_complete_trips,
    ROUND(AVG(cancelled_trips)::numeric,4) AS avg_cancelled_trips,
    ROUND(SUM(cancelled_trips)::numeric / NULLIF(SUM(total_trips),0) * 100,4) AS cancel_rate,
    ROUND(AVG(total_revenue)::numeric,2) AS avg_revenue_per_user,
    ROUND(SUM(total_booked_sessions)::numeric / NULLIF(SUM(total_sessions),0), 4) AS conversion_rate
FROM user_level
GROUP BY total_sessions
ORDER BY total_sessions;
