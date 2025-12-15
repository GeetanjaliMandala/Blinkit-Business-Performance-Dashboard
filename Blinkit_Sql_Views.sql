----------------------------------------------------
--  BLINKIT SQL PROJECT – FULL DATABASE + DATE FIXES + KPI VIEWS
----------------------------------------------------

DROP DATABASE IF EXISTS blinkit_db;
CREATE DATABASE blinkit_db;
USE blinkit_db;

----------------------------------------------------
-- 1. CREATE TABLES
----------------------------------------------------

CREATE TABLE customers (
    customer_id BIGINT PRIMARY KEY,
    customer_name VARCHAR(100),
    email VARCHAR(200),
    phone VARCHAR(20),
    address TEXT,
    area VARCHAR(100),
    pincode INT,
    registration_date VARCHAR(20),   -- will convert later
    customer_segment VARCHAR(50),
    total_orders INT,
    avg_order_value DECIMAL(10,2)
);

CREATE TABLE products (
    product_id BIGINT PRIMARY KEY,
    product_name VARCHAR(200),
    category VARCHAR(100),
    brand VARCHAR(100),
    price DECIMAL(10,2),
    mrp DECIMAL(10,2),
    margin_percentage INT,
    shelf_life_days INT,
    min_stock_level INT,
    max_stock_level INT
);

CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    order_date VARCHAR(50),                 -- will convert later
    promised_delivery_time VARCHAR(50),     -- will convert later
    actual_delivery_time VARCHAR(50),       -- will convert later
    delivery_status VARCHAR(50),
    order_total DECIMAL(10,2),
    payment_method VARCHAR(50),
    delivery_partner_id BIGINT,
    store_id BIGINT,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_id BIGINT,
    product_id BIGINT,
    quantity INT,
    unit_price DECIMAL(10,2),
    PRIMARY KEY(order_id, product_id),
    FOREIGN KEY(order_id) REFERENCES orders(order_id),
    FOREIGN KEY(product_id) REFERENCES products(product_id)
);

CREATE TABLE customer_feedback (
    feedback_id BIGINT PRIMARY KEY,
    order_id BIGINT,
    customer_id BIGINT,
    rating INT,
    feedback_text TEXT,
    feedback_category VARCHAR(100),
    sentiment VARCHAR(50),
    feedback_date VARCHAR(20),  -- will convert later
    FOREIGN KEY(order_id) REFERENCES orders(order_id),
    FOREIGN KEY(customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE marketing_performance (
    campaign_id BIGINT PRIMARY KEY,
    campaign_name VARCHAR(200),
    date VARCHAR(20),  -- will convert later
    target_audience VARCHAR(100),
    channel VARCHAR(50),
    impressions INT,
    clicks INT,
    conversions INT,
    spend DECIMAL(10,2),
    revenue_generated DECIMAL(10,2),
    roas DECIMAL(5,2)
);

SELECT COUNT(*) FROM customers;
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM products;
SELECT COUNT(*) FROM order_items;
SELECT COUNT(*) FROM customer_feedback;
SELECT COUNT(*) FROM marketing_performance;

----------------------------------------------------
-- 2. Disable Safe Updates to Allow Fixing Dates
----------------------------------------------------
SET SQL_SAFE_UPDATES = 0;

----------------------------------------------------
-- 3. FIX DATE FORMATS AFTER CSV IMPORT
----------------------------------------------------

--  Fix customers.registration_date (DD-MM-YYYY → DATE)
UPDATE customers
SET registration_date = STR_TO_DATE(registration_date, '%d-%m-%Y')
WHERE registration_date LIKE '__-__-____';

ALTER TABLE customers MODIFY registration_date DATE;

--  Fix orders (DD-MM-YYYY HH:MM → DATETIME)
UPDATE orders
SET 
    order_date = STR_TO_DATE(order_date, '%d-%m-%Y %H:%i'),
    promised_delivery_time = STR_TO_DATE(promised_delivery_time, '%d-%m-%Y %H:%i'),
    actual_delivery_time = STR_TO_DATE(actual_delivery_time, '%d-%m-%Y %H:%i')
WHERE order_date LIKE '__-__-____%';

ALTER TABLE orders 
MODIFY order_date DATETIME,
MODIFY promised_delivery_time DATETIME,
MODIFY actual_delivery_time DATETIME;

--  Fix feedback_date (DD-MM-YYYY → DATE)
UPDATE customer_feedback
SET feedback_date = STR_TO_DATE(feedback_date, '%d-%m-%Y')
WHERE feedback_date LIKE '__-__-____';

ALTER TABLE customer_feedback MODIFY feedback_date DATE;

--  Fix marketing_performance.date (DD-MM-YYYY → DATE)
UPDATE marketing_performance
SET date = STR_TO_DATE(date, '%d-%m-%Y')
WHERE date LIKE '__-__-____';

ALTER TABLE marketing_performance MODIFY date DATE;

----------------------------------------------------
-- 4. Re-enable Safe Update Mode
----------------------------------------------------
SET SQL_SAFE_UPDATES = 1;

----------------------------------------------------
-- 5. KPI VIEWS (7 Dashboard Views)
----------------------------------------------------

-- 1️. Monthly Revenue View
CREATE OR REPLACE VIEW vw_monthly_revenue AS
SELECT 
    DATE_FORMAT(order_date, '%Y-%m') AS month,
    SUM(order_total) AS total_revenue
FROM orders
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;

-- 2️. Average Delivery Time View
CREATE OR REPLACE VIEW vw_avg_delivery_time AS
SELECT
    c.area,
    AVG(TIMESTAMPDIFF(MINUTE, o.order_date, o.actual_delivery_time)) AS avg_delivery_minutes
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.actual_delivery_time IS NOT NULL
GROUP BY c.area;

-- 3️. Delivery Delay Analysis
CREATE OR REPLACE VIEW vw_delivery_delay AS
SELECT 
    delivery_status,
    COUNT(*) AS total_orders
FROM orders
GROUP BY delivery_status;

-- 4️. Orders by Time of Day
CREATE OR REPLACE VIEW vw_orders_by_time_of_day AS
SELECT 
    CASE
        WHEN HOUR(order_date) BETWEEN 6 AND 11 THEN 'Morning'
        WHEN HOUR(order_date) BETWEEN 12 AND 17 THEN 'Afternoon'
        WHEN HOUR(order_date) BETWEEN 18 AND 22 THEN 'Evening'
        ELSE 'Late Night'
    END AS time_of_day,
    COUNT(*) AS total_orders
FROM orders
GROUP BY time_of_day;

-- 5️. Customer Segments View
CREATE OR REPLACE VIEW vw_customer_types AS
SELECT
    customer_segment,
    COUNT(customer_id) AS user_count
FROM customers
GROUP BY customer_segment;

-- 6️. Restock Prediction View
CREATE OR REPLACE VIEW vw_restock_products AS
SELECT
    p.product_id,
    p.product_name,
    SUM(oi.quantity) AS qty_sold_last_7_days,
    p.min_stock_level,
    p.max_stock_level
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.order_date >= (
    SELECT DATE_SUB(MAX(order_date), INTERVAL 7 DAY) 
    FROM orders
)
GROUP BY 
    p.product_id, 
    p.product_name, 
    p.min_stock_level, 
    p.max_stock_level
ORDER BY qty_sold_last_7_days DESC;

-- 7️. Top Selling Products
CREATE OR REPLACE VIEW vw_top_products AS
SELECT 
    p.product_id,
    p.product_name,
    SUM(oi.quantity) AS total_qty_sold
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.product_id, p.product_name
ORDER BY total_qty_sold DESC
LIMIT 10;

----------------------------------------------------
-- END OF FILE
----------------------------------------------------
SELECT DATABASE();
SELECT COUNT(*) FROM blinkit_db.customers;
SELECT COUNT(*) FROM blinkit_db.orders;
SELECT COUNT(*) FROM blinkit_db.order_items;
SELECT COUNT(*) FROM blinkit_db.customer_feedback;
SELECT COUNT(*) FROM blinkit_db.products;

SELECT 
    MIN(order_date) AS earliest_date,
    MAX(order_date) AS latest_date
FROM orders;