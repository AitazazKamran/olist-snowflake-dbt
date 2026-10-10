"""Load the Olist CSVs into Snowflake RAW.

Uploads every CSV in ./data to the internal stage with PUT, then runs
snowflake/01_load_raw.sql (file format, stage, tables, COPY INTO, row counts).

Safe to run again: PUT skips files already on the stage and COPY INTO skips
files already loaded, so Airflow can call this every day.

Usage:
    python ingestion/load_raw.py                 # uses ./data
    python ingestion/load_raw.py --data-dir D:/olist

Connection settings come from environment variables (see .env.example).
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[1]
LOAD_SQL = REPO_ROOT / "snowflake" / "01_load_raw.sql"
STAGE = "@OLIST.RAW.OLIST_STAGE"

EXPECTED_FILES = [
    "olist_orders_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_customers_dataset.csv",
    "olist_sellers_dataset.csv",
    "olist_products_dataset.csv",
    "product_category_name_translation.csv",
    "olist_geolocation_dataset.csv",
]

log = logging.getLogger("load_raw")


def connect() -> snowflake.connector.SnowflakeConnection:
    """Open a connection using key-pair auth if a key file is set, else password."""
    params = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "role": os.getenv("SNOWFLAKE_ROLE", "TRANSFORMER"),
        "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE", "OLIST_WH"),
        "database": os.getenv("SNOWFLAKE_DATABASE", "OLIST"),
        "schema": "RAW",
    }
    key_file = os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH")
    if key_file:
        params["private_key_file"] = key_file
        passphrase = os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
        if passphrase:
            params["private_key_file_pwd"] = passphrase
    else:
        params["password"] = os.environ["SNOWFLAKE_PASSWORD"]
    return snowflake.connector.connect(**params)


def put_files(conn, data_dir: Path) -> None:
    missing = [f for f in EXPECTED_FILES if not (data_dir / f).exists()]
    if missing:
        raise FileNotFoundError(
            f"Missing in {data_dir}: {', '.join(missing)}. "
            "Download the Olist dataset from Kaggle and unzip it there."
        )
    cur = conn.cursor()
    # The stage is created by 01_load_raw.sql; make sure it exists before PUT.
    cur.execute(
        "CREATE FILE FORMAT IF NOT EXISTS OLIST.RAW.CSV_OLIST TYPE = CSV SKIP_HEADER = 1 "
        "FIELD_OPTIONALLY_ENCLOSED_BY = '\"' EMPTY_FIELD_AS_NULL = TRUE NULL_IF = ('', 'NULL')"
    )
    cur.execute(f"CREATE STAGE IF NOT EXISTS {STAGE[1:]} FILE_FORMAT = OLIST.RAW.CSV_OLIST")
    for name in EXPECTED_FILES:
        path = (data_dir / name).resolve().as_posix()
        cur.execute(f"PUT 'file://{path}' {STAGE} AUTO_COMPRESS = TRUE OVERWRITE = FALSE")
        for row in cur.fetchall():
            # row: source, target, source_size, target_size, source_compression,
            #      target_compression, status, message
            log.info("PUT %-45s %s", row[0], row[6])


def run_load_sql(conn) -> None:
    sql_text = LOAD_SQL.read_text(encoding="utf-8")
    for cur in conn.execute_string(sql_text, remove_comments=True):
        text = (cur.query or "").strip().split("\n", 1)[0][:80]
        if text.upper().startswith("COPY INTO"):
            for row in cur.fetchall():
                if len(row) >= 4:
                    # row: file, status, rows_parsed, rows_loaded, ...
                    log.info("COPY %-45s %-10s loaded=%s", row[0], row[1], row[3])
                else:
                    # Already-loaded files return one message, e.g. "0 files processed"
                    log.info("COPY %s", row[0])
        elif text.upper().startswith("SELECT"):
            log.info("Row counts (table, actual, expected):")
            bad = 0
            for name, actual, expected in cur.fetchall():
                flag = "" if actual == expected else "   <-- check"
                bad += actual != expected
                log.info("  %-36s %9s %9s%s", name, actual, expected, flag)
            if bad:
                log.warning("%s table(s) differ from the expected counts", bad)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data-dir", type=Path, default=REPO_ROOT / "data")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    load_dotenv(REPO_ROOT / ".env")

    conn = connect()
    try:
        put_files(conn, args.data_dir)
        run_load_sql(conn)
    finally:
        conn.close()
    log.info("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
