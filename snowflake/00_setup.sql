-- =============================================================================
-- 00_setup.sql  |  One-time Snowflake setup for the Olist analytics project
-- -----------------------------------------------------------------------------
-- Run top to bottom in a Snowsight worksheet, logged in as your trial admin user.
-- Creates: warehouse, database, 5 schemas, 2 roles, grants, a service user for
-- dbt / Airflow / CI, and a resource monitor that protects your trial credits.
--
-- Role design (follows Snowflake best practice: each system role does one job)
--   USERADMIN     creates roles and users
--   SYSADMIN      creates the warehouse, database and schemas
--   SECURITYADMIN hands out privileges
--   ACCOUNTADMIN  only for the resource monitor (it is the only role allowed to)
--
-- Project roles
--   TRANSFORMER  engineering role: loads RAW and builds every dbt layer
--   REPORTER     Power BI role: read-only on MARTS, nothing else
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Warehouse, database, schemas
-- -----------------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS OLIST_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60        -- suspend after 60 seconds idle
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Olist project: dbt, Airflow, CI and Power BI';

CREATE DATABASE IF NOT EXISTS OLIST
    COMMENT = 'Olist e-commerce analytics engineering project';

CREATE SCHEMA IF NOT EXISTS OLIST.RAW          COMMENT = 'Untouched copies of the source CSVs';
CREATE SCHEMA IF NOT EXISTS OLIST.STAGING      COMMENT = 'dbt staging views: rename, cast, clean';
CREATE SCHEMA IF NOT EXISTS OLIST.INTERMEDIATE COMMENT = 'dbt intermediate models: business logic';
CREATE SCHEMA IF NOT EXISTS OLIST.MARTS        COMMENT = 'dbt star schema exposed to Power BI';
CREATE SCHEMA IF NOT EXISTS OLIST.SNAPSHOTS    COMMENT = 'dbt snapshots (SCD Type 2)';


-- -----------------------------------------------------------------------------
-- 2. Roles
-- -----------------------------------------------------------------------------
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS TRANSFORMER COMMENT = 'Loads RAW and runs dbt (write)';
CREATE ROLE IF NOT EXISTS REPORTER    COMMENT = 'Power BI (read MARTS only)';


-- -----------------------------------------------------------------------------
-- 3. Grants
-- -----------------------------------------------------------------------------
USE ROLE SECURITYADMIN;

-- Role hierarchy: SYSADMIN inherits both, so admins can always see everything.
GRANT ROLE TRANSFORMER TO ROLE SYSADMIN;
GRANT ROLE REPORTER    TO ROLE SYSADMIN;

-- Give yourself both roles so you can test them in Snowsight.
SET my_user = CURRENT_USER();
GRANT ROLE TRANSFORMER TO USER IDENTIFIER($my_user);
GRANT ROLE REPORTER    TO USER IDENTIFIER($my_user);

-- Warehouse
GRANT USAGE, OPERATE ON WAREHOUSE OLIST_WH TO ROLE TRANSFORMER;
GRANT USAGE          ON WAREHOUSE OLIST_WH TO ROLE REPORTER;

-- Database. CREATE SCHEMA lets dbt make personal dev schemas and temporary CI schemas.
GRANT USAGE, CREATE SCHEMA ON DATABASE OLIST TO ROLE TRANSFORMER;
GRANT USAGE                ON DATABASE OLIST TO ROLE REPORTER;

-- TRANSFORMER owns every project schema, so it can create, replace and drop
-- tables, views, stages and file formats inside them.
GRANT OWNERSHIP ON SCHEMA OLIST.RAW          TO ROLE TRANSFORMER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA OLIST.STAGING      TO ROLE TRANSFORMER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA OLIST.INTERMEDIATE TO ROLE TRANSFORMER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA OLIST.MARTS        TO ROLE TRANSFORMER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA OLIST.SNAPSHOTS    TO ROLE TRANSFORMER COPY CURRENT GRANTS;

-- REPORTER sees MARTS only: current and future tables and views.
GRANT USAGE  ON SCHEMA OLIST.MARTS                 TO ROLE REPORTER;
GRANT SELECT ON ALL TABLES    IN SCHEMA OLIST.MARTS TO ROLE REPORTER;
GRANT SELECT ON ALL VIEWS     IN SCHEMA OLIST.MARTS TO ROLE REPORTER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA OLIST.MARTS TO ROLE REPORTER;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA OLIST.MARTS TO ROLE REPORTER;


-- -----------------------------------------------------------------------------
-- 4. Service user for dbt, Airflow and GitHub Actions (key-pair auth, no password)
-- -----------------------------------------------------------------------------
-- Snowflake is phasing out password-only sign-in, so machines should use a
-- TYPE = SERVICE user with an RSA key pair. Generate the key on your laptop
-- first (see README > "Create the service user key"), then paste the PUBLIC key
-- below, without the BEGIN/END lines and without line breaks.
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS DBT_SVC
    TYPE              = SERVICE
    DEFAULT_ROLE      = TRANSFORMER
    DEFAULT_WAREHOUSE = OLIST_WH
    DEFAULT_NAMESPACE = OLIST.RAW
    COMMENT = 'Service user for dbt, Airflow and CI';

-- ALTER USER DBT_SVC SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqh...paste your public key here...';

USE ROLE SECURITYADMIN;
GRANT ROLE TRANSFORMER TO USER DBT_SVC;


-- -----------------------------------------------------------------------------
-- 5. Resource monitor: stop the warehouse before the trial credits run out
-- -----------------------------------------------------------------------------
-- An XS warehouse uses 1 credit per running hour. 25 credits is far more than
-- this project needs; adjust if you like.
USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS OLIST_MONITOR
    WITH CREDIT_QUOTA = 25
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75  PERCENT DO NOTIFY
        ON 90  PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE OLIST_WH SET RESOURCE_MONITOR = OLIST_MONITOR;


-- -----------------------------------------------------------------------------
-- 6. Check
-- -----------------------------------------------------------------------------
USE ROLE SYSADMIN;
SHOW SCHEMAS IN DATABASE OLIST;
SHOW GRANTS TO ROLE TRANSFORMER;
SHOW GRANTS TO ROLE REPORTER;
SHOW WAREHOUSES LIKE 'OLIST_WH';
