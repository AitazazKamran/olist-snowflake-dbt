"""Daily Olist pipeline: load RAW -> check freshness -> dbt build -> dbt docs.

Each step is a BashOperator calling the same commands you run by hand, so the
DAG is easy to read and debug. dbt runs from its own virtualenv in the image.

Failure handling: each task retries twice, 5 minutes apart. If a task still
fails, downstream tasks are skipped and the failure shows in the Airflow UI
and task logs (on_failure_callback is where a Slack/email alert would go).
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

PROJECT = os.environ.get("PROJECT_DIR", "/opt/project")
VENV = os.environ.get("DBT_VENV", "/home/airflow/dbt_venv")
DBT = f"cd {PROJECT}/dbt && {VENV}/bin/dbt"

log = logging.getLogger(__name__)


def alert_on_failure(context) -> None:
    """Placeholder alert: log loudly. Swap for a Slack or email notifier."""
    ti = context["task_instance"]
    log.error("PIPELINE FAILURE: dag=%s task=%s run=%s", ti.dag_id, ti.task_id, context["run_id"])


default_args = {
    "owner": "aitazaz",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "on_failure_callback": alert_on_failure,
}

with DAG(
    dag_id="olist_pipeline",
    description="Load Olist CSVs into Snowflake RAW, then build and test the dbt project",
    schedule="0 6 * * *",          # every day at 06:00 UTC
    start_date=datetime(2026, 11, 1),
    catchup=False,                 # do not backfill missed days
    max_active_runs=1,             # never run two pipelines at once
    default_args=default_args,
    tags=["olist", "dbt", "snowflake"],
) as dag:

    load_raw = BashOperator(
        task_id="load_raw",
        bash_command=f"cd {PROJECT} && {VENV}/bin/python ingestion/load_raw.py",
    )

    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=f"{DBT} deps",
    )

    # Warns (exit 0) after 7 days, errors (exit 1) after 30: see _sources.yml.
    source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=f"{DBT} source freshness --target prod",
    )

    # Seeds, models, snapshot and every test, in dependency order.
    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=f"{DBT} build --target prod",
    )

    docs_generate = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=f"{DBT} docs generate --target prod",
    )

    load_raw >> dbt_deps >> source_freshness >> dbt_build >> docs_generate
