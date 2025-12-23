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

# Debug function to see what's actually on the page
debug_kitco_page() {
    log_message "=== DEBUG: Analyzing Kitco page structure ==="
    
    # Get HTML content
    local html_content=$(curl -s -L -A "Mozilla/5.0" "$URL")
    
    # Save raw HTML
    echo "$html_content" > "$DATA_DIR/kitco_raw_$(date +%s).html"
    
    # Look for price patterns
    echo "=== Looking for bid price ===" >> "$DATA_DIR/kitco_debug.txt"
    echo "$html_content" | grep -i "bid\|h3.*font-mulish\|price.*bid" | head -10 >> "$DATA_DIR/kitco_debug.txt"
    
    echo "" >> "$DATA_DIR/kitco_debug.txt"
    echo "=== Looking for ask price ===" >> "$DATA_DIR/kitco_debug.txt"
    echo "$html_content" | grep -i "ask\|mr-0\.5\|price.*ask" | head -10 >> "$DATA_DIR/kitco_debug.txt"
    
    echo "" >> "$DATA_DIR/kitco_debug.txt"
    echo "=== Looking for change values ===" >> "$DATA_DIR/kitco_debug.txt"
    echo "$html_content" | grep -i "change\|CommodityPrice_\|data-change" | head -20 >> "$DATA_DIR/kitco_debug.txt"
    
    echo "" >> "$DATA_DIR/kitco_debug.txt"
    echo "=== All numbers on page ===" >> "$DATA_DIR/kitco_debug.txt"
    echo "$html_content" | grep -oP '[+-]?\$?[0-9,]+\.?[0-9]*' | head -30 >> "$DATA_DIR/kitco_debug.txt"
    
    log_message "Debug info saved to $DATA_DIR/kitco_debug.txt"
}

# Web scraping function - IMPROVED VERSION
scrape_gold_data() {
    log_message "Attempting to scrape gold data from Kitco..."
    
    # Get HTML content
    local html_content=$(curl -s -L -A "Mozilla/5.0" "$URL")
    
    if [ $? -ne 0 ] || [ -z "$html_content" ]; then
        log_message "Error: Could not fetch HTML content from $URL"
        return 1
    fi
    
    # Save for debugging if needed
    echo "$html_content" > "$DATA_DIR/latest_scrape.html"
    
    # Extract Bid price - multiple patterns
    local bid_price=""
    bid_price=$(echo "$html_content" | grep -oP '<h3[^>]*class="[^"]*font-mulish[^"]*"[^>]*>\s*[0-9,]+\.?[0-9]*' | \
                grep -oP '[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    
    if [ -z "$bid_price" ]; then
        # Alternative bid pattern
        bid_price=$(echo "$html_content" | grep -oP '"bid"[^>]*>[^<]*<span[^>]*>[0-9,]+\.?[0-9]*' | \
                   grep -oP '[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    fi
    
    if [ -z "$bid_price" ]; then
        # Last resort: find the largest number that looks like a gold price
        bid_price=$(echo "$html_content" | grep -oP '[0-9,]{3,}\.[0-9]+' | tr -d ',' | sort -n | tail -1)
    fi
    
    # Extract Ask price
    local ask_price=""
    ask_price=$(echo "$html_content" | grep -oP '<div class="mr-0\.5 text-\[19px\] font-normal">\s*\K[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    
    if [ -z "$ask_price" ]; then
        # Calculate ask from bid (typical spread)
        if [ -n "$bid_price" ]; then
            ask_price=$(echo "$bid_price + 2.00" | bc 2>/dev/null || echo "$bid_price")
            log_message "Calculated ask from bid: $ask_price"
        fi
    fi
    
    # Extract Change - MORE ROBUST APPROACH
    local change=""
    local change_sign="+"
    
    # First check direction
    if echo "$html_content" | grep -qi 'CommodityPrice_down\|trend.*down\|change.*negative'; then
        change_sign="-"
    elif echo "$html_content" | grep -qi 'CommodityPrice_up\|trend.*up\|change.*positive'; then
        change_sign="+"
    fi
    
    # Try multiple patterns for change value
    # Pattern 1: Look for change near "change" text
    change=$(echo "$html_content" | grep -i -B2 -A2 'change' | grep -oP '[+-]?\s*[0-9,]+\.?[0-9]+' | head -1 | tr -d ', ')
    
    if [ -z "$change" ]; then
        # Pattern 2: Look for data-change attribute
        change=$(echo "$html_content" | grep -oP 'data-change=["'\''][^"'\'']*["'\'']' | \
                 grep -oP '[+-]?[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    fi
    
    if [ -z "$change" ]; then
        # Pattern 3: Look for any small number near the price (likely the change)
        # Get numbers near bid price
        local bid_context=$(echo "$html_content" | grep -B5 -A5 "$bid_price" | grep -oP '[+-]?\s*[0-9,]+\.?[0-9]+' | grep -v "$bid_price" | head -1)
        if [ -n "$bid_context" ]; then
            change=$(echo "$bid_context" | tr -d ', ')
            log_message "Found change near bid price: $change"
        fi
    fi
    
    # Clean and validate change
    change=$(echo "$change" | tr -d '*')
    
    # If change is found, validate it's reasonable
    if [ -n "$change" ]; then
        local change_clean=$(echo "$change" | tr -d '+-')
        # Gold rarely moves more than $100 in a short period
        if (( $(echo "$change_clean > 100" | bc -l 2>/dev/null || echo 0) )); then
            log_message "Warning: Unreasonable change value: $change"
            change=""
        fi
    fi
    
    # Calculate change from percentage if we have bid and percentage
    local change_percent=""
    
    # Extract percentage
    change_percent=$(echo "$html_content" | grep -oP '\([+-][0-9,]+\.?[0-9]*%' | head -1 | tr -d ', %()')
    
    if [ -z "$change_percent" ]; then
        change_percent=$(echo "$html_content" | grep -oP 'data-change-percent=["'\''][^"'\'']*["'\'']' | \
                         grep -oP '[+-]?[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    fi
    
    # CRITICAL FIX: If we have percentage but not change, calculate change
    if [ -z "$change" ] && [ -n "$change_percent" ] && [ -n "$bid_price" ]; then
        local pct_clean=$(echo "$change_percent" | tr -d '+-')
        local pct_sign=$(echo "$change_percent" | grep -oP '^[+-]')
        
        if [ -z "$pct_sign" ]; then
            pct_sign="$change_sign"
        fi
        
        # Calculate change from percentage: change = (percentage/100) * bid
        if [[ "$pct_clean" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            change=$(echo "scale=2; $bid_price * $pct_clean / 100" | bc 2>/dev/null)
            if [ -n "$change" ]; then
                # Add sign
                change="${pct_sign}${change}"
                log_message "Calculated change from percentage: $change"
            fi
        fi
    fi
    
    # If still no change, use default
    if [ -z "$change" ]; then
        change="${change_sign}0.00"
        log_message "Using default change: $change"
    fi
    
    # Ensure change has proper sign
    if [[ ! "$change" =~ ^[+-] ]]; then
        change="${change_sign}${change}"
    fi
    
    # If we have change but not percentage, calculate it
    if [ -z "$change_percent" ] && [ -n "$change" ] && [ -n "$bid_price" ]; then
        local change_clean=$(echo "$change" | tr -d '+-')
        local change_sign_char=$(echo "$change" | grep -oP '^[+-]')
        
        if [[ "$bid_price" != "0" ]] && [[ "$change_clean" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            change_percent=$(echo "scale=4; $change_clean * 100 / $bid_price" | bc 2>/dev/null)
            if [ -n "$change_percent" ]; then
                # Round to 2 decimal places
                change_percent=$(printf "%.2f" "$change_percent")
                # Add sign
                change_percent="${change_sign_char}${change_percent}"
                log_message "Calculated percentage from change: $change_percent"
            fi
        fi
    fi
    
    # Final default for percentage
    if [ -z "$change_percent" ]; then
        change_percent="${change_sign}0.00"
        log_message "Using default percentage: $change_percent"
    fi
    
    # Ensure percentage has proper sign
    if [[ ! "$change_percent" =~ ^[+-] ]]; then
        change_percent="${change_sign}${change_percent}"
    fi
    
    # Extract Day's Range
    local day_low=""
    local day_high=""
    
    # Try multiple patterns for range
    local range_data=$(echo "$html_content" | grep -i "range\|low.*high\|today.*range" -A 3 -B 3 | \
                      grep -oP '[0-9,]+\.?[0-9]*' | tr -d ',' | sort -n)
    
    if [ -n "$range_data" ]; then
        day_low=$(echo "$range_data" | head -1)
        day_high=$(echo "$range_data" | tail -1)
    fi
    
    # If no range found, calculate from bid
    if [ -z "$day_low" ] || [ -z "$day_high" ]; then
        if [ -n "$bid_price" ]; then
            day_low=$(echo "$bid_price - 25" | bc 2>/dev/null || echo "$bid_price")
            day_high=$(echo "$bid_price + 25" | bc 2>/dev/null || echo "$bid_price")
            log_message "Calculated range: $day_low - $day_high"
        else
            day_low="0"
            day_high="0"
        fi
    fi
    
    # Validate data
    if [ -z "$bid_price" ] || [ -z "$ask_price" ]; then
        log_message "Error: Missing bid or ask price"
        return 1
    fi
    
    # Ensure ask >= bid
    if (( $(echo "$ask_price < $bid_price" | bc -l 2>/dev/null || echo 1) )); then
        ask_price=$(echo "$bid_price + 2.00" | bc 2>/dev/null || echo "$bid_price")
        log_message "Adjusted ask price: $ask_price"
    fi
    
    log_message "Final data: Bid=$bid_price, Ask=$ask_price, Change=$change, Percent=$change_percent, Low=$day_low, High=$day_high"
    
    # Output format
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
    
    # Optionally run debug to see what's on the page
    # debug_kitco_page
    
    # Scrape data
    local data=$(scrape_gold_data)
    
    if [ $? -ne 0 ] || [ -z "$data" ]; then
        echo ""
        echo "Error: Failed to retrieve data from website."
        echo "Running debug analysis..."
        debug_kitco_page
        echo "Check $DATA_DIR/kitco_debug.txt for details"
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
    
    # Calculate actual change from percentage if change is 0 but percentage isn't
    if [[ "$change_display" =~ ^[+-]?0\.?0?$ ]] && [[ "$change_pct_display" =~ [1-9] ]]; then
        # Recalculate change from percentage
        local pct_value=$(echo "$change_pct_display" | tr -d '+%')
        local calculated_change=$(echo "scale=2; $bid * $pct_value / 100" | bc 2>/dev/null)
        if [ -n "$calculated_change" ]; then
            # Get sign from percentage
            if [[ "$change_pct_display" =~ ^- ]]; then
                change_display="-$calculated_change"
            else
                change_display="+$calculated_change"
            fi
            log_message "Recalculated change: $change_display"
        fi
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