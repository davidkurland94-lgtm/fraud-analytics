-- One row per transaction with rule-based fraud flags and an overall risk level.
-- Hour-of-day flags depend on the assumed transactions_start_ts (see stg_transactions).

WITH transactions AS (
  SELECT * FROM {{ ref('stg_transactions') }}
),

-- Amount cutoffs computed once over the whole table (one row), then joined onto every transaction.
-- APPROX_QUANTILES(amount, 100) splits amounts into 100 buckets; OFFSET(n) picks the n-th percentile.
thresholds AS (
  SELECT
    APPROX_QUANTILES(amount, 100)[OFFSET(90)] AS amount_p90,
    APPROX_QUANTILES(amount, 100)[OFFSET(95)] AS amount_p95
  FROM transactions
),

flagged AS (
  SELECT
    t.transaction_id,
    t.transaction_ts,
    t.amount,
    t.feature_score,
    t.is_fraudulent,
    t.amount > th.amount_p95 AS flag_large_amount,
    t.amount > th.amount_p90 AS flag_elevated_amount,
    EXTRACT(HOUR FROM t.transaction_time)
      BETWEEN {{ var('unusual_hour_start') }} AND {{ var('unusual_hour_end') }} AS flag_unusual_time,
    t.feature_score > {{ var('high_risk_score_threshold') }} AS flag_high_risk_score
  FROM transactions AS t
  CROSS JOIN thresholds AS th
)

SELECT
  *,
  CASE
    WHEN flag_large_amount AND flag_high_risk_score THEN 'high'
    WHEN flag_elevated_amount THEN 'medium'
    ELSE 'low'
  END AS risk_level
FROM flagged
