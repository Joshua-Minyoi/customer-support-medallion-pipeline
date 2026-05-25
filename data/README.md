# Source Data

Two CSV files seed the pipeline. In the actual deployment they live in a Google
Sheet and Fivetran replicates them into Databricks. These copies are committed
so the notebooks can be reproduced without setting up Fivetran.

## `users_dirty.csv`

50 user records. Deliberately messy to exercise the bronze-to-silver cleaning
step.

| Column          | Type   | Notes                                          |
|-----------------|--------|------------------------------------------------|
| user_id         | string | Format `USR_NNNN`. Primary key after dedup.    |
| first_name      | string |                                                |
| last_name       | string |                                                |
| email           | string |                                                |
| signup_date     | string | Mixed formats: `M/d/yy` and `M.d.yy`.          |
| country         | string | UK, US, AU, CA.                                |
| referral_source | string | `google_ads`, `organic`, `referral`, etc.      |

**Known data quality issues**

- `signup_date` uses inconsistent separators. Some rows use `.`, others use `/`.
  The silver-layer notebook normalises both to `/` then parses as `M/d/yy`.
- Duplicate `user_id` values exist. The silver layer applies
  `dropDuplicates(["user_id"])`.

## `support_tickets.csv`

40 support ticket records, joined on `user_id`.

| Column                 | Type   | Notes                                                  |
|------------------------|--------|--------------------------------------------------------|
| ticket_id              | string | Format `TKT_NNNNNN`. Primary key.                      |
| user_id                | string | Foreign key to users.                                  |
| category               | string | `billing`, `technical`, `onboarding`, `account`, `feature_request`. |
| priority               | string | `low`, `medium`, `high`, `critical`.                   |
| created_date           | date   | When the ticket was opened.                            |
| resolved_date          | date   | Nullable. Empty for unresolved tickets.                |
| resolution_time_hours  | float  | Nullable. Empty for unresolved tickets.                |
| satisfaction_score     | int    | Nullable. 1 to 5 scale. Only present where surveyed.   |

## Fivetran-injected columns

When Fivetran lands the data in the bronze layer it adds two metadata columns
to each table: `_row` (the source row position) and `_fivetran_synced` (the
sync timestamp). These are preserved through to the gold `final_joined_table`
for lineage traceability.
