WITH trip_base AS (
    SELECT
        trip_id,
        user_id,
        MIN(session_end) AS booking_time,
        MAX(CASE WHEN cancellation THEN 1 ELSE 0 END) AS is_cancelled,
        MAX(COALESCE(flight_discount_amount,0)) AS flight_discount,
        MAX(COALESCE(hotel_discount_amount,0)) AS hotel_discount
    FROM sessions
    WHERE trip_id IS NOT NULL AND session_start >= '2023-01-05'
    GROUP BY trip_id, user_id
),
trip_enriched AS (
	SELECT
	    tb.trip_id,
	    tb.user_id,
	    tb.booking_time,
	    tb.is_cancelled,
	    tb.flight_discount,
	    tb.hotel_discount,
	    f.base_fare_usd,
	    f.seats,
	    f.checked_bags,
	    f.departure_time,
	    f.return_time,
	    f.destination_airport_lat,
	    f.destination_airport_lon,
	    h.nights,
	    h.rooms,
	    h.hotel_per_room_usd,
	    h.check_in_time,
	    h.check_out_time,
	    u.home_airport_lat,
	    u.home_airport_lon
	FROM trip_base tb
	LEFT JOIN flights f ON tb.trip_id = f.trip_id
	LEFT JOIN hotels h ON tb.trip_id = h.trip_id
	LEFT JOIN users u ON tb.user_id = u.user_id
),
trip_complete AS (
	SELECT 
		--identity
		trip_id,
		user_id,
		--trip status
		is_cancelled,
		1 - is_cancelled AS is_completed,
		--product type
		CASE WHEN base_fare_usd IS NOT NULL THEN 1 ELSE 0 END AS has_flight,
		CASE WHEN hotel_per_room_usd IS NOT NULL THEN 1 ELSE 0 END AS has_hotel,
		CASE WHEN departure_time IS NOT NULL AND return_time IS NULL THEN 1 ELSE 0 END AS one_way_flight,
		--cleaning data
		CASE WHEN base_fare_usd IS NULL THEN NULL ELSE GREATEST(COALESCE(seats,1),1) END AS seats,
		checked_bags,
		CASE WHEN hotel_per_room_usd IS NULL THEN NULL ELSE GREATEST(ABS(COALESCE(nights,1)),1)END AS nights,
		nights AS nights_raw,
		CASE WHEN hotel_per_room_usd IS NULL THEN NULL ELSE GREATEST(COALESCE(rooms,1),1)END AS rooms,
		--revenue
		CASE WHEN is_cancelled = 0 THEN
					(COALESCE(base_fare_usd * GREATEST(seats,1) * (1 - flight_discount),0)) +
					(COALESCE (hotel_per_room_usd * GREATEST(rooms,1) * GREATEST(ABS(nights),1 ) * (1 - hotel_discount),0)) ELSE 0
					END AS total_revenue,
		--pricing
		CASE WHEN hotel_discount != 0 OR flight_discount != 0 THEN 1 ELSE 0 END AS has_discount,
		COALESCE (base_fare_usd, 0) AS flight_base_fare,
		CASE WHEN base_fare_usd IS NOT NULL THEN flight_discount ELSE 0 END AS flight_discount,
		COALESCE (hotel_per_room_usd, 0) AS hotel_fare, 
		CASE WHEN hotel_per_room_usd  IS NOT NULL THEN hotel_discount ELSE 0 END AS hotel_discount,
		--timing
		COALESCE (departure_time, check_in_time) AS trip_start_time,
		COALESCE (departure_time, check_in_time) - booking_time AS lead_time,
		--COALESCE (return_time, check_out_time ) - COALESCE (departure_time, check_in_time) AS trip_duration_days,
	  /*CASE WHEN departure_time IS NOT NULL AND return_time IS NOT NULL THEN EXTRACT(EPOCH FROM (return_time - departure_time)) / 86400
	        WHEN check_in_time IS NOT NULL AND check_out_time IS NOT NULL THEN EXTRACT(EPOCH FROM (check_out_time - check_in_time)) / 86400
	    ELSE NULL END AS trip_dur_days,*/
		departure_time,
		check_in_time,
		return_time,
		check_out_time,
		--distance
		CASE WHEN base_fare_usd IS NOT NULL THEN
	                6371 * acos(
	                    cos(radians(home_airport_lat)) *
	                    cos(radians(destination_airport_lat)) *
	                    cos(radians(destination_airport_lon - home_airport_lon)) +
	                    sin(radians(home_airport_lat)) *
	                    sin(radians(destination_airport_lat))
	                )
	            ELSE NULL
	        END AS flight_distance_km
	FROM trip_enriched
),
trip_duration_fixed AS (
	SELECT
	    *,    
	    CASE WHEN departure_time IS NOT NULL AND return_time IS NOT NULL THEN round(EXTRACT(EPOCH FROM (return_time - departure_time)) / 86400,6)
	         WHEN check_in_time IS NOT NULL AND check_out_time IS NOT NULL THEN round(EXTRACT(EPOCH FROM (check_out_time - check_in_time)) / 86400,6)
	         WHEN departure_time IS NOT NULL AND check_out_time IS NOT NULL THEN round(EXTRACT(EPOCH FROM (check_out_time - departure_time)) / 86400,6)
	         ELSE NULL
	    END AS trip_duration_days
	FROM trip_complete
),
trip_clean AS (
    SELECT *,
    	CASE WHEN trip_duration_days IS NULL THEN NULL
   			 WHEN trip_duration_days = 0 THEN 0
  			 WHEN trip_duration_days < 1 THEN 1
 			 ELSE round(trip_duration_days)
		END AS trip_duration_days_clean
    FROM trip_duration_fixed
    WHERE (nights_raw IS NULL OR nights_raw >= 0) AND (return_time IS NULL OR departure_time <> return_time)
),
trip_final AS (
	SELECT
		trip_id,
		user_id,
		is_cancelled,
		is_completed,
		round(total_revenue, 2) AS total_revenue,
		has_discount,
		flight_discount,
		hotel_discount,
		has_flight,
		has_hotel,
		one_way_flight,
		seats,
		checked_bags,
		nights,
		rooms,
		trip_start_time, 
		CASE WHEN is_cancelled = 1 THEN NULL ELSE lead_time END AS lead_time,
		CASE WHEN is_cancelled = 1 THEN NULL ELSE trip_duration_days_clean END AS trip_duration_days,
		CASE WHEN is_cancelled = 1 THEN NULL ELSE flight_distance_km END AS flight_distance_km
	FROM trip_clean
),
sessions_per_user AS (
    SELECT
        user_id,
        MAX(session_end) AS last_session,
        COUNT(*) AS total_sessions,
        ROUND(AVG(page_clicks),2) AS avg_page_clicks,
        SUM(page_clicks) AS total_page_clicks,
        ROUND(AVG(EXTRACT(EPOCH FROM (session_end - session_start)) / 60),2) AS avg_session_duration_minutes
    FROM sessions
    WHERE session_start >= '2023-01-05'
    GROUP BY user_id
),
trips_per_user AS (
    SELECT
        user_id,
        COUNT(*) AS total_trips,
        SUM(is_completed) AS completed_trips,
        SUM(total_revenue) AS total_revenue,
        ROUND(AVG(total_revenue),2) AS avg_revenue_per_trip,
        ROUND(AVG(trip_duration_days),2) AS avg_trip_duration,
        AVG(lead_time) AS avg_lead_time,
        ROUND(AVG(seats), 2) AS seats,
        ROUND(AVG(checked_bags), 2) AS checked_bags,
        ROUND(AVG(rooms), 2) AS rooms,
        ROUND(AVG(nights), 2) AS nights,
        -- ratios
        ROUND(AVG(is_cancelled),2) AS cancel_rate,
        ROUND(AVG(one_way_flight),2) AS one_way_ratio,
        ROUND(AVG(has_discount),2) AS discount_ratio,
        ROUND(AVG(has_flight),2) AS flight_ratio,
        ROUND(AVG(has_hotel),2) AS hotel_ratio,
        round(AVG(flight_distance_km)) AS avg_distance_km
    FROM trip_final
    GROUP BY user_id
),
user_static AS (
    SELECT
        user_id,
        '2023-08-30 00:00:00' - sign_up_date AS account_age_days,
        EXTRACT(YEAR FROM AGE('2023-08-30 00:00:00', birthdate)) AS age,
        has_children,
        married
    FROM users
),
user_features_base AS (
    SELECT
        spu.user_id,
        spu.total_sessions,
        ROUND(tpu.completed_trips::decimal / spu.total_sessions, 2) AS conversion_rate,
        spu.avg_page_clicks,
		spu.total_page_clicks,
		spu.avg_session_duration_minutes,
		spu.last_session,
        COALESCE(tpu.total_trips,0) AS total_trips,
        COALESCE(tpu.completed_trips,0) AS completed_trips,
        COALESCE(ROUND(tpu.total_trips::decimal / NULLIF(spu.total_sessions,0),2),0) AS trips_per_session,
        COALESCE(tpu.total_revenue,0) AS total_revenue,
        tpu.avg_revenue_per_trip,
        COALESCE(ROUND(tpu.total_revenue / NULLIF(spu.total_sessions,0), 2),0) AS revenue_per_session,
        tpu.avg_lead_time,
        tpu.avg_trip_duration,
        tpu.seats,
        tpu.checked_bags,
        tpu.rooms,
        tpu.nights,
        tpu.cancel_rate,
        tpu.one_way_ratio,
        tpu.discount_ratio,
        tpu.flight_ratio,
        tpu.hotel_ratio,
        tpu.avg_distance_km,
		us.account_age_days,
		us.age,
		us.has_children,
		us.married
    FROM sessions_per_user spu
    LEFT JOIN trips_per_user tpu
        ON spu.user_id = tpu.user_id
    LEFT JOIN user_static us
    ON spu.user_id = us.user_id
)
SELECT *
FROM user_features_base
WHERE total_sessions >= 5
ORDER BY 1 ASC;
