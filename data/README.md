# Data

Raw and user-level datasets are **not versioned** in this repository (see
[`.gitignore`](../.gitignore)). They are fully reproducible by running the
queries in [`sql/`](../sql) against the TravelTide database and saving the
results to the paths below. Only small aggregated tables are tracked.

```
data/
├── raw/            # query exports, not versioned
└── processed/      # analysis outputs; only aggregates are versioned
    └── segments/   # one user list per segment, not versioned
```

## How to reproduce

The source is the TravelTide PostgreSQL database (read-only credentials are
provided by the bootcamp and are not stored here). Run each query and export
its result as CSV:

| Query | Output | Tracked |
|---|---|---|
| `sql/01_cutoff_criteria_summary.sql` | `data/processed/cutoff_criteria_summary.csv` | yes |
| `sql/02_sessions_per_user.sql` | `data/raw/sessions_per_user.csv` | no (8 MB) |
| `sql/03_booking_rate.sql` | `data/processed/booking_rate.csv` | yes |
| `sql/04_cumulative_revenue_per_sessions.sql` | `data/processed/cumulative_revenue_per_sessions.csv` | yes |
| `sql/05_user_features_v1.sql` | *(superseded by v2)* | no |
| `sql/06_user_features_v2.sql` | `data/raw/user_features.csv` | no (30 MB) |

Then run the notebooks in order; `02_feature_engineering_and_segmentation.ipynb`
writes `user_features_labels.csv`, `user_segments.csv` and the per-segment
files in `processed/segments/`.

## Datasets

### `raw/sessions_per_user.csv` — 978,709 rows
Session count per user, used to pick the cohort cutoff.

| Column | Description |
|---|---|
| `user_id` | User identifier |
| `total_sessions` | Number of sessions in the observation window |

### `raw/user_features.csv` — 189,432 rows
User-level feature table (output of `06_user_features_v2.sql`) and the input to
the segmentation. One row per user in the cohort (`total_sessions >= 5`).

| Column | Description |
|---|---|
| `user_id` | User identifier |
| `total_sessions` | Sessions in the observation window |
| `conversion_rate` | Share of sessions that ended in a booking |
| `avg_page_clicks`, `total_page_clicks` | Browsing intensity |
| `avg_session_duration_minutes` | Mean session length |
| `last_session` | Timestamp of the most recent session |
| `total_trips`, `completed_trips` | Booked trips and non-cancelled trips |
| `trips_per_session` | Booking frequency |
| `total_revenue`, `avg_revenue_per_trip`, `revenue_per_session` | Monetary value (USD) |
| `avg_lead_time` | Mean days between booking and departure |
| `avg_trip_duration` | Mean trip length in days |
| `seats`, `checked_bags`, `rooms`, `nights` | Mean booking composition |
| `cancel_rate` | Share of cancelled trips |
| `one_way_ratio`, `discount_ratio` | Share of one-way flights / discounted bookings |
| `flight_ratio`, `hotel_ratio` | Product mix |
| `avg_distance_km` | Mean flight distance |
| `account_age_days`, `age`, `has_children`, `married` | Account and demographic attributes |

### `processed/user_features_labels.csv` — 189,432 rows
`raw/user_features.csv` plus the helper flags `has_trips`, `has_revenue` and the
assigned `segment_label`.

### `processed/user_segments.csv` — 189,432 rows
The deliverable handed to marketing: `user_id`, `segment_label`.

### `processed/segment_summary.csv` — 6 rows *(tracked)*
Aggregated profile per segment: user count, share of users, share of revenue
and segment means for the main behavioural metrics. This is the table behind
the segment profiles in the reports.

### `processed/cutoff_criteria_summary.csv`, `booking_rate.csv`, `cumulative_revenue_per_sessions.csv` *(tracked)*
Cohort diagnostics by session count: users, trips, cancellation rate, average
revenue per user, booking rate and cumulative revenue share. These support the
`total_sessions >= 5` cutoff.

## Privacy

`user_id` is a synthetic identifier from the bootcamp dataset; the data contains
no names, emails or other direct identifiers. Even so, user-level files are kept
out of version control and only aggregates are published.
