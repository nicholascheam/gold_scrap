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

# Web scraping function
scrape_gold_data() {
    log_message "Attempting to scrape gold data from Kitco..."
    
    # Get HTML content
    local html_content=$(curl -s -L -A "Mozilla/5.0" "$URL")
    
    if [ $? -ne 0 ] || [ -z "$html_content" ]; then
        log_message "Error: Could not fetch HTML content from $URL"
        return 1
    fi
    
    # Save HTML for debugging
    echo "$html_content" > "$DATA_DIR/debug_html_$(date +%s).html"
    
    # Extract Bid price - more flexible pattern
    local bid_price=$(echo "$html_content" | grep -oP '[>\s]\$?1?[0-9]{3,}\.[0-9]{1,2}[<\s]' | head -1 | tr -d '\$><, ' | sed 's/^1//')
    
    if [ -z "$bid_price" ]; then
        # Alternative pattern for bid
        bid_price=$(echo "$html_content" | grep -oP 'Bid[^0-9]*[0-9,]+\.?[0-9]*' | grep -oP '[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    fi
    
    # Extract Ask price
    local ask_price=$(echo "$html_content" | grep -oP 'Ask[^0-9]*[0-9,]+\.?[0-9]*' | grep -oP '[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    
    # If Ask not found, add typical spread to bid
    if [ -z "$ask_price" ] && [ -n "$bid_price" ]; then
        ask_price=$(echo "$bid_price + 0.50" | bc 2>/dev/null || echo "$bid_price")
        log_message "Warning: Ask price not found, using bid + 0.50 spread"
    fi
    
    # --- FIXED: Price Change Extraction ---
    local change=""
    local change_sign="+"
    
    # Method 1: Look for change in various patterns
    change=$(echo "$html_content" | grep -oP '(change|Change|CHANGE)[^0-9]*[+-]?[0-9,]+\.?[0-9]*' | grep -oP '[+-]?[0-9,]+\.?[0-9]*' | head -1)
    
    # Method 2: Look for +/- numbers with parentheses
    if [ -z "$change" ]; then
        change=$(echo "$html_content" | grep -oP '\([+-][0-9,]+\.?[0-9]*\)' | grep -oP '[+-]?[0-9,]+\.?[0-9]*' | head -1)
    fi
    
    # Method 3: Look for any number with + or - sign
    if [ -z "$change" ]; then
        change=$(echo "$html_content" | tr '>' '\n' | grep -E '^[+-][0-9,]+\.?[0-9]*$' | head -1)
    fi
    
    # Method 4: Look for change in common HTML patterns
    if [ -z "$change" ]; then
        change=$(echo "$html_content" | grep -oP 'data-change=["\047][^"\047]*["\047]' | grep -oP '[+-]?[0-9,]+\.?[0-9]*' | head -1)
    fi
    
    # Method 5: Look for change in span/div elements
    if [ -z "$change" ]; then
        change=$(echo "$html_content" | grep -oP '<(span|div)[^>]*>[^<]*[+-][0-9,]+\.?[0-9]*' | grep -oP '[+-][0-9,]+\.?[0-9]*' | head -1)
    fi
    
    # Clean the change value
    change=$(echo "$change" | tr -d ',' | tr -d ' ')
    
    # Determine if change is positive or negative based on HTML context
    if echo "$html_content" | grep -qi 'negative\|down\|loss\|decrease\|red'; then
        change_sign="-"
        if [[ "$change" =~ ^[0-9] ]]; then
            change="-$change"
        fi
    elif echo "$html_content" | grep -qi 'positive\|up\|gain\|increase\|green'; then
        change_sign="+"
        if [[ "$change" =~ ^[0-9] ]]; then
            change="+$change"
        fi
    else
        # Default to positive if we can't determine
        if [ -n "$change" ] && [[ ! "$change" =~ ^[+-] ]]; then
            change="+$change"
        fi
    fi
    
    # Extract Change Percentage
    local change_percent=""
    
    # Method 1: Look for percentage with change
    change_percent=$(echo "$html_content" | grep -oP '[+-]?[0-9,]+\.?[0-9]*%' | head -1)
    
    # Method 2: Look for percentage near the change value
    if [ -z "$change_percent" ] && [ -n "$change" ]; then
        local change_num=$(echo "$change" | tr -d '+-')
        change_percent=$(echo "$html_content" | grep -B2 -A2 "$change_num" | grep -oP '[+-]?[0-9,]+\.?[0-9]*%' | head -1)
    fi
    
    # Method 3: Look for percentage in parentheses
    if [ -z "$change_percent" ]; then
        change_percent=$(echo "$html_content" | grep -oP '\([+-]?[0-9,]+\.?[0-9]*%\)' | grep -oP '[+-]?[0-9,]+\.?[0-9]*' | head -1)
    fi
    
    # Clean the percentage value
    change_percent=$(echo "$change_percent" | tr -d ', %()')
    
    # If we have change but no percentage, calculate approximate
    if [ -z "$change_percent" ] && [ -n "$bid_price" ] && [ -n "$change" ]; then
        local change_clean=$(echo "$change" | tr -d '+-')
        if [[ "$bid_price" =~ ^[0-9.]+$ ]] && [[ "$change_clean" =~ ^[0-9.]+$ ]]; then
            local percent_calc=$(echo "scale=4; $change_clean * 100 / $bid_price" | bc 2>/dev/null)
            if [ -n "$percent_calc" ]; then
                change_percent="${change_sign}${percent_calc}"
                log_message "Calculated change percent: $change_percent"
            fi
        fi
    fi
    
    # Set defaults if still empty
    if [ -z "$change" ]; then
        change="+0.00"
        log_message "Warning: Using default change value"
    fi
    
    if [ -z "$change_percent" ]; then
        change_percent="${change_sign}0.00"
        log_message "Warning: Using default change percent value"
    fi
    
    # Ensure both have proper signs
    if [[ "$change" =~ ^[0-9] ]]; then
        change="${change_sign}${change}"
    fi
    
    if [[ "$change_percent" =~ ^[0-9] ]]; then
        change_percent="${change_sign}${change_percent}"
    fi
    
    # Extract Day's Range with improved patterns
    local day_low=""
    local day_high=""
    
    # Method 1: Look for range patterns
    local range_data=$(echo "$html_content" | grep -i -A5 -B5 'range\|low.*high\|high.*low')
    
    if [ -n "$range_data" ]; then
        day_low=$(echo "$range_data" | grep -oP '\$?[0-9,]+\.?[0-9]*' | head -1 | tr -d '\$,')
        day_high=$(echo "$range_data" | grep -oP '\$?[0-9,]+\.?[0-9]*' | tail -1 | tr -d '\$,')
    fi
    
    # Method 2: Calculate from bid if range not found
    if [ -z "$day_low" ] || [ -z "$day_high" ]; then
        if [ -n "$bid_price" ]; then
            day_low=$(echo "$bid_price - 20" | bc 2>/dev/null || echo "$bid_price")
            day_high=$(echo "$bid_price + 20" | bc 2>/dev/null || echo "$bid_price")
            log_message "Warning: Using calculated day range based on bid"
        else
            day_low="0"
            day_high="0"
            log_message "Warning: Using default day range values"
        fi
    fi
    
    # Validate we have all required data
    if [ -z "$bid_price" ] || [ -z "$ask_price" ]; then
        log_message "Error: Could not extract bid/ask prices"
        return 1
    fi
    
    # Final validation and formatting
    local bid_clean=$(echo "$bid_price" | grep -oP '[0-9]+\.?[0-9]*' | head -1)
    local ask_clean=$(echo "$ask_price" | grep -oP '[0-9]+\.?[0-9]*' | head -1)
    
    if [ -z "$bid_clean" ] || [ -z "$ask_clean" ]; then
        log_message "Error: Invalid numeric values for prices"
        return 1
    fi
    
    # Use cleaned values
    bid_price="$bid_clean"
    ask_price="$ask_clean"
    
    # Clean change formatting
    change=$(echo "$change" | sed 's/^[+-]*\([0-9.-]*\)/\1/')
    if [[ "$change_sign" == "-" ]]; then
        change="-${change#-}"
    else
        change="+${change#+}"
    fi
    
    # Clean percentage formatting
    change_percent=$(echo "$change_percent" | sed 's/^[+-]*\([0-9.-]*\)/\1/')
    if [[ "$change_sign" == "-" ]]; then
        change_percent="-${change_percent#-}"
    else
        change_percent="+${change_percent#+}"
    fi
    
    # Log what we found
    log_message "Extracted data: bid=$bid_price, ask=$ask_price, change=$change, change_percent=$change_percent, low=$day_low, high=$day_high"
    
    # Output format: bid:ask:change:change_percent:low:high
    echo "$bid_price:$ask_price:$change:$change_percent:$day_low:$day_high"
    return 0
}

# [Rest of the functions remain the same - generate_csv, update_sql_file, update_database, main]

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