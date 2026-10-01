"""
Tiny SQL runner: executes the .sql files in /sql against data/cartwise.db.

Each analysis file holds one or more queries, each introduced by a
`-- name: <query_name>` comment. This keeps the SQL readable in GitHub while
letting Python (or a notebook) call any query by name.

Usage:
    python src/sql_runner.py            # build views + run every query -> outputs/*.csv
"""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"
DB_PATH = ROOT / "data" / "cartwise.db"
OUT_DIR = ROOT / "outputs"

_NAME_RE = re.compile(r"^--\s*name:\s*(\w+)\s*$", re.MULTILINE)


def load_queries(sql_file: str | Path) -> dict[str, str]:
    """Return {query_name: sql} for every `-- name:` block in a file."""
    text = Path(sql_file if Path(sql_file).is_absolute() else SQL_DIR / sql_file).read_text()
    parts = _NAME_RE.split(text)
    # parts = [preamble, name1, body1, name2, body2, ...]
    return {name: body.strip().rstrip(";") for name, body in zip(parts[1::2], parts[2::2])}


def connect() -> sqlite3.Connection:
    con = sqlite3.connect(DB_PATH)
    con.executescript((SQL_DIR / "02_views.sql").read_text())
    return con


def run(con: sqlite3.Connection, sql_file: str, name: str) -> pd.DataFrame:
    return pd.read_sql_query(load_queries(sql_file)[name], con)


def run_all() -> None:
    OUT_DIR.mkdir(exist_ok=True)
    con = connect()
    for f in sorted(SQL_DIR.glob("0[1-9]_*.sql")):
        for name, sql in load_queries(f).items():
            df = pd.read_sql_query(sql, con)
            df.to_csv(OUT_DIR / f"{name}.csv", index=False)
            print(f"{f.name:<38} {name:<28} {len(df):>6} rows")
    con.close()


if __name__ == "__main__":
    run_all()
