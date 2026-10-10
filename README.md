# Olist E-Commerce Analytics Platform

**Snowflake · dbt · Airflow · GitHub Actions · Power BI**

Raw Brazilian e-commerce data (about 100K orders, 9 tables) loaded into Snowflake,
modelled with dbt into a tested and documented star schema, orchestrated by Airflow,
checked by CI on every pull request, and reported in Power BI.

> Status: **Week 1 — setup and raw data.** Sections marked _(coming)_ are filled in as the build progresses.

## Business questions

1. What are monthly revenue, orders and average order value, by product category and state?
2. How many orders arrive late, and how much does a late delivery lower the review score?
3. Which sellers have the best and worst on-time rate and review score?
4. What share of customers buy again, and how does that change by first-purchase month?
5. How does payment type relate to order value and cancellations?

## Architecture

```
Kaggle CSVs ──PUT──▶ Snowflake stage ──COPY INTO──▶ RAW
                                                     │  dbt
                                                     ▼
                           STAGING ──▶ INTERMEDIATE ──▶ MARTS ──▶ Power BI (REPORTER role)
                                                     ▲
                       Airflow (daily) · GitHub Actions (every PR) · SNAPSHOTS (SCD2)
```

_(architecture.png and lineage.png coming in Week 3)_

| Snowflake schema | Built by | Contents |
|---|---|---|
| RAW | `snowflake/01_load_raw.sql` | 9 tables, all VARCHAR, plus `_source_file` and `_loaded_at` |
| STAGING | dbt (views) | 9 `stg_` models: rename, cast, deduplicate |
| INTERMEDIATE | dbt (views) | business logic _(Week 2)_ |
| MARTS | dbt (tables) | `fct_orders`, `fct_order_items`, 5 dimensions _(Week 2)_ |
| SNAPSHOTS | dbt | `snap_products` SCD Type 2 _(Week 2)_ |

**Access control:** `TRANSFORMER` loads and transforms; `REPORTER` can only read MARTS.
dbt, Airflow and CI connect as a `TYPE = SERVICE` user with key-pair authentication.

## Repo layout

```
snowflake/       00_setup.sql, 01_load_raw.sql, 02_profile_raw.sql
ingestion/       load_raw.py  (PUT + COPY INTO in one command)
dbt/             dbt project (profiles.yml reads secrets from env vars)
airflow/dags/    daily pipeline (Week 3)
.github/         CI (Week 3)
dashboard/       Power BI file and screenshots (Week 4)
docs/            data_profile.md, diagrams
AI_LOG.md        how AI was used and checked
```

## How to run

### 1. Prerequisites

- Python 3.10 – 3.12, Git, and OpenSSL (Git Bash includes it on Windows)
- A Snowflake trial account (30 days)
- The Olist CSVs in `data/` (see `data/README.md`)

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env               # then fill it in
```

### 2. Create the service user key

Keep the key files **outside** the repo.

```bash
mkdir -p ~/.snowflake && cd ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```

Copy the contents of `rsa_key.pub` (without the BEGIN/END lines, as one line) into the
commented `ALTER USER DBT_SVC SET RSA_PUBLIC_KEY = ...` line in `snowflake/00_setup.sql`.
Put the full path of `rsa_key.p8` in `.env` as `SNOWFLAKE_PRIVATE_KEY_PATH`.

### 3. Set up Snowflake

Open a Snowsight worksheet as your admin user and run `snowflake/00_setup.sql` top to bottom
(uncomment the `ALTER USER` line first).

### 4. Load RAW

```bash
python ingestion/load_raw.py
```

This uploads the 9 CSVs to the stage, runs `snowflake/01_load_raw.sql`, and prints
actual vs expected row counts. Running it again is safe: already-loaded files are skipped.

### 5. Profile the data

Run `snowflake/02_profile_raw.sql` in Snowsight and record findings in `docs/data_profile.md`.

### 6. Build staging with dbt

```bash
cd dbt
dbt deps
dbt debug  --profiles-dir .
dbt source freshness --profiles-dir .
dbt build  --select staging --profiles-dir .
```

Dev models land in `DBT_DEV_STAGING`. Use `--target prod` to build the real `STAGING` schema.

## Key findings

_(coming in Week 4, with numbers)_

## Built AI-first

Built with Claude Code and Cursor. Every AI-generated model was validated with dbt tests
and row-count checks before commit. See [AI_LOG.md](AI_LOG.md).
