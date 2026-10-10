-- =============================================================================
-- 01_load_raw.sql  |  Load the 9 Olist CSVs into OLIST.RAW
-- -----------------------------------------------------------------------------
-- Pattern: internal stage + named FILE FORMAT + COPY INTO with load metadata.
--
-- Design choices (good to explain in interviews):
--   * Every source column is VARCHAR. RAW is an untouched copy, so a bad value
--     never makes the load fail; dbt staging does the casting with TRY_ functions.
--   * Column names stay exactly as in the CSVs, typos included
--     (product_name_lenght). Renaming is staging's job.
--   * Two metadata columns on every table:
--       _source_file  which staged file the row came from (METADATA$FILENAME)
--       _loaded_at    when it was loaded; dbt source freshness reads this
--   * CREATE TABLE IF NOT EXISTS + COPY INTO is idempotent: Snowflake keeps
--     64 days of load history per table and skips files it already loaded,
--     so Airflow can run this script every day safely.
--
-- How to run
--   Step A  upload the CSVs to the stage (PUT section below, or Snowsight UI,
--           or ingestion/load_raw.py, which does both steps for you)
--   Step B  run the rest of this file as TRANSFORMER
-- =============================================================================

USE ROLE TRANSFORMER;
USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA RAW;


-- -----------------------------------------------------------------------------
-- 1. File format and stage
-- -----------------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS OLIST.RAW.CSV_OLIST
    TYPE                         = CSV
    FIELD_DELIMITER              = ','
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'    -- review comments contain commas and line breaks
    EMPTY_FIELD_AS_NULL          = TRUE
    NULL_IF                      = ('', 'NULL')
    ENCODING                     = 'UTF8'
    COMMENT = 'Olist Kaggle CSVs';

CREATE STAGE IF NOT EXISTS OLIST.RAW.OLIST_STAGE
    FILE_FORMAT = OLIST.RAW.CSV_OLIST
    COMMENT = 'Internal stage for the Olist CSVs';


-- -----------------------------------------------------------------------------
-- 2. Upload the files (Step A)
-- -----------------------------------------------------------------------------
-- PUT does not run in a Snowsight worksheet. Use ONE of these:
--   a) Snowflake CLI:  snow sql -q "PUT 'file:///path/to/data/*.csv' @OLIST.RAW.OLIST_STAGE AUTO_COMPRESS=TRUE"
--      Windows path example: 'file://C:/Users/you/olist-snowflake-dbt/data/*.csv'
--   b) Snowsight: Data > Databases > OLIST > RAW > Stages > OLIST_STAGE > + Files
--   c) python ingestion/load_raw.py   (uploads and then runs this whole file)
--
-- PUT 'file:///path/to/olist-snowflake-dbt/data/*.csv' @OLIST.RAW.OLIST_STAGE AUTO_COMPRESS = TRUE;

LIST @OLIST.RAW.OLIST_STAGE;


-- -----------------------------------------------------------------------------
-- 3. RAW tables
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS OLIST.RAW.ORDERS (
    order_id                       VARCHAR,
    customer_id                    VARCHAR,
    order_status                   VARCHAR,
    order_purchase_timestamp       VARCHAR,
    order_approved_at              VARCHAR,
    order_delivered_carrier_date   VARCHAR,
    order_delivered_customer_date  VARCHAR,
    order_estimated_delivery_date  VARCHAR,
    _source_file                   VARCHAR,
    _loaded_at                     TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS OLIST.RAW.ORDER_ITEMS (
    order_id             VARCHAR,
    order_item_id        VARCHAR,
    product_id           VARCHAR,
    seller_id            VARCHAR,
    shipping_limit_date  VARCHAR,
    price                VARCHAR,
    freight_value        VARCHAR,
    _source_file         VARCHAR,
    _loaded_at           TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS OLIST.RAW.ORDER_PAYMENTS (
    order_id              VARCHAR,
    payment_sequential    VARCHAR,
    payment_type          VARCHAR,
    payment_installments  VARCHAR,
    payment_value         VARCHAR,
    _source_file          VARCHAR,
    _loaded_at            TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS OLIST.RAW.ORDER_REVIEWS (
    review_id                VARCHAR,
    order_id                 VARCHAR,
    review_score             VARCHAR,
    review_comment_title     VARCHAR,
    review_comment_message   VARCHAR,
    review_creation_date     VARCHAR,
    review_answer_timestamp  VARCHAR,
    _source_file             VARCHAR,
    _loaded_at               TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS OLIST.RAW.CUSTOMERS (
    customer_id               VARCHAR,
    customer_unique_id        VARCHAR,
    customer_zip_code_prefix  VARCHAR,
    customer_city             VARCHAR,
    customer_state            VARCHAR,
    _source_file              VARCHAR,
    _loaded_at                TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS OLIST.RAW.SELLERS (
    seller_id               VARCHAR,
    seller_zip_code_prefix  VARCHAR,
    seller_city             VARCHAR,
    seller_state            VARCHAR,
    _source_file            VARCHAR,
    _loaded_at              TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS OLIST.RAW.PRODUCTS (
    product_id                  VARCHAR,
    product_category_name       VARCHAR,
    product_name_lenght         VARCHAR,   -- typo is in the source file; fixed in staging
    product_description_lenght  VARCHAR,   -- typo is in the source file; fixed in staging
    product_photos_qty          VARCHAR,
    product_weight_g            VARCHAR,
    product_length_cm           VARCHAR,
    product_height_cm           VARCHAR,
    product_width_cm            VARCHAR,
    _source_file                VARCHAR,
    _loaded_at                  TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION (
    product_category_name          VARCHAR,
    product_category_name_english  VARCHAR,
    _source_file                   VARCHAR,
    _loaded_at                     TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS OLIST.RAW.GEOLOCATION (
    geolocation_zip_code_prefix  VARCHAR,
    geolocation_lat              VARCHAR,
    geolocation_lng              VARCHAR,
    geolocation_city             VARCHAR,
    geolocation_state            VARCHAR,
    _source_file                 VARCHAR,
    _loaded_at                   TIMESTAMP_LTZ
);


-- -----------------------------------------------------------------------------
-- 4. COPY INTO (Step B)
-- -----------------------------------------------------------------------------
-- PATTERN matches the file whether or not PUT compressed it to .csv.gz.
-- [.] means a literal dot. ON_ERROR = ABORT_STATEMENT: fail loudly, never load
-- half a file. If a load fails, rerun that COPY with VALIDATION_MODE = RETURN_ERRORS
-- to see the bad rows.

COPY INTO OLIST.RAW.ORDERS
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, $8, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*olist_orders_dataset[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;

COPY INTO OLIST.RAW.ORDER_ITEMS
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*olist_order_items_dataset[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;

COPY INTO OLIST.RAW.ORDER_PAYMENTS
FROM (
    SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*olist_order_payments_dataset[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;

COPY INTO OLIST.RAW.ORDER_REVIEWS
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*olist_order_reviews_dataset[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;

COPY INTO OLIST.RAW.CUSTOMERS
FROM (
    SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*olist_customers_dataset[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;

COPY INTO OLIST.RAW.SELLERS
FROM (
    SELECT $1, $2, $3, $4, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*olist_sellers_dataset[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;

COPY INTO OLIST.RAW.PRODUCTS
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*olist_products_dataset[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;

COPY INTO OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION
FROM (
    SELECT $1, $2, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*product_category_name_translation[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;

COPY INTO OLIST.RAW.GEOLOCATION
FROM (
    SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @OLIST.RAW.OLIST_STAGE
)
PATTERN = '.*olist_geolocation_dataset[.]csv.*'
FILE_FORMAT = (FORMAT_NAME = 'OLIST.RAW.CSV_OLIST')
ON_ERROR = ABORT_STATEMENT;


-- -----------------------------------------------------------------------------
-- 5. Check row counts
-- -----------------------------------------------------------------------------
-- Expected counts are for the current Kaggle version of the dataset. If yours
-- differ, check which file version you downloaded before assuming a load bug.
SELECT 'orders'                            AS table_name, COUNT(*) AS row_count,  99441 AS expected FROM OLIST.RAW.ORDERS
UNION ALL SELECT 'order_items',                       COUNT(*), 112650  FROM OLIST.RAW.ORDER_ITEMS
UNION ALL SELECT 'order_payments',                    COUNT(*), 103886  FROM OLIST.RAW.ORDER_PAYMENTS
UNION ALL SELECT 'order_reviews',                     COUNT(*),  99224  FROM OLIST.RAW.ORDER_REVIEWS
UNION ALL SELECT 'customers',                         COUNT(*),  99441  FROM OLIST.RAW.CUSTOMERS
UNION ALL SELECT 'sellers',                           COUNT(*),   3095  FROM OLIST.RAW.SELLERS
UNION ALL SELECT 'products',                          COUNT(*),  32951  FROM OLIST.RAW.PRODUCTS
UNION ALL SELECT 'product_category_name_translation', COUNT(*),     71  FROM OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION
UNION ALL SELECT 'geolocation',                       COUNT(*), 1000163 FROM OLIST.RAW.GEOLOCATION
ORDER BY table_name;
