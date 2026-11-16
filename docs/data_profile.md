# Data profile: Olist RAW

Profiled on 2026-11-06 with `snowflake/02_profile_raw.sql`, run against `OLIST.RAW`
after the first load. Every number below comes from those queries. Each issue says
what was found, why it matters, and how the pipeline handles it.

## Row counts

| Table | Rows | Expected | Match |
|---|---:|---:|:-:|
| orders | 99,441 | 99,441 | ✅ |
| order_items | 112,650 | 112,650 | ✅ |
| order_payments | 103,886 | 103,886 | ✅ |
| order_reviews | 99,224 | 99,224 | ✅ |
| customers | 99,441 | 99,441 | ✅ |
| sellers | 3,095 | 3,095 | ✅ |
| products | 32,951 | 32,951 | ✅ |
| product_category_name_translation | 71 | 71 | ✅ |
| geolocation | 1,000,163 | 1,000,163 | ✅ |

A second run of `ingestion/load_raw.py` reported `PUT ... SKIPPED` and
`Copy executed with 0 files processed` for every file, with identical row counts:
the load is **idempotent** (safe to rerun, no duplicate rows).

**Order date range:** 2016-09-04 21:15:19 to 2018-10-17 17:30:18 (about 2 years).
`dim_date` will cover 2016-01-01 to 2018-12-31.

## Keys and grain

| Key | Rows | Distinct | Unique? |
|---|---:|---:|:-:|
| orders.order_id | 99,441 | 99,441 | ✅ |
| customers.customer_id | 99,441 | 99,441 | ✅ |
| sellers.seller_id | 3,095 | 3,095 | ✅ |
| products.product_id | 32,951 | 32,951 | ✅ |
| order_items (order_id, order_item_id) | 112,650 | 112,650 | ✅ composite key |
| order_payments (order_id, payment_sequential) | 103,886 | 103,886 | ✅ composite key |
| **order_reviews.review_id** | **99,224** | **98,410** | ❌ |
| order_reviews (review_id, order_id) | 99,224 | 99,224 | ✅ true grain |

## Data quality issues

| # | Issue | Count | Why it matters | Handled in | Guarded by |
|---|---|---:|---|---|---|
| 1 | Geolocation has many rows per zip prefix | 1,000,163 rows for 19,015 prefixes (≈53 per prefix) | Joining customers to raw geolocation by zip would multiply each row ≈53 times | `stg_geolocation`: one row per prefix (average lat/lng, most common city/state) | `unique` + `not_null` on `zip_code_prefix` |
| 2 | Exact duplicate geolocation rows | 261,831 (26.2%) | Same as #1 | `stg_geolocation` aggregation | same |
| 3 | Geolocation points outside Brazil | 42 | Stray points on the Power BI map | `stg_geolocation` bounding-box filter (lat −34…6, lng −74…−34) | — |
| 4 | Same zip prefix with several city spellings | up to 5 per prefix | Accent/case variants split one city into several | `stg_geolocation` keeps the most common spelling (`MODE`) | — |
| 5 | `review_id` not unique | 814 rows reuse an id across different orders; 0 exact duplicate rows | A `unique` test on `review_id` fails; joining on it double-counts | `stg_reviews` grain = (review_id, order_id), key `review_key` | `unique` on `review_key` |
| 6 | Orders with more than one review | 551 extra review rows; max 3 reviews per order (4 orders), the rest have 2 | Joining reviews to `fct_orders` would duplicate orders and inflate revenue | Latest review per order in the intermediate layer before joining (Week 2) | `unique` on `fct_orders.order_id` |
| 7 | Orders with no review | 768 | `review_score` is null for these orders | Averages use only orders with a score; documented in the metric definition | — |
| 8 | `customer_id` is per order, not per person | 99,441 customer_ids vs 96,096 people (`customer_unique_id`) | Repeat-customer rate would be 0% using `customer_id` | Repeat and cohort metrics use `customer_unique_id` | `not_null` on `customer_unique_id` |
| 9 | "delivered" orders with no delivery date | 8 | Late flag cannot be computed | `is_late` left null (not "on time") in the delivery metrics model (Week 2) | — |
| 10 | Delivered orders missing other timestamps | 14 no approval date, 2 no carrier date | Minor gaps in lifecycle durations | Durations left null where a timestamp is missing | — |
| 11 | Canceled orders with a delivery date | 6 | Delivered but canceled (likely returns) | Excluded from revenue by the revenue definition | — |
| 12 | Carrier date before purchase date | 166 | "Time to ship" would be negative | Negative durations set to null in the delivery metrics model (Week 2) | — |
| 13 | Orders with no items | 775 (603 unavailable, 164 canceled, 5 created, 2 invoiced, 1 shipped) | An inner join to items silently drops them and undercounts cancellations | `fct_orders` starts from orders and LEFT JOINs items; `item_count = 0`, revenue 0; AOV divides by orders with items | — |
| 14 | Order with no payment | 1 | Payment-reconciliation test must not fail on a missing value | Custom test compares only orders that have both items and payments | — |
| 15 | Payment total ≠ items + freight by more than 1% | 254 of 98,665 orders (0.26%) | Likely credit-card instalment interest; revenue definitions could disagree | Revenue = item price (not payments), documented | Custom test with `warn_if: ">0"`, `error_if: ">1000"` (Week 3) |
| 16 | Zero-value payments | 9 (including 3 `not_defined` payments totalling R$0) | Harmless, but skews "average payment" slightly | Kept; documented | `accepted_values` on `payment_type` includes `not_defined` |
| 17 | Products with no category | 610 (1.9%) | Blank category in the dashboard | `dim_products` labels them `unknown` (Week 2) | — |
| 18 | Categories with no English translation | 2 categories, 13 products: `pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos` | Untranslated category names in the dashboard | dbt seed `category_translation_fixes.csv` fills them in (Week 2) | — |
| 19 | Customer zip prefixes with no geolocation match | 157 distinct prefixes | Some customers get no coordinates on the map | `dim_geography` LEFT JOIN; missing coordinates stay null | — |
| 20 | Typo in source column names (`lenght`) | 2 columns | Readability | `stg_products` renames to `length` | — |

## Checks that came back clean

- **Delivered before purchase:** 0. **Approved before purchase:** 0. The planned custom test "delivered date never before purchase date" will pass.
- **Values that fail to cast** in `order_items` (price, freight, shipping date): 0, 0, 0.
- **Zip leading zeros:** 0 customer zips shorter than 5 characters; smallest is `01003`. Storing RAW as text preserved them (a numeric load would have turned `06900` into `6900`).
- **Order statuses:** exactly 8 values, matching the `accepted_values` test in staging.
- **Review scores:** only 1 to 5, no nulls, and they sum to all 99,224 rows.

## Profile facts for the business questions

**Order status mix**

| Status | Orders |
|---|---:|
| delivered | 96,478 (97.0%) |
| shipped | 1,107 |
| canceled | 625 |
| unavailable | 609 |
| invoiced | 314 |
| processing | 301 |
| created | 5 |
| approved | 2 |

**Payment mix** (BRL, ≈R$16.0M total across 103,886 payments)

| Type | Payments | Share of payments | Total value | Share of value |
|---|---:|---:|---:|---:|
| credit_card | 76,795 | 73.9% | R$12,542,084.19 | 78.3% |
| boleto | 19,784 | 19.0% | R$2,869,361.27 | 17.9% |
| voucher | 5,775 | 5.6% | R$379,436.87 | 2.4% |
| debit_card | 1,529 | 1.5% | R$217,989.79 | 1.4% |
| not_defined | 3 | 0.0% | R$0.00 | 0.0% |

Vouchers are frequent but small (≈R$66 per payment), so they are usually part of a split payment.

**Review scores** (average ≈ 4.09)

| Score | Reviews | Share |
|---|---:|---:|
| 1 | 11,424 | 11.5% |
| 2 | 3,151 | 3.2% |
| 3 | 8,179 | 8.2% |
| 4 | 19,142 | 19.3% |
| 5 | 57,328 | 57.8% |

J-shaped: 1-star is far more common than 2-star. Business question 2 tests whether late
delivery explains it.

**Repeat customers:** 96,096 people placed 99,441 orders, so at most 3,345 orders are
repeat purchases. The repeat rate will be low (around 3%).

## Modelling decisions this profile drives (Week 2)

1. `fct_orders` is one row per order: start from orders, LEFT JOIN items, aggregate items first.
2. Reduce reviews to the latest review per order before joining to `fct_orders`.
3. Use `customer_unique_id` for every customer-level metric.
4. `is_late` is null when the delivery date is missing; negative durations become null.
5. Revenue = sum of item price for orders not canceled or unavailable (not payment value).
6. Average order value divides by orders that have at least one item.
7. Add a seed for the 2 missing category translations; label null categories `unknown`.
8. Check orders per month at the start and end of the date range before building monthly charts; very thin months may need to be excluded from trend visuals.
