#!/bin/bash
# gold_plotter.sh - Creates graphs from gold price CSV data

# Configuration
CSV_FILE="gold_tracker_data/gold_prices.csv"
PLOT_DIR="gold_tracker_data/plots"

# Create directories
mkdir -p "$PLOT_DIR"

# Check if CSV file exists
check_csv_file() {
    if [ ! -f "$CSV_FILE" ]; then
        echo "Error: CSV file not found at $CSV_FILE"
        return 1
    fi
    
    local line_count=$(wc -l < "$CSV_FILE" 2>/dev/null)
    if [ "$line_count" -le 1 ]; then
        echo "Error: CSV file has insufficient data (only headers found)"
        return 1
    fi
    
    echo "Found CSV file with $((line_count - 1)) data records"
    return 0
}

# Check if gnuplot is installed
check_gnuplot() {
    if ! command -v gnuplot &> /dev/null; then
        echo "Error: gnuplot is not installed"
        return 1
    fi
    return 0
}

# Create price time series plot
create_price_plot() {
    echo "Creating price time series plot..."
    
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

plot '$CSV_FILE' using 2:3 with linespoints title 'Bid Price', \
     '' using 2:4 with linespoints title 'Ask Price'
EOF
    
    if [ -f "$output_file" ]; then
        echo "Created: $output_file"
    else
        echo "Error: Failed to create price plot"
    fi
}

# Main execution
main() {
    echo "=== Gold Price Plotter ==="
    echo ""
    
    # Check prerequisites
    if ! check_csv_file; then
        exit 1
    fi
    
    if ! check_gnuplot; then
        echo "Install gnuplot with: sudo apt-get install gnuplot"
        exit 1
    fi
    
    # Create plot
    create_price_plot
    
    echo ""
    echo "Plot created: $PLOT_DIR/gold_prices_timeseries.png"
}

# Run the script
main