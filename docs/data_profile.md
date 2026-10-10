# Data profile: Olist RAW

Filled in on Day 4 from `snowflake/02_profile_raw.sql`. Each issue says what
was found, why it matters, and how the pipeline handles it.

## Row counts

| Table | Rows | Expected | Match |
|---|---:|---:|:-:|
| orders | | 99,441 | |
| order_items | | 112,650 | |
| order_payments | | 103,886 | |
| order_reviews | | 99,224 | |
| customers | | 99,441 | |
| sellers | | 3,095 | |
| products | | 32,951 | |
| product_category_name_translation | | 71 | |
| geolocation | | 1,000,163 | |

Order date range: ____ to ____

## Data quality issues

| # | Issue | Count | Why it matters | Handled in | Guarded by test |
|---|---|---:|---|---|---|
| 1 | Duplicate / near-duplicate geolocation rows per zip prefix | | Joining raw geolocation would multiply rows | `stg_geolocation` (one row per prefix) | `unique` on `zip_code_prefix` |
| 2 | Geolocation points outside Brazil | | Wrong map points in Power BI | `stg_geolocation` bounding box filter | |
| 3 | `review_id` not unique | | Naive unique test fails; reviews could double-count | `stg_reviews` grain = (review_id, order_id) | `unique` on `review_key` |
| 4 | Delivered orders with no delivery date | | Late flag cannot be computed | `int_order_delivery_metrics` (Week 2) | |
| 5 | Orders with no items | | Revenue = 0, skews AOV | Filter / flag in `fct_orders` (Week 2) | |
| 6 | Product categories with no English translation | | Blank category in dashboard | `dim_products` coalesce to Portuguese (Week 2) | |
| 7 | Products with no category | | | | |
| 8 | Payment total differs from items + freight by more than 1% | | Revenue definitions disagree | Custom test (Week 3) | |
| 9 | customer_id is per order, not per person | | Repeat-customer rate would be ~0% | Use `customer_unique_id` | |
| 10 | Typo in source columns (`lenght`) | 2 columns | Readability | `stg_products` renames | |

## Notes

_Anything surprising you found while profiling._
