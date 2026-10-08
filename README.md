# Credit Card Fraud Analytics (dbt + BigQuery)

A small dbt project that turns the [Kaggle credit card fraud dataset](https://www.kaggle.com/datasets/mlg-ulb/creditcardfraud)
(~284k transactions over two days in September 2013) into clean, tested tables with rule-based fraud flags.

## What to query

Models are built in BigQuery in the `raw_data` dataset (project `fraud-analytics-510507`).

| Table | Grain | Use it for |
|---|---|---|
| `fact_fraud_indicators` | one row per transaction | **Start here.** Fraud flags, `risk_level`, and the true `is_fraudulent` label |
| `stg_transactions` | one row per transaction | Cleaned, deduplicated transactions with a derived timestamp and `feature_score` |

**Key columns in `fact_fraud_indicators`**

| Column | Meaning |
|---|---|
| `flag_large_amount` | Amount above the 95th percentile |
| `flag_elevated_amount` | Amount above the 90th percentile |
| `flag_unusual_time` | Transaction between 2am and 5am |
| `flag_high_risk_score` | `feature_score` (mean absolute value of the 28 PCA features) above 1.0 |
| `risk_level` | `high` = large amount **and** high risk score · `medium` = elevated amount · `low` = everything else |
| `is_fraudulent` | Ground-truth label (1 = fraud) |

### Example: how well does `risk_level` separate fraud?

```sql
SELECT
  risk_level,
  COUNT(*)                            AS transactions,
  SUM(is_fraudulent)                  AS fraud_cases,
  ROUND(AVG(is_fraudulent) * 100, 2)  AS fraud_rate_pct
FROM `fraud-analytics-510507.raw_data.fact_fraud_indicators`
GROUP BY risk_level
ORDER BY fraud_rate_pct DESC;
```

| risk_level | transactions | fraud_cases | fraud_rate_pct |
|---|---:|---:|---:|
| high | 3,982 | 33 | 0.83 |
| medium | 24,358 | 49 | 0.20 |
| low | 255,385 | 391 | 0.15 |

`high`-risk transactions are ~5x more likely to be fraud than `low`, but most fraud still lands in `low`.
The simple rules are a starting point, not a classifier.

### Example: fraud by hour of day

```sql
SELECT
  EXTRACT(HOUR FROM transaction_ts)   AS hour,
  COUNT(*)                            AS transactions,
  SUM(is_fraudulent)                  AS fraud_cases
FROM `fraud-analytics-510507.raw_data.fact_fraud_indicators`
GROUP BY hour
ORDER BY hour;
```

## Project structure

```
fraud_analytics/
├── models/
│   ├── staging/
│   │   ├── _sources.yml            # raw_data.transactions (loaded from the Kaggle CSV)
│   │   ├── _staging.yml            # tests for stg_transactions
│   │   └── stg_transactions.sql    # dedupe, derive timestamp + feature_score
│   └── marts/
│       ├── _marts.yml              # column docs + tests
│       └── fact_fraud_indicators.sql
├── tests/
│   └── assert_no_negative_amounts.sql
└── dbt_project.yml                 # thresholds live here as vars
```

## Running it

```bash
cd fraud_analytics
dbt build          # builds models and runs all tests
```

Thresholds are dbt vars in `dbt_project.yml` and can be overridden at run time:

```bash
dbt build --vars '{"high_risk_score_threshold": 1.5, "unusual_hour_start": 1}'
```

## Assumptions and caveats

- **Timestamps are assumed.** The source `time` column is seconds since the first transaction; the dataset
  doesn't publish the real start. We anchor it to `2013-09-01 00:00:00` (`transactions_start_ts` var), so
  hour-of-day results depend on that assumption.
- **Duplicates removed.** The raw table has exact duplicate rows; staging drops them (284,806 → 283,725 rows).
- **Features are anonymized.** `V1`–`V28` are PCA components with no business meaning, so
  `feature_score` is only a rough measure of how unusual a transaction is.

## Tech stack

dbt · BigQuery (GCP)
