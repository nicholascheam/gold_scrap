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
    
    # Extract Bid price
    local bid_price=$(echo "$html_content" | grep -oP '<h3 class="font-mulish[^>]*>\s*\K[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    
    # Extract Ask price
    local ask_price=$(echo "$html_content" | grep -oP '<div class="mr-0\.5 text-\[19px\] font-normal">\s*\K[0-9,]+\.?[0-9]*' | head -1 | tr -d ',')
    
    # Extract Change
    local change=$(echo "$html_content" | grep -oP 'CommodityPrice_up[^>]*>\+<!-- -->\K[0-9,]+\.?[0-9]*' | head -1)
    
    # Extract Change Percentage
    local change_percent=$(echo "$html_content" | grep -oP '\(<!-- -->\+<!-- -->\K[0-9,]+\.?[0-9]*' | head -1)
    
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
    
    # Use reasonable defaults if range not found
    if [ -z "$day_low" ] || [ -z "$day_high" ]; then
        day_low=$(echo "$bid_price - 50" | bc 2>/dev/null || echo "0")
        day_high=$(echo "$bid_price + 50" | bc 2>/dev/null || echo "0")
        log_message "Warning: Using calculated day range"
    fi
    
    if [ -z "$change" ]; then
        change="0.00"
        log_message "Warning: Using default change value"
    fi
    
    if [ -z "$change_percent" ]; then
        change_percent="0.00"
        log_message "Warning: Using default change percent"
    fi
    
    log_message "Extracted data: bid=$bid_price, ask=$ask_price, change=$change, change_percent=$change_percent, low=$day_low, high=$day_high"
    
    echo "$bid_price:$ask_price:$change:$change_percent:$day_low:$day_high"
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
    
    # Validate data is numeric
    if ! [[ "$bid" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$ask" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Error: Invalid data format received."
        log_message "Invalid data format: bid='$bid', ask='$ask'"
        exit 1
    fi
    
    echo ""
    echo "Gold Price Data Retrieved"
    echo "========================="
    printf "%-20s: $%s\n" "Bid Price" "$bid"
    printf "%-20s: $%s\n" "Ask Price" "$ask"
    printf "%-20s: +%s\n" "Price Change" "$change"
    printf "%-20s: +%s%%\n" "Change Percent" "$change_pct"
    printf "%-20s: $%s - $%s\n" "Day's Range" "$low" "$high"
    printf "%-20s: %s\n" "Collection Time" "$TIMESTAMP"
    printf "%-20s: %s\n" "Date" "$TODAY_DATE"
    echo "========================="
    echo ""
    
    # Generate CSV file
    generate_csv "$bid" "$ask" "$change" "$change_pct" "$low" "$high"
    
    log_message "=== Collection completed successfully ==="
}

main