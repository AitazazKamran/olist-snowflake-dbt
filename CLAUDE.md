# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Olist Brazilian e-commerce data (9 Kaggle CSVs, ~100K orders) → Snowflake RAW → dbt (staging → intermediate → marts star schema) → Power BI. Airflow orchestration and GitHub Actions CI are planned (Week 3). The build is staged by week; `README.md` marks unfinished sections _(coming)_, and empty dirs hold `.gitkeep` placeholders (`intermediate/`, `marts/`, `snapshots/`, `tests/`, `airflow/dags/`, `.github/workflows/`).

## Commands

Setup (Python 3.10–3.12): `pip install -r requirements.txt`, then copy `.env.example` to `.env`.

```bash
python ingestion/load_raw.py                  # PUT CSVs from ./data + run snowflake/01_load_raw.sql; idempotent
python ingestion/load_raw.py --data-dir D:/olist

# dbt — always run from dbt/ with --profiles-dir . (profiles.yml lives in the repo)
cd dbt
dbt deps
dbt debug --profiles-dir .
dbt build --select staging --profiles-dir .          # build + test a layer
dbt build --select stg_orders --profiles-dir .       # single model + its tests
dbt test  --select stg_reviews --profiles-dir .      # tests for one model
dbt source freshness --profiles-dir .
dbt build --target prod --profiles-dir .             # or set DBT_TARGET

sqlfluff lint dbt/models                             # sqlfluff is installed; no repo config yet
```

dbt reads `.env` values only via environment variables — `profiles.yml` uses `env_var()` and does not load `.env` itself, so export them in the shell first (`load_raw.py` does call `load_dotenv`).

`snowflake/00_setup.sql` (roles, warehouse, schemas, service user, resource monitor) and `snowflake/02_profile_raw.sql` are run manually in Snowsight, not by any script.

## Architecture

- **RAW** (`snowflake/01_load_raw.sql`): every column is `VARCHAR`, plus `_source_file` and `_loaded_at`. All type casting happens in staging. `load_raw.py` executes this file statement-by-statement and parses the `COPY INTO` and final `SELECT` (actual vs expected row counts) results — keep that output shape if editing the SQL.
- **Staging** (`dbt/models/staging/`, views): one `stg_` model per source table. Pattern is `source` CTE → `renamed` CTE (cast with `try_to_*`, `lower(trim())`, `nullif(trim(x), '')`) → optional `deduplicated` CTE using `qualify row_number()`. Models without a natural key get a `dbt_utils.generate_surrogate_key` `*_key` column, which carries the `unique` test.
- **Intermediate** (views) and **marts** (tables: `fct_orders`, `fct_order_items`, 5 dims) plus `snap_products` SCD2 snapshot are Week 2 work.
- Sources are declared in `_sources.yml` (dbt 1.10+ syntax: `freshness`/`loaded_at_field` under `config:`; tests use `data_tests:`). Model tests/docs are in `_stg_models.yml`. `persist_docs` is on, so descriptions are pushed to Snowflake.
- Packages: `dbt_utils` and `metaplane/dbt_expectations` (not the unmaintained calogica fork).

### Schema naming (`macros/generate_schema_name.sql`)

- `prod` target → exact names `STAGING`, `INTERMEDIATE`, `MARTS`, `SNAPSHOTS` (Power BI and REPORTER grants depend on these).
- `dev` → `DBT_DEV_<LAYER>`; `ci` → `<DBT_CI_SCHEMA>_<LAYER>` (e.g. `CI_PR_12_MARTS`).

### Access

`TRANSFORMER` loads RAW and runs dbt; `REPORTER` reads MARTS only. dbt/Airflow/CI connect as service user `DBT_SVC` with key-pair auth (private key kept outside the repo; `*.p8`, `*.pub`, `rsa_key*`, `.env`, and `data/*` are git-ignored).

## Data quirks to respect

Documented in `docs/data_profile.md`; key ones that drive model grain:
- `review_id` is not unique — `stg_reviews` grain is (review_id, order_id), keeping the latest answered copy.
- `customer_id` is per order; use `customer_unique_id` for the person (repeat-customer analysis).
- Geolocation has many rows per zip prefix and points outside Brazil — `stg_geolocation` collapses to one row per prefix and filters by bounding box.
- Source columns misspell `lenght`; `stg_products` renames them.
- Source freshness will warn after 7 days — expected, the dataset is a one-time export.

## Workflow conventions (from AI_LOG.md)

- AI-generated SQL is not committed until `dbt build` passes and row counts match RAW.
- Metric definitions, grants, roles and security settings require explicit user review — don't change them unprompted.
- Notable AI successes/mistakes get logged as rows in `AI_LOG.md`.
