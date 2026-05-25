-- Gold layer table: final_joined_table
-- Purpose: Canonical analytics fact table. Inner join of cleaned users and
-- cleaned support tickets, preserving Fivetran metadata columns for lineage
-- traceability. This is the primary source for the Executive Overview and
-- Ticket Analysis dashboard pages.
--
-- Source: silver_cleaned_data.users_cleaned, silver_cleaned_data.support_tickets_cleaned
-- Sink:   gold_final_dev_table.final_joined_table

CREATE OR REPLACE TABLE databrickscourse.gold_final_dev_table.final_joined_table AS
SELECT
  u.user_id,
  u.first_name,
  u.last_name,
  u.email,
  u.country,
  u.signup_date,
  u.referral_source,
  u._row              AS user_row,
  u._fivetran_synced  AS user_fivetran_synced,
  st.ticket_id,
  st.created_date,
  st.category,
  st.priority,
  st.resolved_date,
  st.resolution_time_hours,
  st.satisfaction_score,
  st._row             AS ticket_row,
  st._fivetran_synced AS ticket_fivetran_synced
FROM databrickscourse.silver_cleaned_data.users_cleaned u
INNER JOIN databrickscourse.silver_cleaned_data.support_tickets_cleaned st
  ON u.user_id = st.user_id
ORDER BY u.user_id, st.created_date;
