#!/bin/bash
# gold_plotter.sh - Creates graphs from gold price CSV data

# Configuration
CSV_FILE="gold_tracker_data/gold_prices.csv"
PLOT_DIR="gold_tracker_data/plots"
LOG_FILE="gold_tracker_data/plotter.log"

# Create directories
mkdir -p "$PLOT_DIR"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

# Check if CSV file exists
check_csv_file() {
    if [ ! -f "$CSV_FILE" ]; then
        log_message "Error: CSV file not found at $CSV_FILE"
        return 1
    fi
    
    local line_count=$(wc -l < "$CSV_FILE" 2>/dev/null)
    if [ "$line_count" -le 1 ]; then
        log_message "Error: CSV file has insufficient data (only headers found)"
        return 1
    fi
    
    log_message "Found CSV file with $((line_count - 1)) data records"
    return 0
}

# Check if gnuplot is installed
check_gnuplot() {
    if ! command -v gnuplot &> /dev/null; then
        log_message "Error: gnuplot is not installed"
        return 1
    fi
    return 0
}

# Create price time series plot (FIXED - no stats command)
create_price_plot() {
    log_message "Creating price time series plot..."
    
    local output_file="$PLOT_DIR/gold_prices_timeseries.png"
    
    gnuplot << EOF
set terminal pngcairo size 1200,800 enhanced font 'Verdana,10'
set output '$output_file'
set title 'Gold Price Time Series (Kitco)'
set xlabel 'Time'
set ylabel 'Price (USD)'
set xdata time
set timefmt '%Y-%m-%d %H:%M:%S'
set format x '%d/%m %H:%M'
set xtics rotate by -45
set grid xtics ytics
set key top left
set datafile separator ","

# Don't use stats in time mode - autoscale will work fine
set autoscale x

# Custom line styles
set style line 1 lc rgb '#0066cc' lw 2 pt 7 ps 0.5
set style line 2 lc rgb '#cc0000' lw 2 pt 7 ps 0.5
set style line 3 lc rgb '#009900' lw 3

plot '$CSV_FILE' using 2:3 with linespoints ls 1 title 'Bid Price', \
     '' using 2:4 with linespoints ls 2 title 'Ask Price', \
     '' using 2:((\$3+\$4)/2) with lines ls 3 title 'Mid Price'
EOF
    
    if [ -f "$output_file" ]; then
        log_message "Created: $output_file"
    else
        log_message "Error: Failed to create price plot"
    fi
}

# Create bid-ask spread plot (FIXED - no stats command)
create_spread_plot() {
    log_message "Creating bid-ask spread plot..."
    
    local output_file="$PLOT_DIR/gold_spread.png"
    
    gnuplot << EOF
set terminal pngcairo size 1200,600 enhanced font 'Verdana,10'
set output '$output_file'
set title 'Gold Price Bid-Ask Spread'
set xlabel 'Time'
set ylabel 'Spread (USD)'
set xdata time
set timefmt '%Y-%m-%d %H:%M:%S'
set format x '%d/%m %H:%M'
set xtics rotate by -45
set grid xtics ytics
set key top left
set datafile separator ","

# Don't use stats in time mode
set autoscale x

# Custom style - just lines
set style line 1 lc rgb '#ff6600' lw 2 pt 7 ps 0.5

plot '$CSV_FILE' using 2:(\$4-\$3) with linespoints ls 1 title 'Bid-Ask Spread'
EOF
    
    if [ -f "$output_file" ]; then
        log_message "Created: $output_file"
    else
        log_message "Error: Failed to create spread plot"
    fi
}

# Create daily statistics plot (no changes needed - doesn't use time mode)
create_daily_stats() {
    log_message "Creating daily statistics plot..."
    
    local output_file="$PLOT_DIR/gold_daily_stats.png"
    
    # Extract unique dates and create daily summary
    local temp_summary="$PLOT_DIR/daily_summary.csv"
    
    # Create daily summary using awk
    awk -F, '
    NR==1 { next }  # Skip header
    {
        date = $1
        bid = $3
        ask = $4
        
        if (!(date in count)) {
            count[date] = 0
            min[date] = bid
            max[date] = bid
            sum_bid[date] = 0
            sum_ask[date] = 0
        }
        
        count[date]++
        sum_bid[date] += bid
        sum_ask[date] += ask
        
        if (bid < min[date]) min[date] = bid
        if (bid > max[date]) max[date] = bid
    }
    END {
        print "date,observations,avg_bid,avg_ask,min_price,max_price,range"
        for (d in count) {
            avg_bid = sum_bid[d] / count[d]
            avg_ask = sum_ask[d] / count[d]
            range = max[d] - min[d]
            printf "%s,%d,%.2f,%.2f,%.2f,%.2f,%.2f\n", d, count[d], avg_bid, avg_ask, min[d], max[d], range
        }
    }
    ' "$CSV_FILE" | sort > "$temp_summary"
    
    if [ ! -s "$temp_summary" ]; then
        log_message "Error: Failed to create daily summary"
        return 1
    fi
    
    gnuplot << EOF
set terminal pngcairo size 1400,800 enhanced font 'Verdana,10'
set output '$output_file'
set title 'Daily Gold Price Statistics'
set datafile separator ","
set style data histogram
set style histogram cluster gap 1
set style fill solid border -1
set boxwidth 0.8 relative
set xtics rotate by -45

# Multiplot layout
set multiplot layout 2,2 title 'Daily Analysis'

# Plot 1: Average prices per day
set title 'Average Daily Prices'
set ylabel 'Price (USD)'
set grid ytics
plot '$temp_summary' using 3:xtic(1) title 'Avg Bid', \
     '' using 4 title 'Avg Ask'

# Plot 2: Daily range
set title 'Daily Price Range'
set ylabel 'Range (USD)'
set grid ytics
plot '$temp_summary' using 7:xtic(1) with boxes lc rgb '#ff9900' title 'Daily Range'

# Plot 3: Number of observations
set title 'Observations per Day'
set ylabel 'Count'
set grid ytics
plot '$temp_summary' using 2:xtic(1) with boxes lc rgb '#6699ff' title 'Observations'

# Plot 4: Min/Max prices
set title 'Daily Min/Max Prices'
set ylabel 'Price (USD)'
set grid ytics
plot '$temp_summary' using 5:xtic(1) with linespoints lc rgb '#cc0000' title 'Min Price', \
     '' using 6 with linespoints lc rgb '#009900' title 'Max Price'

unset multiplot
EOF
    
    if [ -f "$output_file" ]; then
        log_message "Created: $output_file"
        rm -f "$temp_summary"
    else
        log_message "Error: Failed to create daily stats plot"
        [ -f "$temp_summary" ] && rm -f "$temp_summary"
    fi
}

# Create change analysis plot (FIXED - no stats command)
create_change_plot() {
    log_message "Creating price change analysis plot..."
    
    local output_file="$PLOT_DIR/gold_changes.png"
    
    gnuplot << EOF
set terminal pngcairo size 1200,800 enhanced font 'Verdana,10'
set output '$output_file'
set title 'Gold Price Changes Analysis'
set xlabel 'Time'
set ylabel 'Change'
set xdata time
set timefmt '%Y-%m-%d %H:%M:%S'
set format x '%d/%m %H:%M'
set xtics rotate by -45
set grid xtics ytics
set datafile separator ","
set multiplot layout 2,1

# Plot 1: Absolute change
set title 'Price Change (Absolute)'
set ylabel 'Change (USD)'
set style line 1 lc rgb '#9966cc' lw 2 pt 7 ps 0.5
plot '$CSV_FILE' using 2:5 with linespoints ls 1 title 'Price Change'

# Plot 2: Percentage change
set title 'Price Change (Percentage)'
set ylabel 'Change (%)'
set style line 2 lc rgb '#ff3366' lw 2 pt 7 ps 0.5
plot '$CSV_FILE' using 2:6 with linespoints ls 2 title 'Change %'

unset multiplot
EOF
    
    if [ -f "$output_file" ]; then
        log_message "Created: $output_file"
    else
        log_message "Error: Failed to create change plot"
    fi
}

# Main execution
main() {
    echo "=== Gold Price Plotter ==="
    log_message "=== Starting Gold Price Plotter ==="
    
    echo ""
    echo "Generating visualizations from CSV data..."
    echo ""
    
    # Check prerequisites
    if ! check_csv_file; then
        exit 1
    fi
    
    if ! check_gnuplot; then
        echo "gnuplot is not installed. Install with:"
        echo "  Ubuntu/Debian: sudo apt-get install gnuplot"
        echo "  macOS: brew install gnuplot"
        echo "  CentOS/RHEL: sudo yum install gnuplot"
        exit 1
    fi
    
    # Create essential plots
    create_price_plot
    create_spread_plot
    create_daily_stats
    create_change_plot
    
    echo ""
    echo "=== Plot Generation Complete ==="
    echo ""
    echo "Created visualizations in: $PLOT_DIR"
    echo ""
    echo "Plots created:"
    echo "  • gold_prices_timeseries.png - Bid/Ask price timeline"
    echo "  • gold_spread.png - Bid-Ask spread over time"
    echo "  • gold_daily_stats.png - Daily statistics summary"
    echo "  • gold_changes.png - Price change analysis"
    
    log_message "=== Plot generation completed successfully ==="
}

# Run the script
main