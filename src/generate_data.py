"""
Generate a synthetic e-commerce database for "Cartwise", a fictional online store,
and load it into SQLite (data/cartwise.db) plus CSV copies (data/csv/).

Tables
------
customers     one row per customer (acquisition date, channel, region, test-account flag)
products      product catalogue with price and unit cost
orders        order header (date, status)
order_items   order lines (product, quantity, unit price at time of sale)
web_events    clickstream funnel events for 2025 (session -> purchase)

Business patterns planted for the SQL analysis to discover
----------------------------------------------------------
* Paid Social acquires many customers who rarely come back (low retention).
* Referral and Organic Search customers are the most loyal.
* "Cartwise Plus" (free-shipping membership) launched 2025-03-01 -> repeat purchase lifts.
* Mobile users drop off sharply at checkout (a UX problem), desktop does not.
* Apparel has a much higher return rate.
* A handful of internal test accounts and duplicated tracking events pollute the raw data.

Usage:  python src/generate_data.py
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 7
rng = np.random.default_rng(SEED)
ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"

START, END = pd.Timestamp("2024-01-01"), pd.Timestamp("2025-12-31")
PLUS_LAUNCH = pd.Timestamp("2025-03-01")
N_CUSTOMERS = 12_000

CHANNELS = {  # share of acquisitions, monthly churn hazard, monthly order prob while active
    "Paid Social":    (0.30, 0.38, 0.22),
    "Paid Search":    (0.22, 0.22, 0.26),
    "Organic Search": (0.20, 0.15, 0.28),
    "Email":          (0.10, 0.16, 0.30),
    "Referral":       (0.10, 0.11, 0.32),
    "Affiliate":      (0.08, 0.30, 0.22),
}
REGIONS = ["Northeast", "Southeast", "Midwest", "Southwest", "West"]
REGION_P = [0.24, 0.22, 0.18, 0.14, 0.22]

CATEGORIES = {  # (n products, price range, margin, return rate)
    "Electronics": (30, (25, 400), 0.22, 0.06),
    "Home & Kitchen": (40, (12, 180), 0.38, 0.05),
    "Apparel": (45, (15, 120), 0.55, 0.19),
    "Beauty": (30, (8, 60), 0.60, 0.04),
    "Sports & Outdoors": (30, (15, 250), 0.40, 0.06),
    "Toys & Games": (25, (10, 90), 0.45, 0.04),
}


def make_products() -> pd.DataFrame:
    rows, pid = [], 1
    for cat, (n, (lo, hi), margin, _) in CATEGORIES.items():
        prices = np.round(np.exp(rng.uniform(np.log(lo), np.log(hi), n)), 2) - 0.01
        for p in prices:
            cost = round(p * (1 - margin) * rng.uniform(0.9, 1.1), 2)
            rows.append((pid, f"{cat.split()[0]}-{pid:03d}", cat, float(p), cost))
            pid += 1
    return pd.DataFrame(rows, columns=["product_id", "product_name", "category", "list_price", "unit_cost"])


def make_customers() -> pd.DataFrame:
    days = pd.date_range(START, END - pd.Timedelta(days=1), freq="D")
    season = 1 + 0.6 * days.month.isin([11, 12]) + 0.0
    growth = np.linspace(1.0, 1.6, len(days))
    w = season * growth
    acq = rng.choice(days, size=N_CUSTOMERS, p=w / w.sum())
    ch_names = list(CHANNELS)
    ch_p = np.array([CHANNELS[c][0] for c in ch_names])
    df = pd.DataFrame({
        "customer_id": np.arange(1, N_CUSTOMERS + 1),
        "first_seen_date": pd.to_datetime(acq).normalize(),
        "acquisition_channel": rng.choice(ch_names, size=N_CUSTOMERS, p=ch_p),
        "region": rng.choice(REGIONS, size=N_CUSTOMERS, p=REGION_P),
        "is_test_account": 0,
    })
    # 12 internal QA/test accounts that place lots of fake orders
    test_idx = rng.choice(df.index, 12, replace=False)
    df.loc[test_idx, "is_test_account"] = 1
    return df.sort_values("first_seen_date").reset_index(drop=True)


def make_orders(customers: pd.DataFrame, products: pd.DataFrame):
    cat_return = {c: v[3] for c, v in CATEGORIES.items()}
    prod_by_cat = {c: g for c, g in products.groupby("category")}
    cats = list(CATEGORIES)
    orders, items = [], []
    oid = 100001

    for c in customers.itertuples(index=False):
        _, churn, p_order = CHANNELS[c.acquisition_channel]
        # Each customer has a favourite category (drives basket mix)
        fav = rng.choice(cats, p=[0.18, 0.22, 0.22, 0.14, 0.14, 0.10])
        order_dates = [c.first_seen_date]
        t = c.first_seen_date
        alive = True
        if c.is_test_account:
            n_fake = rng.integers(25, 60)
            order_dates += list(pd.to_datetime(rng.choice(pd.date_range(t, END), n_fake)))
        else:
            while alive:
                t = t + pd.Timedelta(days=int(rng.integers(20, 40)))
                if t > END:
                    break
                plus = t >= PLUS_LAUNCH
                h = churn * (0.72 if plus else 1.0)
                if rng.random() < h:
                    alive = False
                    break
                if rng.random() < min(0.95, p_order * (1.30 if plus else 1.0)):
                    order_dates.append(t + pd.Timedelta(days=int(rng.integers(-5, 6))))

        for d in sorted(order_dates):
            d = min(max(pd.Timestamp(d), c.first_seen_date), END)
            n_lines = int(rng.choice([1, 1, 1, 2, 2, 3, 4]))
            line_cats = [fav if rng.random() < 0.6 else rng.choice(cats) for _ in range(n_lines)]
            r = rng.random()
            ret_p = max(cat_return[lc] for lc in line_cats)
            status = "Cancelled" if r < 0.04 else ("Returned" if r < 0.04 + ret_p else "Completed")
            orders.append((oid, int(c.customer_id), d.strftime("%Y-%m-%d"), status))
            for lc in line_cats:
                prod = prod_by_cat[lc].iloc[int(rng.integers(len(prod_by_cat[lc])))]
                qty = int(rng.choice([1, 1, 1, 1, 2, 2, 3]))
                disc = rng.choice([1.0, 1.0, 1.0, 0.9, 0.8]) if d.month in (11, 12) else rng.choice([1.0, 1.0, 1.0, 1.0, 0.9])
                items.append((oid, int(prod.product_id), qty, round(prod.list_price * disc, 2)))
            oid += 1

    orders = pd.DataFrame(orders, columns=["order_id", "customer_id", "order_date", "status"])
    items = pd.DataFrame(items, columns=["order_id", "product_id", "quantity", "unit_price"])
    items.insert(0, "order_item_id", np.arange(1, len(items) + 1))
    return orders, items


def make_web_events(customers: pd.DataFrame) -> pd.DataFrame:
    """2025 clickstream funnel: session_start -> product_view -> add_to_cart -> begin_checkout -> purchase."""
    n_sessions = 70_000
    days = pd.date_range("2025-01-01", "2025-12-31", freq="D")
    w = 1 + 0.6 * days.month.isin([11, 12])
    sess_day = rng.choice(days, size=n_sessions, p=w / w.sum())
    device = rng.choice(["Mobile", "Desktop", "Tablet"], size=n_sessions, p=[0.62, 0.31, 0.07])
    channel = rng.choice(list(CHANNELS), size=n_sessions, p=[CHANNELS[c][0] for c in CHANNELS])
    known = customers[customers.is_test_account == 0].customer_id.values

    # step-through probabilities by device
    p = {
        "Mobile":  [0.62, 0.27, 0.52, 0.41],
        "Desktop": [0.68, 0.31, 0.58, 0.74],
        "Tablet":  [0.66, 0.29, 0.55, 0.63],
    }
    steps = ["product_view", "add_to_cart", "begin_checkout", "purchase"]
    rows = []
    for i in range(n_sessions):
        sid = f"S{i + 1:06d}"
        uid = int(rng.choice(known)) if rng.random() < 0.45 else None
        ts = pd.Timestamp(sess_day[i]) + pd.Timedelta(seconds=int(rng.integers(0, 86_400)))
        rows.append((sid, uid, ts, "session_start", device[i], channel[i]))
        probs = p[device[i]]
        if channel[i] == "Paid Social":            # low-intent traffic
            probs = [probs[0] * 0.85, probs[1] * 0.75, probs[2], probs[3]]
        for step, pr in zip(steps, probs):
            if rng.random() >= pr:
                break
            ts = ts + pd.Timedelta(seconds=int(rng.integers(10, 400)))
            rows.append((sid, uid, ts, step, device[i], channel[i]))
    ev = pd.DataFrame(rows, columns=["session_id", "customer_id", "event_time", "event_name", "device", "traffic_channel"])
    ev["customer_id"] = ev["customer_id"].astype("Int64")
    # ~0.8% duplicated events (tag fired twice) - a classic tracking data-quality issue
    dup = ev.sample(frac=0.008, random_state=SEED)
    ev = pd.concat([ev, dup]).sort_values(["event_time", "session_id"]).reset_index(drop=True)
    ev["event_time"] = ev["event_time"].dt.strftime("%Y-%m-%d %H:%M:%S")
    ev.insert(0, "event_id", np.arange(1, len(ev) + 1))
    return ev


def main() -> None:
    products = make_products()
    customers = make_customers()
    orders, items = make_orders(customers, products)
    events = make_web_events(customers)
    customers["first_seen_date"] = customers["first_seen_date"].dt.strftime("%Y-%m-%d")

    tables = {"customers": customers, "products": products, "orders": orders,
              "order_items": items, "web_events": events}

    (DATA / "csv").mkdir(parents=True, exist_ok=True)
    db_path = DATA / "cartwise.db"
    db_path.unlink(missing_ok=True)
    schema = (ROOT / "sql" / "00_schema.sql").read_text()
    with sqlite3.connect(db_path) as con:
        con.executescript(schema)
        for name, df in tables.items():
            df.to_csv(DATA / "csv" / f"{name}.csv", index=False)
            df.to_sql(name, con, if_exists="append", index=False)
    for name, df in tables.items():
        print(f"{name:<12} {len(df):>8,} rows")
    print("SQLite database ->", db_path.relative_to(ROOT))


if __name__ == "__main__":
    main()
