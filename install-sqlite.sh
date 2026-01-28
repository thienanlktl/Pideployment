#!/bin/bash
# Script to install SQLite on Linux systems and initialize database
# Supports Ubuntu/Debian, CentOS/RHEL, and Arch Linux
# Creates the database and table structure matching iot_pubsub_gui.py

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${SCRIPT_DIR}/iot_messages.db"

echo "=========================================="
echo "SQLite Installation and Database Setup"
echo "=========================================="
echo "Script directory: $SCRIPT_DIR"
echo "Database path: $DB_PATH"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    echo "ERROR: Cannot detect OS. This script supports Ubuntu/Debian, CentOS/RHEL, and Arch Linux."
    exit 1
fi

echo "Detected OS: $OS"
echo "OS Version: $OS_VERSION"
echo ""

# Check if SQLite is already installed
SQLITE_INSTALLED=false
if command -v sqlite3 &> /dev/null; then
    SQLITE_VERSION=$(sqlite3 --version | awk '{print $1}')
    echo "SQLite is already installed: version $SQLITE_VERSION"
    SQLITE_INSTALLED=true
    
    echo "Checking if Python sqlite3 module is available..."
    # Check Python sqlite3 module
    if python3 -c "import sqlite3" 2>/dev/null; then
        echo "✓ Python sqlite3 module is available"
    else
        echo "WARNING: SQLite command-line tool is installed but Python sqlite3 module is not available"
        echo "This is unusual - Python should have sqlite3 built-in"
    fi
    echo ""
    echo "SQLite is installed. Proceeding to database initialization..."
else
    echo "SQLite is not installed. Installing now..."
    echo ""
fi

# Install SQLite based on OS (only if not already installed)
if [ "$SQLITE_INSTALLED" = false ]; then
    case $OS in
        ubuntu|debian)
            echo "Installing SQLite on Ubuntu/Debian..."
            sudo apt-get update
            sudo apt-get install -y sqlite3 libsqlite3-dev
            ;;
        centos|rhel|fedora|rocky|almalinux)
            echo "Installing SQLite on CentOS/RHEL/Fedora..."
            if command -v dnf &> /dev/null; then
                sudo dnf install -y sqlite sqlite-devel
            else
                sudo yum install -y sqlite sqlite-devel
            fi
            ;;
        arch|manjaro)
            echo "Installing SQLite on Arch Linux..."
            sudo pacman -S --noconfirm sqlite
            ;;
        *)
            echo "ERROR: Unsupported OS: $OS"
            echo "Please install SQLite manually for your OS."
            exit 1
            ;;
    esac
fi

# Verify installation
echo ""
echo "Verifying SQLite installation..."
if command -v sqlite3 &> /dev/null; then
    SQLITE_VERSION=$(sqlite3 --version | awk '{print $1}')
    echo "✓ SQLite command-line tool installed: version $SQLITE_VERSION"
else
    echo "ERROR: SQLite installation failed"
    exit 1
fi

# Verify Python sqlite3 module
echo "Verifying Python sqlite3 module..."
if python3 -c "import sqlite3; print('SQLite version:', sqlite3.sqlite_version)" 2>/dev/null; then
    PYTHON_SQLITE_VERSION=$(python3 -c "import sqlite3; print(sqlite3.sqlite_version)" 2>/dev/null)
    echo "✓ Python sqlite3 module is available: version $PYTHON_SQLITE_VERSION"
else
    echo "WARNING: Python sqlite3 module check failed"
    echo "This is unusual - Python should have sqlite3 built-in"
    echo "You may need to reinstall Python or install python3-dev package"
fi

echo ""
echo "=========================================="
echo "Initializing Database and Creating Table"
echo "=========================================="

# Initialize database and create table
if [ -f "$DB_PATH" ]; then
    echo "Database file already exists: $DB_PATH"
    echo "Checking if table structure is correct..."
    
    # Check if messages table exists
    if sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='messages';" | grep -q "messages"; then
        echo "✓ Messages table already exists"
        
        # Verify table structure
        TABLE_INFO=$(sqlite3 "$DB_PATH" "PRAGMA table_info(messages);")
        if echo "$TABLE_INFO" | grep -q "timestamp.*TEXT.*NOT NULL"; then
            echo "✓ Table structure is correct"
        else
            echo "WARNING: Table structure may not match expected schema"
            echo "Recreating table to ensure correct structure..."
            sqlite3 "$DB_PATH" <<EOF
DROP TABLE IF EXISTS messages;
CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    topic TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_topic ON messages(topic);
EOF
            echo "✓ Table recreated with correct structure"
        fi
    else
        echo "Messages table not found. Creating table..."
        sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    topic TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_topic ON messages(topic);
EOF
        echo "✓ Messages table created"
    fi
else
    echo "Creating new database: $DB_PATH"
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    topic TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_timestamp ON messages(timestamp);
CREATE INDEX idx_topic ON messages(topic);
EOF
    echo "✓ Database created successfully"
    echo "✓ Messages table created with correct structure"
    echo "✓ Indexes created on timestamp and topic columns"
fi

# Verify database structure
echo ""
echo "Verifying database structure..."
TABLE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='messages';")
if [ "$TABLE_COUNT" -eq 1 ]; then
    echo "✓ Messages table verified"
    
    # Check columns
    COLUMN_COUNT=$(sqlite3 "$DB_PATH" "PRAGMA table_info(messages);" | wc -l)
    if [ "$COLUMN_COUNT" -eq 5 ]; then
        echo "✓ Table has correct number of columns (5)"
    fi
    
    # Check indexes
    INDEX_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='messages';")
    if [ "$INDEX_COUNT" -ge 2 ]; then
        echo "✓ Indexes verified ($INDEX_COUNT indexes found)"
    fi
fi

# Display table structure
echo ""
echo "Database table structure:"
sqlite3 "$DB_PATH" ".schema messages"
echo ""
echo "Indexes:"
sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='messages';"

echo ""
echo "=========================================="
echo "SQLite installation and database setup completed!"
echo "=========================================="
echo ""
echo "SQLite command-line tool: $(which sqlite3)"
echo "SQLite version: $(sqlite3 --version)"
echo "Database location: $DB_PATH"
echo ""
echo "Database is ready to store MQTT messages from iot_pubsub_gui.py"
echo "The sqlite3 module is built into Python, so no additional"
echo "Python packages are required."

