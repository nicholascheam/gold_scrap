# 1.0 System Overview
The Gold Price Tracker is an automated Bash-based system that collects gold price data, generates visualizations, and commits results to GitHub. The system runs hourly via cron, fetching live gold prices, storing them in CSV format, creating SQL backups, and generating PNG charts for analysis.

Unlike traditional database systems, this implementation uses Git for version control of data files, making historical tracking and collaboration seamless through GitHub.

# 1.1 Project Folder Structure
~~~~~~~~~
~/
├── gold_price_tracker.sh           # Main data collection script
├── plot_gold_price.sh              # Gnuplot visualization script
├── .ssh/id_ed25519_cron            # SSH key for GitHub automation
├── gold_tracker_data/              # All data storage
│   ├── gold_prices.csv             # Time-series price history
│   ├── gold_dump_normalized.sql    # MySQL-compatible database export
│   └── plots/                      # Generated charts
│       ├── gold_prices_timeseries.png
│       ├── gold_changes.png
│       ├── gold_spread.png
│       └── gold_daily_stats.png
└── hourly_gold.log                 # Cron execution log
~~~~~~~~~
# 2.0 Prerequisites and Installation
# 2.1 Required Packages
~~~
# Install dependencies (Ubuntu/Debian)

sudo apt install -y curl grep bc gnuplot git

# Verify installations

curl --version
gnuplot --version
git --version
~~~
# 2.2 SSH Key Setup for GitHub Automation
~~~
# Generate dedicated SSH key (no passphrase for automation)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_cron -N ""
# Add public key to GitHub
cat ~/.ssh/id_ed25519_cron.pub
# Copy output to: GitHub → Settings → SSH and GPG keys → New SSH key
~~~
# 2.3 Git Repository Configuration
~~~
# Initialize repository
cd ~/
git init
# Set SSH remote URL
git remote add origin git@github.com:<user>/<git repo>

# Configure Git to use SSH key
export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_cron"

# Test SSH connection
ssh -i ~/.ssh/id_ed25519_cron -T git@github.com
# Expected: "Hi <user>! You've successfully authenticated..."
~~~
# 2.4 File Permissions
~~~
# Make scripts executable
chmod +x ~/*.sh

# Create necessary directories
mkdir -p ~/gold_tracker_data/plots
~~~
# 3.0 Core Scripts
# 3.1 `gold_price_tracker.sh` - Data Collection
Purpose: Fetches current gold prices from financial sources and appends to CSV.

Key Features:

Downloads live gold price data using `curl`

Extracts key metrics: Ask, Bid, High, Low, Change

Appends timestamped data to CSV with proper formatting

Generates normalized SQL dump for database compatibility

Handles error cases with fallback values

Execution:

~~~
cd ~/
./gold_price_tracker.sh
# OR
bash gold_price_tracker.sh
~~~
Output:

Updates `gold_tracker_data/gold_prices.csv`

Creates/updates `gold_tracker_data/gold_dump_normalized.sql`
# 3.2 `plot_gold_price.sh` - Visualization
Purpose: Generates four types of charts using gnuplot.

Chart Types:

Timeseries Plot (`gold_prices_timeseries.png`) - Price trends over time

Change Analysis (`gold_changes.png`) - Daily price changes

Spread Visualization (`gold_spread.png`) - Bid-Ask spread analysis

Daily Statistics (`gold_daily_stats.png`) - Summary statistics

Execution:

~~~
cd ~/
./plot_gold_price.sh
# OR
bash plot_gold_price.sh
~~~
Prerequisites: Requires `gnuplot` installed

~~~
sudo apt install gnuplot
~~~
# 4.0 Automation with Cron
# 4.1 Cron Job Configuration
The system runs automatically every hour at XX:00.

Cron Command:

~~~
0 * * * * cd ~/ && export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_cron" && git fetch origin && git reset --hard origin/main && bash gold_price_tracker.sh && bash plot_gold_price.sh && git add gold_tracker_data/gold_prices.csv gold_tracker_data/gold_dump_normalized.sql gold_tracker_data/plots/*.png && git commit -m "hourly gold update" && git push origin main >> ~/hourly_gold.log 2>&1
~~~
# 4.2 Installation Steps
~~~
# 1. Edit crontab
crontab -e

# 2. Add the cron command above
# 3. Save and exit (Ctrl+X, Y, Enter in nano)

# 4. Verify installation
crontab -l

# 5. Create log file
touch ~/hourly_gold.log
~~~
# 4.3 Execution Flow
XX:00:00 - Cron triggers execution

Set environment - Change directory, configure SSH

Sync with GitHub - Fetch latest, reset to clean state

Collect data - Run gold price tracker

Generate visuals - Create updated plots

Version control - Stage, commit, and push data files

Log results - Record execution to log file

# 5.0 Data Storage and Version Control
# 5.1 Files Tracked by Git
The repository tracks only data files, not scripts:

Updates every hour:

`gold_prices.csv`: Primary time-series data

`gold_dump_normalized.sql`: Database export

`plots/*.png` (4 files): Visualization charts

# 5.2 Files Ignored by Git
Script files (`*.sh`)

Log files (`*.log`)

Temporary files

Raw HTML downloads

# 5.3 Data Structure
CSV Format (`gold_prices.csv`):

~~~
timestamp,ask,bid,high,low,change,change_percent,currency
2024-12-24 14:00:00,2050.25,2048.75,2052.10,2045.50,+1.75,+0.085%,USD
~~~
SQL Format (`gold_dump_normalized.sql`):
~~~
CREATE TABLE IF NOT EXISTS gold_prices (...);
INSERT INTO gold_prices VALUES (...);
-- Normalized structure for database import
~~~
# 6.0 Monitoring and Maintenance
# 6.1 Log Files
`hourly_gold.log`: Cron execution output

System logs: `/var/log/syslog` (cron service)

# 6.2 Monitoring Commands
~~~
# Check recent execution
tail -20 ~/hourly_gold.log

# Monitor in real-time
tail -f ~/hourly_gold.log

# Check system cron logs
sudo grep CRON /var/log/syslog | tail -5

# Verify data updates
tail -5 ~/gold_tracker_data/gold_prices.csv

# Check GitHub commits
cd ~/ && git log --oneline -3
~~~
# 6.3 Manual Testing
~~~
# Complete test run
cd ~/ && export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_cron" && git fetch origin && git reset --hard origin/main && bash gold_price_tracker.sh && bash plot_gold_price.sh && git add gold_tracker_data/gold_prices.csv gold_tracker_data/gold_dump_normalized.sql gold_tracker_data/plots/*.png && git commit -m "manual test" && git push origin main

# Individual component testing
bash gold_price_tracker.sh
bash plot_gold_price.sh
~~~
# 7.0 Troubleshooting Guide
# 7.1 Common Issues and Solutions
1) SSH Authentication
   Problem: Git push asks for username

   Solution: `export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_cron"`
2) Permission denied
   Problem: Script won't execute

   Solution: `chmod +x ~/*.sh`
3) Cron Not Running
   Problem: No log updates

   Solution: Check `sudo systemctl status cron`
4) Git Push Rejected
   Problem: "non-fast-forward" error

   Solution: Include `git fetch && git reset --hard origin/main`
5) Missing Gnuplot
   Problem: Plot script fails
   
   Solution: `sudo apt install gnuplot`
7) No Output in Log
   Problem: Empty `hourly_gold.log`

   Solution: Check cron command syntax and redirects
# 7.2 Diagnostic Commands
~~~
# Test SSH connection
ssh -i ~/.ssh/id_ed25519_cron -T git@github.com

# Verify Git remote URL
git remote -v
# Should show: origin  git@github.com:<user>/<git repo>

# Check script permissions
ls -la ~/*.sh

# Test individual components
cd ~/
bash gold_price_tracker.sh
ls -la gold_tracker_data/
~~~
7.3 Reset Procedures
~~~
# Complete system reset
cd ~/
rm -rf gold_tracker_data/hourly_gold.log
git fetch origin
git reset --hard origin/main
mkdir -p gold_tracker_data/plots

# Reinstall cron job
crontab -r
echo '0 * * * * cd ~/ && export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_cron" && git fetch origin && git reset --hard origin/main && bash gold_price_tracker.sh && bash plot_gold_price.sh && git add gold_tracker_data/gold_prices.csv gold_tracker_data/gold_dump_normalized.sql gold_tracker_data/plots/*.png && git commit -m "hourly gold update" && git push origin main >> ~/hourly_gold.log 2>&1' | crontab -
~~~
# 8.0 Advanced Configuration
# 8.1 Custom Schedule
Modify the cron time expression:

Every hour at :00: `0 * * * *`

Every 30 minutes: `*/30 * * * *`

Daily at 9 AM: `0 9 * * *`

Weekdays hourly: `0 * * * 1-5`

# 8.2 Enhanced Logging
Add detailed logging to script:

~~~
#!/bin/bash
# Add to gold_price_tracker.sh
LOG_FILE="~/gold_tracker_data/script.log"
echo "[$(date)] Starting gold price collection" >> $LOG_FILE
# ... script content ...
echo "[$(date)] Collection complete" >> $LOG_FILE
~~~
# 8.3 Error Notification
Add error alerts via email (requires MTA):

~~~
# Modify cron command
0 * * * * cd ~/ && ... 2>&1 | mail -s "Gold Tracker Alert" your@email.com
~~~
# 9.0 System Architecture
# 9.1 Data Flow
~~~
[Kitco/Financial Source] 
        ↓
[gold_price_tracker.sh] → CSV + SQL Files
        ↓
[plot_gold_price.sh] → PNG Charts
        ↓
[Git Operations] → GitHub Repository
        ↓
[hourly_gold.log] ← Execution Logging
~~~
# 9.2 Design Principles
Simplicity: Single cron line, no unnecessary dependencies

Reliability: Git reset ensures clean state before each run

Version Control: All data changes tracked in GitHub

Automation: Fully hands-off operation after setup

Portability: Uses standard Unix tools (bash, git, gnuplot)

# 9.3 Security Considerations
SSH key has no passphrase (for automation only)

Key stored in user directory with proper permissions

Repository contains only data, no sensitive information

Log files contain execution details only

# 10.0 Maintenance Schedule
1) Check log file size (Weekly)
   `du -h ~/hourly_gold.log`
2) Verify GitHub commits (Daily)
   `git log --oneline --since="1 day ago"`
3) Test manual execution (Monthly)
   Run manual test command
5) Update SSH key	Yearly
   Regenerate and update GitHub
# 11.0 Support and References
# 11.1 Useful Commands Quick Reference
~~~
# Status check
crontab -l                            # View cron jobs
tail -f hourly_gold.log               # Live monitoring
git log --oneline -5                  # Recent commits

# Manual operations
cd ~/ && export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_cron" && git push origin main  # Manual push

# System checks
sudo systemctl status cron           # Cron service status
ssh -i ~/.ssh/id_ed25519_cron -T git@github.com  # SSH test
~~~
# 11.2 Contact and Support
For issues with this specific implementation:

Check `hourly_gold.log` for errors

Verify SSH key in GitHub settings

Test scripts manually

Review cron syntax
