#!/bin/bash
# gold_tracker_fixed.sh - Creates normalized tables with scraped data

# Configuration
URL="https://www.kitco.com/charts/livegold.html"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TODAY_DATE=$(date '+%Y-%m-%d')
DB_NAME="comp1314_db"

# MySQL configuration
MYSQL_USER="root"
MYSQL_PASS=""  # Add password here if needed

# Create data directory
DATA_DIR="gold_tracker_data"
mkdir -p "$DATA_DIR"

CSV_FILE="$DATA_DIR/gold_prices.csv"
SQL_FILE="$DATA_DIR/gold_dump_normalized.sql"
LOG_FILE="$DATA_DIR/gold_tracker.log"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Web scraping function - FIXED with correct pattern matching
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
    
    # ==== FIXED: Extract change and percentage with correct patterns ====
    local change=""
    local change_percent=""
    
    # Find the container with the price change data
    local change_container=$(echo "$html_content" | grep -oP 'CommodityPrice_currencyChangeDate__pb28W[^>]*>.*?</div>' | head -1)
    
    if [ -n "$change_container" ]; then
        # Extract ALL text from this container (including HTML comments)
        local container_text=$(echo "$change_container" | sed 's/<[^>]*>//g')
        
        # Now extract the change value (looks like: +49.50 or -49.50)
        change=$(echo "$container_text" | grep -oP '[+-][0-9]+\.[0-9]{2}' | head -1)
        
        # Extract the percentage value (looks like: +1.11% or -1.11%)
        # Remove parentheses and % sign
        change_percent=$(echo "$container_text" | grep -oP '[+-][0-9]+\.[0-9]{2}%' | head -1 | tr -d '%')
    fi
    
    # Alternative method if above doesn't work: Look for spans in sequence
    if [ -z "$change" ] || [ -z "$change_percent" ]; then
        # Get all spans with CommodityPrice_up class
        local spans=$(echo "$html_content" | grep -oP '<span[^>]*class="[^"]*CommodityPrice_up[^"]*"[^>]*>.*?</span>' | head -2)
        
        # First span contains the change value (e.g., +49.50)
        local span1=$(echo "$spans" | head -1)
        change=$(echo "$span1" | sed 's/.*>\([+-]*[0-9]*\.[0-9]*\).*/\1/' | tr -d ',')
        
        # Second span contains the percentage (e.g., (+1.11%))
        local span2=$(echo "$spans" | tail -1)
        change_percent=$(echo "$span2" | sed 's/.*>([+-]*\([0-9]*\.[0-9]*\)%).*/\1/' | tr -d ',')
    fi
    
    # Extract Day's Range
    local day_low=""
    local day_high=""
    
    # Look for the range div
    local range_div=$(echo "$html_content" | grep -oP 'CommodityPrice_priceToday__wBwVD[^>]*>.*?</div>\s*</div>' | head -1)
    
    if [ -n "$range_div" ]; then
        # Extract the two numbers from the divs
        day_low=$(echo "$range_div" | grep -oP '<div>[0-9,]+\.?[0-9]*' | head -1 | sed 's/<div>//' | tr -d ',')
        day_high=$(echo "$range_div" | grep -oP '<div>[0-9,]+\.?[0-9]*' | tail -1 | sed 's/<div>//' | tr -d ',')
    fi
    
    # Clean the values (remove any remaining non-numeric characters except + and -)
    change=$(echo "$change" | sed 's/[^0-9+-.]//g')
    change_percent=$(echo "$change_percent" | sed 's/[^0-9+-.]//g')
    
    # Log raw extracted values
    log_message "EXTRACTED: bid=$bid_price, ask=$ask_price, change=$change, percent=$change_percent, low=$day_low, high=$day_high"
    
    # Validate we have minimum required data
    if [ -z "$bid_price" ] || [ -z "$ask_price" ]; then
        log_message "Error: Could not extract bid/ask prices"
        return 1
    fi
    
    # Output exactly what we found
    echo "${bid_price}:${ask_price}:${change}:${change_percent}:${day_low}:${day_high}"
    return 0
}

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

# Function to create the SQL file with multi-row INSERT format
update_sql_file() {
    local bid="$1" ask="$2" change="$3" change_pct="$4" low="$5" high="$6"
    
    log_message "Updating SQL file..."
    
    # Check if SQL file exists
    if [ ! -f "$SQL_FILE" ]; then
        # Create initial SQL file with table structure
        cat > "$SQL_FILE" << EOF
-- COMP1314 Coursework - Normalized Gold Price Database
-- Clean SQL demonstrating normalization concept
-- Initial creation: $(date '+%Y-%m-%d %H:%M:%S')

-- Create fresh database
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME;
USE $DB_NAME;

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
('$TODAY_DATE', $low, $high);

-- Gold price observations (multiple per day)
INSERT INTO gold_prices (timestamp, bid_price, ask_price, change_amount, change_percent, date, source) VALUES
('$TIMESTAMP', $bid, $ask, $change, $change_pct, '$TODAY_DATE', 'kitco');

EOF
        
        log_message "Created new SQL file with multi-row INSERT format"
        
    else
        # SQL file exists - we need to update it
        
        # For daily_ranges - check if we need to add this date
        if ! grep -q "'$TODAY_DATE', $low, $high" "$SQL_FILE"; then
            sed -i "/INSERT INTO daily_ranges.*VALUES/,/);/{
                s/);$/),\n('$TODAY_DATE', $low, $high);/
            }" "$SQL_FILE"
            log_message "Added new date to daily_ranges: $TODAY_DATE"
        fi
        
        # Always add to gold_prices
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

-- Insert or update daily range for today
INSERT INTO daily_ranges (date, day_low, day_high)
VALUES ('$TODAY_DATE', $low, $high)
ON DUPLICATE KEY UPDATE
    day_low = LEAST(day_low, VALUES(day_low)),
    day_high = GREATEST(day_high, VALUES(day_high));

-- Insert new price observation
INSERT INTO gold_prices (timestamp, bid_price, ask_price, change_amount, change_percent, date, source)
VALUES ('$TIMESTAMP', $bid, $ask, $change, $change_pct, '$TODAY_DATE', 'kitco');
EOF
    
    # Execute the temporary insert
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
        echo "Check internet connection and website availability."
        log_message "Failed to scrape data"
        exit 1
    fi
    
    IFS=':' read -r bid ask change change_pct low high <<< "$data"
    
    # Clean numeric validation (remove signs for validation)
    local bid_clean=$(echo "$bid" | tr -d '+,-')
    local ask_clean=$(echo "$ask" | tr -d '+,-')
    
    if ! [[ "$bid_clean" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$ask_clean" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Error: Invalid data format received."
        log_message "Invalid data format: bid='$bid', ask='$ask'"
        exit 1
    fi
    
    echo ""
    echo "Gold Price Data Retrieved"
    echo "========================="
    
    # Format display - ensure proper signs and formatting
    local change_display="$change"
    local change_pct_display="$change_pct"
    
    # Ensure change has sign for display
    if [[ ! "$change_display" =~ ^[+-] ]]; then
        if [[ "$change_display" =~ ^[0-9] ]]; then
            change_display="+$change_display"
        fi
    fi
    
    # Ensure percentage has sign and % symbol
    if [[ ! "$change_pct_display" =~ ^[+-] ]]; then
        if [[ "$change_pct_display" =~ ^[0-9] ]]; then
            change_pct_display="+$change_pct_display"
        fi
    fi
    
    # Add % symbol if not present
    if [[ ! "$change_pct_display" =~ %$ ]]; then
        change_pct_display="${change_pct_display}%"
    fi
    
    printf "%-20s: $%s\n" "Bid Price" "$bid"
    printf "%-20s: $%s\n" "Ask Price" "$ask"
    printf "%-20s: %s\n" "Price Change" "$change_display"
    printf "%-20s: %s\n" "Change Percent" "$change_pct_display"
    printf "%-20s: $%s - $%s\n" "Day's Range" "$low" "$high"
    printf "%-20s: %s\n" "Collection Time" "$TIMESTAMP"
    printf "%-20s: %s\n" "Date" "$TODAY_DATE"
    echo "========================="
    echo ""
    
    # Generate CSV file
    generate_csv "$bid" "$ask" "$change" "$change_pct" "$low" "$high"
    
    # Update SQL file (multi-row INSERT format)
    update_sql_file "$bid" "$ask" "$change" "$change_pct" "$low" "$high"
    
    # Update database
    update_database "$bid" "$ask" "$change" "$change_pct" "$low" "$high"
    
    log_message "=== Collection completed successfully ==="
}

main