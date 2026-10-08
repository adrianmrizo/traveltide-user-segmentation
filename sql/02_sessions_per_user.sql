--what percent of active users represents our cohort User per Sessions Bucket
with active_users as (
	select
		user_id,
	    count(*) as total_sessions
	from sessions
	where session_start >= '2023-01-05'
	group by user_id
)
select
	count(*) as total_active_users,
	sum(case when total_sessions >= 4 then 1 end) as cohort_users,
	round(sum(case when total_sessions >= 4 then 1 end)::decimal / count(*) * 100, 2) as percent_of_active_users
from active_users
;