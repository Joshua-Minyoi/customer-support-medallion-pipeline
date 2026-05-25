# Architecture

This document covers the design choices behind the pipeline. The top-level
README gives the overview. This file is for someone who wants to understand
*why* the pipeline looks the way it does.

## Layered design

The pipeline follows the Databricks Medallion pattern: bronze for raw landed
data, silver for cleaned and conformed data, gold for analytics-ready
aggregates.

```
┌─────────────┐    ┌──────────┐    ┌────────────────────────┐
│ Google      │    │          │    │  Bronze                │
│ Sheets      │───▶│ Fivetran │───▶│  databrickscourse      │
│ (source)    │    │          │    │  .google_sheets        │
└─────────────┘    └──────────┘    │  - users_dirty         │
                                   │  - support_tickets     │
                                   └───────────┬────────────┘
                                               │
                                  PySpark (notebook 01)
                                               ▼
                                   ┌────────────────────────┐
                                   │  Silver                │
                                   │  silver_cleaned_data   │
                                   │  - users_cleaned       │
                                   │  - support_tickets_    │
                                   │    cleaned             │
                                   └───────────┬────────────┘
                                               │
                                  SQL (notebook 02)
                                               ▼
                                   ┌────────────────────────┐
                                   │  Gold                  │
                                   │  gold_final_dev_table  │
                                   │  - final_joined_table  │
                                   │  - user_ticket_gaps    │
                                   └───────────┬────────────┘
                                               │
                                               ▼
                                   Databricks Dashboard
                                   (3 pages)
```

## Why these layers carry these responsibilities

**Bronze stays raw on purpose.** Fivetran lands the Google Sheets data as-is,
including the messy `signup_date` formats and any duplicate `user_id` rows.
The principle is that the bronze layer is the immutable system-of-record copy.
If a downstream transformation has a bug, the fix happens in silver or gold,
not by rewriting bronze.

**Silver does cleaning and conforming, not business logic.** Two transformations
happen here, both in `notebooks/01_bronze_to_silver_transformation.ipynb`:

1. `signup_date` is normalised. Some source rows use `.` as the date separator,
   others use `/`. The notebook first replaces `.` with `/`, then parses as
   `M/d/yy`. Doing this in silver means every downstream consumer gets a
   proper date type without re-applying the fix.
2. `dropDuplicates(["user_id"])` removes duplicate user rows. The choice to
   dedup on `user_id` only (rather than the full row) is deliberate: if two
   rows share a `user_id` but differ in, say, `country`, we still keep only
   one. In a real system the rule for which row wins would need to be
   explicit (latest by `_fivetran_synced`, for example). For this dataset the
   duplicates are exact, so the simple form suffices.

`support_tickets` passes through silver without transformation because the
source data is already clean. The write still happens so that downstream gold
queries depend only on `silver_cleaned_data`, not on `google_sheets`. This
preserves the layer abstraction: gold never reads bronze directly.

**Gold serves analytics.** Two tables, each with a clear purpose:

- `final_joined_table` is the canonical fact table. Inner join of users and
  tickets, one row per ticket with user attributes denormalised in. This is
  what the Executive Overview and Ticket Analysis dashboard pages query.
- `user_ticket_gaps` is a derived analytical view. For each ticket, a
  `LAG` window function partitioned by `user_id` and ordered by
  `created_date` finds the prior ticket and computes `DATEDIFF` between them.
  This powers the User Engagement page's "days since last contact" metric.

Two tables rather than one wide table because the second is sparse: it only
contains users with two or more tickets, which is a strict subset. Joining
that sparsity into the main fact table would either lose rows or introduce
nulls that confuse the dashboard.

## Orchestration

The two notebooks run as a single Databricks Job (`Data Transformation Job -
Bronze to Gold`) with two sequential tasks. `silver_to_gold` depends on
`bronze_to_silver` finishing successfully. Both tasks run on serverless
compute. End-to-end the job completes in 49 seconds for this dataset.

Email notifications fire on success and failure to a monitoring inbox. In a
production setting these would route to a paged on-call channel rather than
plain email, but for a single-operator portfolio build email is sufficient.

## Unity Catalog placement

Everything lives under a single catalog, `databrickscourse`, with one schema
per layer:

| Layer  | Schema                | Tables                                          |
|--------|-----------------------|-------------------------------------------------|
| Bronze | `google_sheets`       | `users_dirty`, `support_tickets`                |
| Silver | `silver_cleaned_data` | `users_cleaned`, `support_tickets_cleaned`      |
| Gold   | `gold_final_dev_table`| `final_joined_table`, `user_ticket_gaps`        |

The bronze schema is named `google_sheets` because Fivetran defaults the
destination schema to the source connector name. Keeping that default makes
the lineage easier to read: anyone looking at the catalog sees the data's
origin in the schema name itself.

## What the dashboard reads

The Databricks dashboard has three pages, each backed by gold-layer queries:

- **Executive Overview** reads `final_joined_table` for KPIs (total tickets,
  average resolution time, satisfaction score) and a monthly volume trend.
- **Ticket Analysis** reads `final_joined_table` for category, priority, and
  country breakdowns plus resolution time by category.
- **User Engagement** reads `user_ticket_gaps` for the days-since-last-contact
  table and bar chart.

PDF exports of all three pages live in `dashboard/`.

## Decisions worth flagging

A few small choices that aren't obvious from the code:

- **No watermarking or merge logic.** Both silver writes are `overwrite`. For
  this dataset the source CSVs are static, so full refresh is fine. If the
  source were incrementally updated, the silver writes would become
  `MERGE INTO` on `user_id` / `ticket_id` with a watermark from
  `_fivetran_synced`.
- **Fivetran metadata columns flow through to gold.** `_row` and
  `_fivetran_synced` are kept on `final_joined_table` as
  `user_row` / `user_fivetran_synced` and `ticket_row` /
  `ticket_fivetran_synced`. This means a downstream analyst can answer "when
  was this row last synced from source" without going back to bronze.
- **The gold layer is named `gold_final_dev_table`.** The `_dev` suffix is a
  reminder that this is a development environment. In a multi-environment
  setup the same notebooks would be parameterised to write to
  `gold_final_prod` in production.
