-- Gold layer table: user_ticket_gaps
-- Purpose: For each support ticket, identify the previous ticket from the same
-- user and compute the number of days between consecutive tickets. Used by the
-- User Engagement dashboard to surface re-contact patterns and silent users.
--
-- Source: silver_cleaned_data.support_tickets_cleaned, silver_cleaned_data.users_cleaned
-- Sink:   gold_final_dev_table.user_ticket_gaps

CREATE SCHEMA IF NOT EXISTS databrickscourse.gold_final_dev_table;

CREATE OR REPLACE TABLE databrickscourse.gold_final_dev_table.user_ticket_gaps AS
WITH ticket_gaps AS (
  SELECT
    st.user_id,
    u.first_name,
    u.last_name,
    u.email,
    u.country,
    u.signup_date,
    st.ticket_id,
    st.created_date,
    st.category,
    st.priority,
    st.resolved_date,
    st.resolution_time_hours,
    st.satisfaction_score,
    LAG(st.ticket_id)    OVER (PARTITION BY st.user_id ORDER BY st.created_date) AS previous_ticket_id,
    LAG(st.created_date) OVER (PARTITION BY st.user_id ORDER BY st.created_date) AS previous_ticket_date,
    DATEDIFF(
      st.created_date,
      LAG(st.created_date) OVER (PARTITION BY st.user_id ORDER BY st.created_date)
    ) AS days_since_previous_ticket
  FROM databrickscourse.silver_cleaned_data.support_tickets_cleaned st
  INNER JOIN databrickscourse.silver_cleaned_data.users_cleaned u
    ON st.user_id = u.user_id
)
SELECT
  user_id,
  first_name,
  last_name,
  email,
  country,
  signup_date,
  ticket_id,
  created_date,
  category,
  priority,
  resolved_date,
  resolution_time_hours,
  satisfaction_score,
  previous_ticket_id,
  previous_ticket_date,
  days_since_previous_ticket
FROM ticket_gaps
WHERE days_since_previous_ticket IS NOT NULL
ORDER BY user_id, created_date;
