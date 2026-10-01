-- =====================================================================
-- Cartwise e-commerce database: schema (SQLite)
-- =====================================================================

DROP TABLE IF EXISTS web_events;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id          INTEGER PRIMARY KEY,
    first_seen_date      DATE    NOT NULL,   -- date of first purchase
    acquisition_channel  TEXT    NOT NULL,
    region               TEXT    NOT NULL,
    is_test_account      INTEGER NOT NULL DEFAULT 0   -- internal QA accounts (exclude!)
);

CREATE TABLE products (
    product_id    INTEGER PRIMARY KEY,
    product_name  TEXT NOT NULL,
    category      TEXT NOT NULL,
    list_price    REAL NOT NULL,
    unit_cost     REAL NOT NULL
);

CREATE TABLE orders (
    order_id     INTEGER PRIMARY KEY,
    customer_id  INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date   DATE    NOT NULL,
    status       TEXT    NOT NULL CHECK (status IN ('Completed', 'Returned', 'Cancelled'))
);

CREATE TABLE order_items (
    order_item_id  INTEGER PRIMARY KEY,
    order_id       INTEGER NOT NULL REFERENCES orders(order_id),
    product_id     INTEGER NOT NULL REFERENCES products(product_id),
    quantity       INTEGER NOT NULL,
    unit_price     REAL    NOT NULL       -- price actually paid (after discounts)
);

CREATE TABLE web_events (
    event_id         INTEGER PRIMARY KEY,
    session_id       TEXT NOT NULL,
    customer_id      INTEGER,            -- NULL for anonymous visitors
    event_time       TIMESTAMP NOT NULL,
    event_name       TEXT NOT NULL,      -- session_start, product_view, add_to_cart, begin_checkout, purchase
    device           TEXT NOT NULL,
    traffic_channel  TEXT NOT NULL
);

CREATE INDEX idx_orders_customer   ON orders(customer_id);
CREATE INDEX idx_orders_date       ON orders(order_date);
CREATE INDEX idx_items_order       ON order_items(order_id);
CREATE INDEX idx_events_session    ON web_events(session_id);
