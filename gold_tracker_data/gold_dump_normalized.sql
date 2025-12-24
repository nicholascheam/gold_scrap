-- COMP1314 Coursework - Normalized Gold Price Database
-- Clean SQL demonstrating normalization concept
-- Initial creation: 2025-12-24 04:39:18

-- Create fresh database
DROP DATABASE IF EXISTS comp1314_db;
CREATE DATABASE comp1314_db;
USE comp1314_db;

-- ============================================
-- TABLE 1: Daily price ranges (Normalized)
-- Stores day's range once per day (1NF, 2NF, 3NF)
-- ============================================
CREATE TABLE daily_ranges (
    date DATE PRIMARY KEY,           -- Natural primary key
    day_low DECIMAL(10,2) NOT NULL,
    day_high DECIMAL(10,2) NOT NULL,
    range_spread DECIMAL(10,2) AS (day_high - day_low),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- TABLE 2: Price observations (Normalized)
-- Stores multiple price observations per day
-- References daily_ranges via date foreign key
-- ============================================
CREATE TABLE gold_prices (
    price_id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    bid_price DECIMAL(10,2) NOT NULL,
    ask_price DECIMAL(10,2) NOT NULL,
    spread DECIMAL(10,2) AS (ask_price - bid_price),
    change_amount DECIMAL(10,2),
    change_percent DECIMAL(10,4),
    date DATE NOT NULL,              -- Foreign key to daily_ranges
    source VARCHAR(50) DEFAULT 'kitco',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY idx_unique_timestamp (timestamp, source),
    FOREIGN KEY (date) REFERENCES daily_ranges(date)
);

-- ============================================
-- INSERT ALL DATA
-- Multi-row INSERT format
-- ============================================

-- Daily ranges (one per day)
INSERT INTO daily_ranges (date, day_low, day_high) VALUES
('2025-12-24', 4430.40, 4498.60),
('2025-12-24', 4430.40, 4500.50),
('2025-12-24', 4471.80, 4525.80);

-- Gold price observations (multiple per day)
INSERT INTO gold_prices (timestamp, bid_price, ask_price, change_amount, change_percent, date, source) VALUES
('2025-12-24 04:39:17', 4490.40, 4492.40, +47.80, +1.08, '2025-12-24', 'kitco'),
('2025-12-24 04:42:03', 4489.00, 4491.00, +46.40, +1.04, '2025-12-24', 'kitco'),
('2025-12-24 05:06:06', 4492.80, 4494.80, +50.20, +1.13, '2025-12-24', 'kitco'),
('2025-12-24 13:01:13', 4497.60, 4499.60, +13.90, +0.31, '2025-12-24', 'kitco'),
('2025-12-24 13:04:04', 4499.70, 4501.70, +16.00, +0.36, '2025-12-24', 'kitco'),
('2025-12-24 13:05:04', 4499.70, 4501.70, +16.00, +0.36, '2025-12-24', 'kitco'),
('2025-12-24 13:06:04', 4495.20, 4497.20, +11.50, +0.26, '2025-12-24', 'kitco'),
('2025-12-24 14:00:04', 4488.70, 4490.70, +5.00, +0.11, '2025-12-24', 'kitco'),
('2025-12-24 15:00:04', 4493.20, 4495.20, +9.50, +0.21, '2025-12-24', 'kitco'),
('2025-12-24 16:00:04', 4483.20, 4485.20, -0.50, -0.01, '2025-12-24', 'kitco'),
('2025-12-24 17:00:05', 4482.00, 4484.00, -1.70, -0.04, '2025-12-24', 'kitco'),
('2025-12-24 18:00:05', 4493.90, 4495.90, +10.20, +0.23, '2025-12-24', 'kitco'),
('2025-12-24 19:00:05', 4488.60, 4490.60, +4.90, +0.11, '2025-12-24', 'kitco'),
('2025-12-24 20:00:06', 4490.60, 4492.60, +6.90, +0.15, '2025-12-24', 'kitco');

