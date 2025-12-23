-- COMP1314 Coursework - Normalized Gold Price Database
-- Clean SQL demonstrating normalization concept
-- Initial creation: 2025-12-18 03:31:08

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
('2025-12-18', 4301.10, 4349.80),
('2025-12-18', 4323.80, 4343.90),
('2025-12-22', 4337.30, 4421.20),
('2025-12-23', 4337.30, 4434.70),
('2025-12-23', 4441.70, 4498.60),
('2025-12-24', 4430.40, 4498.60);

-- Gold price observations (multiple per day)
INSERT INTO gold_prices (timestamp, bid_price, ask_price, change_amount, change_percent, date, source) VALUES
('2025-12-18 03:31:07', 4339.00, 4341.00, 37.70, 0.88, '2025-12-18', 'kitco'),
('2025-12-18 03:32:14', 4339.70, 4341.70, 38.40, 0.89, '2025-12-18', 'kitco'),
('2025-12-18 12:34:15', 4329.20, 4331.20, 0.00, 0.00, '2025-12-18', 'kitco'),
('2025-12-18 12:34:33', 4329.20, 4331.20, 0.00, 0.00, '2025-12-18', 'kitco'),
('2025-12-18 12:38:39', 4329.50, 4331.50, --8, 0.00, '2025-12-18', 'kitco'),
('2025-12-18 12:41:46', 4328.30, 4330.30, -9.00, +0.00, '2025-12-18', 'kitco'),
('2025-12-18 12:45:25', 4329.20, 4331.20, -8.10, -0.19, '2025-12-18', 'kitco'),
('2025-12-18 12:59:32', 4331.20, 4333.20, -6.10, -0.14, '2025-12-18', 'kitco'),
('2025-12-18 14:28:37', 4332.00, 4334.00, -5.30, -0.12, '2025-12-18', 'kitco'),
('2025-12-22 21:02:16', 4414.80, 4416.80, -5330923290342169, -1.78, '2025-12-22', 'kitco'),
('2025-12-23 00:00:01', 4433.30, 4435.30, -5330923290342169, -2.20, '2025-12-23', 'kitco'),
('2025-12-23 23:03:53', 4447.40, 4449.40, -5330923290342169, -0.11, '2025-12-23', 'kitco'),
('2025-12-24 01:43:29', 4476.70, 4478.70, -5330923290342169, -0.77, '2025-12-24', 'kitco'),
('2025-12-24 01:44:47', 4476.60, 4478.60, -5330923290342169, -0.77, '2025-12-24', 'kitco'),
('2025-12-24 04:37:53', 4491.40, 4493.40, +48.80, +1.10, '2025-12-24', 'kitco');

