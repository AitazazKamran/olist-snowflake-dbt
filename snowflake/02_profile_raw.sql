-- =============================================================================
-- 02_profile_raw.sql  |  Day 4: profile RAW and find data quality issues
-- -----------------------------------------------------------------------------
-- Run each query, then write what you find in docs/data_profile.md:
-- the number, why it matters, and how staging or a test will handle it.
-- Every confirmed issue is an interview story ("I found X, I handled it with Y,
-- and a test now guards it").
-- =============================================================================

USE ROLE TRANSFORMER;
USE WAREHOUSE OLIST_WH;
USE SCHEMA OLIST.RAW;


-- 1. Primary key checks: are the "id" columns really unique?
SELECT 'orders.order_id'       AS key_column, COUNT(*) AS total_rows, COUNT(DISTINCT order_id)    AS distinct_keys FROM ORDERS
UNION ALL SELECT 'customers.customer_id',    COUNT(*), COUNT(DISTINCT customer_id)  FROM CUSTOMERS
UNION ALL SELECT 'sellers.seller_id',        COUNT(*), COUNT(DISTINCT seller_id)    FROM SELLERS
UNION ALL SELECT 'products.product_id',      COUNT(*), COUNT(DISTINCT product_id)   FROM PRODUCTS
UNION ALL SELECT 'order_reviews.review_id',  COUNT(*), COUNT(DISTINCT review_id)    FROM ORDER_REVIEWS
UNION ALL SELECT 'order_items (order_id, order_item_id)', COUNT(*),
          COUNT(DISTINCT order_id || '-' || order_item_id) FROM ORDER_ITEMS
UNION ALL SELECT 'order_payments (order_id, payment_sequential)', COUNT(*),
          COUNT(DISTINCT order_id || '-' || payment_sequential) FROM ORDER_PAYMENTS;


-- 2. Reviews: review_id repeats. Is it the same review on several orders,
--    or exact duplicate rows? This decides the staging grain.
SELECT
    COUNT(*)                                        AS total_rows,
    COUNT(DISTINCT review_id)                       AS distinct_review_ids,
    COUNT(DISTINCT review_id || '-' || order_id)    AS distinct_review_order_pairs,
    COUNT(DISTINCT order_id)                        AS orders_with_reviews
FROM ORDER_REVIEWS;

-- Orders with more than one review
SELECT order_id, COUNT(*) AS n_reviews
FROM ORDER_REVIEWS
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY n_reviews DESC
LIMIT 20;


-- 3. Customers: customer_id is per order; customer_unique_id is the real person.
--    This matters for the repeat-customer metric.
SELECT
    COUNT(DISTINCT customer_id)        AS customer_ids,
    COUNT(DISTINCT customer_unique_id) AS unique_people
FROM CUSTOMERS;


-- 4. Geolocation: many rows per zip prefix (duplicates and near-duplicates).
SELECT
    COUNT(*)                                     AS total_rows,
    COUNT(DISTINCT geolocation_zip_code_prefix)  AS distinct_zip_prefixes,
    COUNT(*) - COUNT(DISTINCT geolocation_zip_code_prefix,
                     geolocation_lat, geolocation_lng,
                     geolocation_city, geolocation_state) AS exact_duplicate_rows
FROM GEOLOCATION;

-- Coordinates outside Brazil's rough bounding box (lat -34 to 6, lng -74 to -34)
SELECT COUNT(*) AS points_outside_brazil
FROM GEOLOCATION
WHERE TRY_TO_DOUBLE(geolocation_lat) NOT BETWEEN -34 AND 6
   OR TRY_TO_DOUBLE(geolocation_lng) NOT BETWEEN -74 AND -34;

-- Same zip prefix spelled with different city names (accents, case)
SELECT geolocation_zip_code_prefix, COUNT(DISTINCT geolocation_city) AS city_spellings
FROM GEOLOCATION
GROUP BY 1
HAVING COUNT(DISTINCT geolocation_city) > 1
ORDER BY city_spellings DESC
LIMIT 20;


-- 5. Orders: status mix and missing timestamps by status
SELECT
    order_status,
    COUNT(*)                                                            AS orders,
    COUNT_IF(order_approved_at IS NULL)                                 AS no_approved_at,
    COUNT_IF(order_delivered_carrier_date IS NULL)                      AS no_carrier_date,
    COUNT_IF(order_delivered_customer_date IS NULL)                     AS no_delivered_date
FROM ORDERS
GROUP BY order_status
ORDER BY orders DESC;

-- "delivered" orders with no delivery date (cannot compute late flag)
SELECT COUNT(*) AS delivered_without_date
FROM ORDERS
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

-- Timestamps in impossible order
SELECT
    COUNT_IF(TRY_TO_TIMESTAMP(order_delivered_customer_date) < TRY_TO_TIMESTAMP(order_purchase_timestamp)) AS delivered_before_purchase,
    COUNT_IF(TRY_TO_TIMESTAMP(order_approved_at)             < TRY_TO_TIMESTAMP(order_purchase_timestamp)) AS approved_before_purchase,
    COUNT_IF(TRY_TO_TIMESTAMP(order_delivered_carrier_date)  < TRY_TO_TIMESTAMP(order_purchase_timestamp)) AS shipped_before_purchase
FROM ORDERS;

-- Date range of the data (dim_date needs this)
SELECT
    MIN(TRY_TO_TIMESTAMP(order_purchase_timestamp)) AS first_order,
    MAX(TRY_TO_TIMESTAMP(order_purchase_timestamp)) AS last_order
FROM ORDERS;


-- 6. Orphans: orders with no items, no payment, no review
SELECT
    COUNT_IF(i.order_id IS NULL) AS orders_without_items,
    COUNT_IF(p.order_id IS NULL) AS orders_without_payment,
    COUNT_IF(r.order_id IS NULL) AS orders_without_review
FROM ORDERS o
LEFT JOIN (SELECT DISTINCT order_id FROM ORDER_ITEMS)    i ON o.order_id = i.order_id
LEFT JOIN (SELECT DISTINCT order_id FROM ORDER_PAYMENTS) p ON o.order_id = p.order_id
LEFT JOIN (SELECT DISTINCT order_id FROM ORDER_REVIEWS)  r ON o.order_id = r.order_id;

-- Which statuses do item-less orders have?
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM ORDERS o
LEFT JOIN (SELECT DISTINCT order_id FROM ORDER_ITEMS) i ON o.order_id = i.order_id
WHERE i.order_id IS NULL
GROUP BY 1
ORDER BY 2 DESC;


-- 7. Products: missing category and categories with no English translation
SELECT
    COUNT_IF(product_category_name IS NULL) AS products_without_category,
    COUNT_IF(product_category_name IS NOT NULL AND t.product_category_name_english IS NULL)
                                            AS products_with_untranslated_category
FROM PRODUCTS p
LEFT JOIN PRODUCT_CATEGORY_NAME_TRANSLATION t USING (product_category_name);

SELECT DISTINCT p.product_category_name AS untranslated_category
FROM PRODUCTS p
LEFT JOIN PRODUCT_CATEGORY_NAME_TRANSLATION t USING (product_category_name)
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name_english IS NULL;


-- 8. Payments: types, zero values, and whether payments match items + freight
SELECT payment_type, COUNT(*) AS payments, SUM(TRY_TO_NUMBER(payment_value, 12, 2)) AS total_value
FROM ORDER_PAYMENTS
GROUP BY 1
ORDER BY 2 DESC;

SELECT COUNT(*) AS zero_value_payments
FROM ORDER_PAYMENTS
WHERE TRY_TO_NUMBER(payment_value, 12, 2) = 0;

-- Payment total vs item price + freight, per order (the custom test in Week 3)
WITH items AS (
    SELECT order_id,
           SUM(TRY_TO_NUMBER(price, 12, 2) + TRY_TO_NUMBER(freight_value, 12, 2)) AS items_total
    FROM ORDER_ITEMS GROUP BY 1
), pays AS (
    SELECT order_id, SUM(TRY_TO_NUMBER(payment_value, 12, 2)) AS payment_total
    FROM ORDER_PAYMENTS GROUP BY 1
)
SELECT
    COUNT(*)                                                                   AS orders_compared,
    COUNT_IF(ABS(p.payment_total - i.items_total) > 0.01 * i.items_total)      AS mismatch_over_1pct
FROM items i
JOIN pays p USING (order_id);


-- 9. Values that will not cast cleanly (TRY_ returns NULL where the raw value is not)
SELECT
    COUNT_IF(price         IS NOT NULL AND TRY_TO_NUMBER(price, 12, 2)         IS NULL) AS bad_price,
    COUNT_IF(freight_value IS NOT NULL AND TRY_TO_NUMBER(freight_value, 12, 2) IS NULL) AS bad_freight,
    COUNT_IF(shipping_limit_date IS NOT NULL AND TRY_TO_TIMESTAMP(shipping_limit_date) IS NULL) AS bad_shipping_date
FROM ORDER_ITEMS;

SELECT review_score, COUNT(*) AS reviews
FROM ORDER_REVIEWS
GROUP BY 1
ORDER BY 1;


-- 10. Zip prefixes: leading zeros must survive (they do, because RAW is VARCHAR)
SELECT
    COUNT_IF(LENGTH(customer_zip_code_prefix) < 5) AS customer_zips_short,
    MIN(customer_zip_code_prefix)                  AS smallest_zip
FROM CUSTOMERS;

-- Customer zips with no match in geolocation
SELECT COUNT(DISTINCT c.customer_zip_code_prefix) AS customer_zips_without_geo
FROM CUSTOMERS c
LEFT JOIN (SELECT DISTINCT geolocation_zip_code_prefix FROM GEOLOCATION) g
       ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
WHERE g.geolocation_zip_code_prefix IS NULL;
