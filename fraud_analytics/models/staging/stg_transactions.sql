-- The purpose of this model is to transform raw events into clean transactions.
-- Cleaning, de-duping, and standardization is required

-- `time` is seconds elapsed since the first transaction in the dataset, not a timestamp.
-- The dataset covers two days in September 2013, but the exact start date isn't published,
-- so anchor it to an assumed start (override with --vars '{"transactions_start_ts": "..."}').
{% set start_ts = var('transactions_start_ts', '2013-09-01 00:00:00') %}

WITH source AS (
  SELECT * FROM {{ source('raw_data', 'transactions') }}
),

-- The raw data contains exact duplicate rows; drop them so each transaction appears once
-- and transaction_id below is deterministic (no ties in the ORDER BY).
deduped AS (
  SELECT DISTINCT * FROM source
),

with_ts AS (
  SELECT
    *,
    TIMESTAMP_ADD(
      TIMESTAMP('{{ start_ts }}'),
      INTERVAL CAST(time AS INT64) SECOND
    ) AS transaction_ts
  FROM deduped
)

SELECT
  ROW_NUMBER() OVER (
    ORDER BY time, amount{% for i in range(1, 29) %}, v{{ i }}{% endfor %}, class
  ) AS transaction_id,
  CAST(time AS INT64) AS seconds_since_first_transaction,
  transaction_ts,
  DATE(transaction_ts) AS transaction_date,
  TIME(transaction_ts) AS transaction_time,
  amount,
  CAST(class AS INT64) AS is_fraudulent,
  (
    {% for i in range(1, 29) %}
      ABS(v{{ i }}){% if not loop.last %} +{% endif %}
    {% endfor %}
  ) / 28 AS feature_score -- Getting a sense for how deviated a transaction is from the rest
FROM with_ts

