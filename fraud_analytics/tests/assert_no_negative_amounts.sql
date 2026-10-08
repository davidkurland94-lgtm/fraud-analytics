-- Fails if any transaction has a negative amount.
SELECT *
FROM {{ ref('stg_transactions') }}
WHERE amount < 0
