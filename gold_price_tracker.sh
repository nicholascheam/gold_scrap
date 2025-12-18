#!/bin/bash
# gold_tracker.sh - Basic gold price scraper

# Configuration
URL="https://www.kitco.com/charts/livegold.html"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TODAY_DATE=$(date '+%Y-%m-%d')

# Create data directory
DATA_DIR="gold_tracker_data"
mkdir -p "$DATA_DIR"
LOG_FILE="$DATA_DIR/gold_tracker.log"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Web scraping function
scrape_gold_data() {
    log_message "Attempting to scrape gold data from Kitco..."
    
    # Get HTML content
    local html_content=$(curl -s -L -A "Mozilla/5.0" "$URL")
    
    if [ $? -ne 0 ] || [ -z "$html_content" ]; then
        log_message "Error: Could not fetch HTML content from $URL"
        return 1
    fi
    
    # Extract Bid price
    local bid_price=$(echo "$html_content" | grep -oP '<h3 class="font-mulish[^>]*>\s*\K[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    
    # Extract Ask price
    local ask_price=$(echo "$html_content" | grep -oP '<div class="mr-0\.5 text-\[19px\] font-normal">\s*\K[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    
    # Extract Change
    local change=$(echo "$html_content" | grep -oP 'CommodityPrice_up[^>]*>\K[+-]?[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    
    # Extract Change Percentage
    local change_percent=$(echo "$html_content" | grep -oP '\([+-][0-9,]+\.?[0-9]*%' | head -1 | tr -d ',()%')
    
    # Extract Day's Range
    local range_html=$(echo "$html_content" | grep -A 3 'CommodityPrice_priceToday__wBwVD')
    
    local day_low=""
    local day_high=""
    
    if [ -n "$range_html" ]; then
        day_low=$(echo "$range_html" | grep -oP '<div>\K[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
        day_high=$(echo "$range_html" | grep -oP '<div>\K[0-9,]+\.?[0-9]*' | tail -1 | tr -d ',')
    fi
    
    # Validate we have all required data
    if [ -z "$bid_price" ] || [ -z "$ask_price" ]; then
        log_message "Error: Could not extract bid/ask prices"
        return 1
    fi
    
    log_message "Extracted data: bid=$bid_price, ask=$ask_price, change=$change, change_percent=$change_percent"
    
    echo "$bid_price:$ask_price:$change:$change_percent:$day_low:$day_high"
    return 0
}

CSV_FILE="$DATA_DIR/gold_prices.csv"

# Generate CSV file with appending
generate_csv() {
    local bid="$1" ask="$2" change="$3" change_pct="$4" low="$5" high="$6"
    
    # Create CSV header if file doesn't exist
    if [ ! -f "$CSV_FILE" ]; then
        echo "date,timestamp,bid_price,ask_price,change_amount,change_percent,day_low,day_high,source" > "$CSV_FILE"
        log_message "Created new CSV file with headers"
    fi
    
    # Append data to CSV
    echo "$TODAY_DATE,$TIMESTAMP,$bid,$ask,$change,$change_pct,$low,$high,kitco" >> "$CSV_FILE"
    
    log_message "Appended data to CSV file: $CSV_FILE"
}

DB_NAME="comp1314_db"
SQL_FILE="$DATA_DIR/gold_dump_normalized.sql"

# Function to create the SQL file with multi-row INSERT format
update_sql_file() {
    local bid="$1" ask="$2" change="$3" change_pct="$4" low="$5" high="$6"
    
    log_message "Updating SQL file..."
    
    # Check if SQL file exists
    if [ ! -f "$SQL_FILE" ]; then
        # Create initial SQL file with table structure
        cat > "$SQL_FILE" << EOF
-- COMP1314 Coursework - Normalized Gold Price Database
-- Initial creation: $(date '+%Y-%m-%d %H:%M:%S')

-- Create fresh database
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME;
USE $DB_NAME;

-- Daily price ranges (one record per day)
CREATE TABLE daily_ranges (
    date DATE PRIMARY KEY,
    day_low DECIMAL(10,2) NOT NULL,
    day_high DECIMAL(10,2) NOT NULL,
    range_spread DECIMAL(10,2) AS (day_high - day_low),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Price observations (multiple per day)
CREATE TABLE gold_prices (
    price_id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    bid_price DECIMAL(10,2) NOT NULL,
    ask_price DECIMAL(10,2) NOT NULL,
    spread DECIMAL(10,2) AS (ask_price - bid_price),
    change_amount DECIMAL(10,2),
    change_percent DECIMAL(10,4),
    date DATE NOT NULL,
    source VARCHAR(50) DEFAULT 'kitco',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY idx_unique_timestamp (timestamp, source),
    FOREIGN KEY (date) REFERENCES daily_ranges(date)
);

-- INSERT DATA
-- Daily ranges
INSERT INTO daily_ranges (date, day_low, day_high) VALUES
('$TODAY_DATE', $low, $high);

-- Price observations
INSERT INTO gold_prices (timestamp, bid_price, ask_price, change_amount, change_percent, date, source) VALUES
('$TIMESTAMP', $bid, $ask, $change, $change_pct, '$TODAY_DATE', 'kitco');

EOF
        
        log_message "Created new SQL file with database structure"
        
    else
        # SQL file exists - update it
        if ! grep -q "'$TODAY_DATE', $low, $high" "$SQL_FILE"; then
            sed -i "/INSERT INTO daily_ranges.*VALUES/,/);/{
                s/);$/),\n('$TODAY_DATE', $low, $high);/
            }" "$SQL_FILE"
        fi
        
        sed -i "/INSERT INTO gold_prices.*VALUES/,/);/{
            s/);$/),\n('$TIMESTAMP', $bid, $ask, $change, $change_pct, '$TODAY_DATE', 'kitco');/
        }" "$SQL_FILE"
        
        log_message "Added new price observation: $TIMESTAMP"
    fi
}

# Execute SQL to update database
update_database() {
    local bid="$1" ask="$2" change="$3" change_pct="$4" low="$5" high="$6"
    
    log_message "Attempting to update database $DB_NAME..."
    
    # Check MySQL connection
    if ! mysql $MYSQL_USER $MYSQL_PASS -e "SELECT 1" 2>/dev/null; then
        return 1
    fi
    
    # Check if database exists
    if ! mysql $MYSQL_USER $MYSQL_PASS -e "USE $DB_NAME" 2>/dev/null; then
        # Create database from SQL file
        mysql $MYSQL_USER $MYSQL_PASS < "$SQL_FILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "Database $DB_NAME created from SQL file"
            return 0
        else
            log_message "Failed to create database from SQL file"
            return 1
        fi
    fi
    
    # Database exists, insert new data
    local temp_sql="$DATA_DIR/temp_insert_$(date +%s).sql"
    
    cat > "$temp_sql" << EOF
USE $DB_NAME;

-- Insert or update daily range
INSERT INTO daily_ranges (date, day_low, day_high)
VALUES ('$TODAY_DATE', $low, $high)
ON DUPLICATE KEY UPDATE
    day_low = LEAST(day_low, VALUES(day_low)),
    day_high = GREATEST(day_high, VALUES(day_high));

-- Insert new price observation
INSERT INTO gold_prices (timestamp, bid_price, ask_price, change_amount, change_percent, date, source)
VALUES ('$TIMESTAMP', $bid, $ask, $change, $change_pct, '$TODAY_DATE', 'kitco');
EOF
    
    # Execute the insert
    if mysql $MYSQL_USER $MYSQL_PASS < "$temp_sql" 2>/dev/null; then
        log_message "Successfully updated database"
        rm -f "$temp_sql"
        return 0
    else
        log_message "Failed to update database"
        rm -f "$temp_sql"
        return 1
    fi
}

# Main execution
main() {
    echo "=== Gold Price Tracker ==="
    log_message "=== Starting Gold Tracker ==="
    
    echo ""
    echo "Fetching real-time gold prices from Kitco..."
    
    # Scrape data
    local data=$(scrape_gold_data)
    
    if [ $? -ne 0 ] || [ -z "$data" ]; then
        echo ""
        echo "Error: Failed to retrieve data from website."
        exit 1
    fi
    
    IFS=':' read -r bid ask change change_pct low high <<< "$data"
    
    echo ""
    echo "Gold Price Data Retrieved"
    echo "========================="
    printf "%-20s: $%s\n" "Bid Price" "$bid"
    printf "%-20s: $%s\n" "Ask Price" "$ask"
    printf "%-20s: %s\n" "Price Change" "$change"
    printf "%-20s: %s%%\n" "Change Percent" "$change_pct"
    printf "%-20s: $%s - $%s\n" "Day's Range" "$low" "$high"
    printf "%-20s: %s\n" "Collection Time" "$TIMESTAMP"
    printf "%-20s: %s\n" "Date" "$TODAY_DATE"
    echo "========================="
    echo ""
    
    # Generate CSV file
    generate_csv "$bid" "$ask" "$change" "$change_pct" "$low" "$high"
    
    # Update SQL file
    update_sql_file "$bid" "$ask" "$change" "$change_pct" "$low" "$high"
    
    # Update database
    update_database "$bid" "$ask" "$change" "$change_pct" "$low" "$high"
    
    log_message "=== Collection completed successfully ==="
}

main