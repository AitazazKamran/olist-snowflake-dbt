# Airflow image + an isolated virtualenv for dbt and the Snowflake loader.
# dbt lives in its own venv so its dependencies never clash with Airflow's.
FROM apache/airflow:3.3.2-python3.12

RUN python -m venv /home/airflow/dbt_venv \
 && /home/airflow/dbt_venv/bin/pip install --no-cache-dir \
      "dbt-core>=1.10,<2.0" \
      "dbt-snowflake>=1.10.6,<2.0" \
      "snowflake-connector-python>=3.12" \
      "python-dotenv>=1.0"
