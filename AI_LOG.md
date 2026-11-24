# AI-first workflow log

This project was built with Claude as a pair programmer. Claude drafted SQL,
dbt models, tests, the Airflow DAG and the CI workflow; I ran everything,
checked the results against the source data, and fixed or questioned what
was wrong. This log records what the AI did well, what it got wrong, and how
I caught it.

## Rules I followed

1. No AI-generated SQL is committed until `dbt build` passes and row counts match RAW.
2. The AI writes tests for its own models; I read every test myself.
3. The AI drafts YAML docs; I check every metric definition against the business rules.
4. Grants, roles and security settings are tested, never assumed.

## Log

| Date | Task | Tool | What AI did well | What it got wrong | How I caught it |
|---|---|---|---|---|---|
| 2026-10-10 | Week 1 scaffold: Snowflake setup, `COPY INTO`, staging models | Claude | Full setup script with separate roles, key-pair service user and a resource monitor | Granted roles to my own login as `SECURITYADMIN`, which failed on a trial account ("does not exist or not authorized") | Snowsight error on Run All. The grant was unnecessary: my login already inherits both roles through `ACCOUNTADMIN → SYSADMIN` |
| 2026-10-28 | Create the `DBT_SVC` service user | Claude | Explained that Snowflake gives one message for "missing" and "not allowed" on purpose | `ALTER USER` failed because the statements had run partly out of order and the role in use could not change the user | Error on `ALTER USER`; recreated and altered the user as `ACCOUNTADMIN`, then confirmed `RSA_PUBLIC_KEY_FP` with `DESC USER` |
| 2026-11-06 | Load RAW with `ingestion/load_raw.py` | Claude | Idempotent loader: `PUT` skips staged files, `COPY INTO` skips loaded files | Nothing wrong; the connector's logging was very noisy | Reran the loader: every file `SKIPPED` / `0 files processed`, all 9 row counts unchanged |
| 2026-11-06 | Profile RAW (20 issues) | Claude | Wrote ~20 profiling queries that found the non-unique `review_id`, duplicate geolocation rows and item-less orders | — | Ran every query myself and recorded the real counts in `docs/data_profile.md` |
| 2026-11-16 | Week 2: 5 intermediate models, 7 marts, seed, snapshot, custom tests | Claude | Built "aggregate before join" models so `fct_orders` cannot fan out; added a revenue reconciliation test | — | `dbt build`: everything passed except the expected warning (254 payment mismatches). Mart row counts matched staging exactly |
| 2026-11-16 | CI and SQLFluff | Claude | Auto-formatted all 21 models to pass SQLFluff, without changing logic | — | CI green on the pull request: lint, then `dbt build` in a throwaway schema |
| 2026-11-23 | Power BI model | Claude | DAX measures that count each order once on item-level data | Did not warn that `DIM_DATE[YEAR]` could load as a date type, or that a measure named `Revenue` clashes with the `REVENUE` column | The year slicer showed dates in 1905; Power BI refused the measure name |
| 2026-11-23 | Power BI: late rate by category | Claude | Explained filter direction once the bug appeared | A copied chart used product category with an order-level measure, so every bar showed the same value | Identical bars. Products relate only to `FCT_ORDER_ITEMS`; switched the axis to customer state |
| 2026-11-24 | Data quality page | Claude | Traced the difference down to a single zip code | Predicted 158 zips without coordinates; the dashboard showed 163 | Reconciled with SQL: 162 zips absent from the geolocation file + 1 zip whose only coordinates were outside Brazil |
| 2026-11-24 | Access control test | Claude | Identified Snowflake's default secondary roles as the cause | The setup assumed `REPORTER` was restricted, but in my session it could still read `RAW` | Ran a `RAW` query as `REPORTER` and it succeeded. Set `DEFAULT_SECONDARY_ROLES = ()` and re-tested: `RAW` fails, `MARTS` works |

## Interview stories (STAR)

1. **Speed.** AI drafted about 20 profiling queries, 21 dbt models, 87 tests, the Airflow DAG and the CI workflow. My time went into running them, checking results against the source data, and deciding the business rules (revenue, late delivery, repeat customer).
2. **AI was wrong, and checks caught it.** The dashboard showed 163 zips without coordinates where the AI had predicted 158. I reconciled the difference in SQL to a single zip whose only coordinates were outside Brazil. The model had handled it correctly; the prediction was wrong.
3. **Where I don't trust AI.** Security and metric definitions. My read-only reporting role looked correct in the setup script, but a test showed it could still read raw data because of Snowflake's default secondary roles. I fixed the user setting and re-tested before trusting it.
4. **Teaching it.** Profile before modelling, aggregate before joining, write a reconciliation test for every headline number, and test permissions by trying to break them.
