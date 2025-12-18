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

set style line 1 lc rgb '#0066cc' lw 2 pt 7 ps 0.5
set style line 2 lc rgb '#cc0000' lw 2 pt 7 ps 0.5
set style line 3 lc rgb '#009900' lw 3

plot '$CSV_FILE' using 2:3 with linespoints ls 1 title 'Bid Price', \
     '' using 2:4 with linespoints ls 2 title 'Ask Price', \
     '' using 2:((\$3+\$4)/2) with lines ls 3 title 'Mid Price'
EOF
    
    if [ -f "$output_file" ]; then
        echo "Created: $output_file"
    else
        echo "Error: Failed to create price plot"
    fi
}

# Create bid-ask spread plot
create_spread_plot() {
    echo "Creating bid-ask spread plot..."
    
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

set style line 1 lc rgb '#ff6600' lw 2 pt 7 ps 0.5

plot '$CSV_FILE' using 2:(\$4-\$3) with linespoints ls 1 title 'Bid-Ask Spread'
EOF
    
    if [ -f "$output_file" ]; then
        echo "Created: $output_file"
    else
        echo "Error: Failed to create spread plot"
    fi
}

# Create change analysis plot
create_change_plot() {
    echo "Creating price change analysis plot..."
    
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

set title 'Price Change (Absolute)'
set ylabel 'Change (USD)'
set style line 1 lc rgb '#9966cc' lw 2 pt 7 ps 0.5
plot '$CSV_FILE' using 2:5 with linespoints ls 1 title 'Price Change'

set title 'Price Change (Percentage)'
set ylabel 'Change (%)'
set style line 2 lc rgb '#ff3366' lw 2 pt 7 ps 0.5
plot '$CSV_FILE' using 2:6 with linespoints ls 2 title 'Change %'

unset multiplot
EOF
    
    if [ -f "$output_file" ]; then
        echo "Created: $output_file"
    else
        echo "Error: Failed to create change plot"
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
    
    # Create plots
    create_price_plot
    create_spread_plot
    create_change_plot
    
    echo ""
    echo "Plots created in: $PLOT_DIR"
    echo "  • gold_prices_timeseries.png"
    echo "  • gold_spread.png"
    echo "  • gold_changes.png"
}

# Run the script
main