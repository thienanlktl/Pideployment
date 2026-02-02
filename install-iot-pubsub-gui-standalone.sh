#!/bin/bash
# ============================================================================
# IoT PubSub GUI - Standalone One-File Installer
# ============================================================================
# This is a self-contained installer that packages all application files
# Usage: bash install-iot-pubsub-gui-standalone.sh
#
# What it does:
# - Updates system packages
# - Installs required system dependencies
# - Extracts all application files from this script
# - Creates virtual environment
# - Installs Python dependencies
# - Creates desktop launcher
#
# No git or SSH keys required!
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/iot-pubsub-gui"

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_step() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    print_error "This script is designed for Linux/Raspberry Pi OS"
    exit 1
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "Please do not run this script as root. It will ask for sudo when needed."
    exit 1
fi

print_step "IoT PubSub GUI - Standalone Installer"
print_info "This installer packages all files - no git required!"
print_info "Installation directory: $INSTALL_DIR"
echo ""

# ============================================================================
# Step 1: Update system packages
# ============================================================================
print_step "Step 1: Updating System Packages"

print_info "Updating package list (this may take a few minutes)..."

if sudo apt-get update; then
    print_success "Package list updated"
else
    print_error "Failed to update package list"
    exit 1
fi

print_info "Upgrading system packages (this may take several minutes)..."

if sudo apt-get upgrade -y; then
    print_success "System packages upgraded"
else
    print_warning "Some packages may have failed to upgrade. Continuing..."
fi

# ============================================================================
# Step 2: Install system dependencies
# ============================================================================
print_step "Step 2: Installing System Dependencies"

print_info "Installing required system packages..."

SYSTEM_PACKAGES=(
    "python3"
    "python3-pip"
    "python3-venv"
    "python3-dev"
    "build-essential"
    "libxcb-xinerama0"
    "libxkbcommon-x11-0"
    "libqt6gui6"
    "libqt6widgets6"
    "libqt6core6"
    "libgl1-mesa-glx"
    "libglib2.0-0"
    "sqlite3"
    "libsqlite3-dev"
)

MISSING_PACKAGES=()
for package in "${SYSTEM_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    print_info "Installing missing packages: ${MISSING_PACKAGES[*]}"
    if sudo apt-get install -y "${MISSING_PACKAGES[@]}"; then
        print_success "System packages installed"
    else
        print_error "Failed to install some system packages"
        exit 1
    fi
else
    print_success "All required system packages are already installed"
fi

# ============================================================================
# Step 3: Create installation directory and extract files
# ============================================================================
print_step "Step 3: Extracting Application Files"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

print_info "Extracting application files to $INSTALL_DIR..."

# Extract iot_pubsub_gui.py
cat > "$INSTALL_DIR/iot_pubsub_gui.py" << 'IOT_PUBSUB_GUI_EOF'
"""
AWS IoT Pub/Sub GUI Application using PyQt6 and AWS IoT Device SDK v2

Installation:
    pip install PyQt6 awsiotsdk

Run:
    python iot_pubsub_gui.py

Test:
    Use AWS IoT Core MQTT test client to publish to your subscribed topics
    and see messages appear in the app log in real-time.
"""

import sys
import json
import traceback
import os
import sqlite3
import subprocess
import logging
import threading
from pathlib import Path
from datetime import datetime
from typing import Optional

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QTextEdit, QPushButton, QGroupBox, QMessageBox,
    QDialog, QTableWidget, QTableWidgetItem, QHeaderView
)
from PyQt6.QtCore import Qt, QObject, pyqtSignal, QMetaObject, Q_ARG, QThread
from PyQt6.QtGui import QTextCursor, QColor

from awscrt import mqtt
from awsiot import mqtt_connection_builder

# Try to import requests for update check
try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

# Version information
__version__ = "1.0.0"
VERSION_FILE = Path(__file__).parent / "VERSION"

# Try to read version from VERSION file if it exists
if VERSION_FILE.exists():
    try:
        with open(VERSION_FILE, 'r') as f:
            version_from_file = f.read().strip()
            if version_from_file:
                __version__ = version_from_file
    except Exception:
        pass

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(Path(__file__).parent / "iot_pubsub_gui.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class MessageReceiver(QObject):
    """Signal emitter for thread-safe GUI updates from MQTT callbacks"""
    message_received = pyqtSignal(str, str, str)  # timestamp, topic, payload


class UpdateChecker(QObject):
    """Signal emitter for update check results"""
    update_available = pyqtSignal(str, str)  # latest_sha, local_sha
    check_complete = pyqtSignal(bool)  # success


class AWSIoTPubSubGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        
        # Get the directory where this script is located
        script_dir = Path(__file__).parent.absolute()
        
        # AWS IoT Configuration
        self.endpoint = "a1qvvs16o26pnz-ats.iot.ap-southeast-2.amazonaws.com"
        self.thing_name = "feasibility_demo"
        self.client_id = "feasibility_demo"
        
        # Certificate paths relative to the script directory (PublishDemo folder)
        self.ca_path = str(script_dir / "AmazonRootCA1.pem")
        self.cert_path = str(script_dir / "ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt")
        self.key_path = str(script_dir / "ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key")
        
        # MQTT Connection
        self.mqtt_connection = None
        self.is_connected = False
        self.subscribed_topics = set()
        
        # Message receiver for thread-safe updates
        self.message_receiver = MessageReceiver()
        self.message_receiver.message_received.connect(self.on_message_received)
        
        # SQLite Database
        self.db_path = str(script_dir / "iot_messages.db")
        
        # Update check
        self.update_checker = UpdateChecker()
        self.update_checker.update_available.connect(self.on_update_available)
        self.update_checker.check_complete.connect(self.on_update_check_complete)
        self.latest_remote_sha = None
        self.local_sha = None
        self.script_dir = script_dir
        
        self.init_ui()
        self.init_database()  # Initialize database after UI so log_text exists
        self.update_status("Disconnected", False)
        
        # Start update check in background after UI is ready
        QMetaObject.invokeMethod(self, "start_update_check", Qt.ConnectionType.QueuedConnection)
    
    def init_ui(self):
        """Initialize the user interface"""
        self.setWindowTitle("AWS IoT Pub/Sub GUI - Feasibility Demo")
        self.setGeometry(100, 100, 900, 800)
        
        # Central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setSpacing(10)
        main_layout.setContentsMargins(15, 15, 15, 15)
        
        # Top bar with version and update status
        top_bar_layout = QHBoxLayout()
        
        # Version label (left side)
        self.version_label = QLabel(f"Version: {__version__}")
        self.version_label.setStyleSheet("font-size: 10pt; color: gray; padding: 5px;")
        top_bar_layout.addWidget(self.version_label)
        
        top_bar_layout.addStretch()
        
        # Update notification (right side, initially hidden)
        self.update_notification_layout = QHBoxLayout()
        self.update_notification_label = QLabel("New update available!")
        self.update_notification_label.setStyleSheet("font-size: 10pt; color: orange; padding: 5px;")
        self.update_notification_label.setVisible(False)
        self.update_notification_layout.addWidget(self.update_notification_label)
        
        self.update_now_btn = QPushButton("Update Now")
        self.update_now_btn.setStyleSheet("font-size: 10pt; padding: 5px; background-color: #4CAF50; color: white;")
        self.update_now_btn.clicked.connect(self.perform_update)
        self.update_now_btn.setVisible(False)
        self.update_notification_layout.addWidget(self.update_now_btn)
        
        top_bar_layout.addLayout(self.update_notification_layout)
        main_layout.addLayout(top_bar_layout)
        
        # Status of update label (red) - keep for backward compatibility, but hide it
        self.update_status_label = QLabel("")
        self.update_status_label.setVisible(False)
        main_layout.addWidget(self.update_status_label)
        
        # Status label
        self.status_label = QLabel("Disconnected")
        self.status_label.setStyleSheet("font-size: 12pt; font-weight: bold; padding: 5px;")
        main_layout.addWidget(self.status_label)
        
        # Connection button
        self.connect_btn = QPushButton("Connect to AWS IoT")
        self.connect_btn.clicked.connect(self.toggle_connection)
        self.connect_btn.setStyleSheet("font-size: 11pt; padding: 8px;")
        main_layout.addWidget(self.connect_btn)
        
        # Publish Group
        publish_group = QGroupBox("Publish Message")
        publish_layout = QVBoxLayout()
        
        # Publish Topic
        publish_topic_layout = QHBoxLayout()
        publish_topic_layout.addWidget(QLabel("Topic:"))
        self.publish_topic_edit = QLineEdit("devices/feasibility_demo/commands")
        publish_topic_layout.addWidget(self.publish_topic_edit)
        publish_layout.addLayout(publish_topic_layout)
        
        # Publish Payload
        publish_layout.addWidget(QLabel("JSON Payload:"))
        self.publish_payload_edit = QTextEdit()
        default_payload = {
            "action": "start_test",
            "timestamp": "2026-01-19T17:00:00Z",
            "parameters": {
                "duration": 60,
                "mode": "demo"
            }
        }
        self.publish_payload_edit.setPlainText(json.dumps(default_payload, indent=2))
        self.publish_payload_edit.setMinimumHeight(120)
        publish_layout.addWidget(self.publish_payload_edit)
        
        # Publish buttons
        publish_btn_layout = QHBoxLayout()
        self.publish_btn = QPushButton("Publish Message")
        self.publish_btn.clicked.connect(self.publish_message)
        self.publish_btn.setEnabled(False)
        publish_btn_layout.addWidget(self.publish_btn)
        
        self.publish_shadow_btn = QPushButton("Publish Shadow Update")
        self.publish_shadow_btn.clicked.connect(self.publish_shadow_update)
        self.publish_shadow_btn.setEnabled(False)
        publish_btn_layout.addWidget(self.publish_shadow_btn)
        publish_layout.addLayout(publish_btn_layout)
        
        publish_group.setLayout(publish_layout)
        main_layout.addWidget(publish_group)
        
        # Subscribe Group
        subscribe_group = QGroupBox("Subscribe to Topics")
        subscribe_layout = QVBoxLayout()
        
        # Subscribe Topic
        subscribe_topic_layout = QHBoxLayout()
        subscribe_topic_layout.addWidget(QLabel("Topic Filter:"))
        self.subscribe_topic_edit = QLineEdit("devices/feasibility_demo/#")
        subscribe_topic_layout.addWidget(self.subscribe_topic_edit)
        subscribe_layout.addLayout(subscribe_topic_layout)
        
        # Subscribe buttons
        subscribe_btn_layout = QHBoxLayout()
        self.subscribe_btn = QPushButton("Subscribe")
        self.subscribe_btn.clicked.connect(self.subscribe_topic)
        self.subscribe_btn.setEnabled(False)
        subscribe_btn_layout.addWidget(self.subscribe_btn)
        
        self.unsubscribe_btn = QPushButton("Unsubscribe")
        self.unsubscribe_btn.clicked.connect(self.unsubscribe_topic)
        self.unsubscribe_btn.setEnabled(False)
        subscribe_btn_layout.addWidget(self.unsubscribe_btn)
        subscribe_btn_layout.addStretch()
        subscribe_layout.addLayout(subscribe_btn_layout)
        
        subscribe_group.setLayout(subscribe_layout)
        main_layout.addWidget(subscribe_group)
        
        # Log Area
        log_group = QGroupBox("Message Log")
        log_layout = QVBoxLayout()
        
        # Log buttons layout
        log_btn_layout = QHBoxLayout()
        self.view_logs_btn = QPushButton("View All Messages in Database")
        self.view_logs_btn.clicked.connect(self.show_all_messages)
        self.view_logs_btn.setStyleSheet("font-size: 10pt; padding: 5px;")
        log_btn_layout.addWidget(self.view_logs_btn)
        log_btn_layout.addStretch()
        log_layout.addLayout(log_btn_layout)
        
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setMinimumHeight(250)
        self.log_text.setStyleSheet("font-family: 'Courier New', monospace; font-size: 9pt;")
        log_layout.addWidget(self.log_text)
        log_group.setLayout(log_layout)
        main_layout.addWidget(log_group)
        
        # Add initial log message
        self.add_log("Application started. Click 'Connect to AWS IoT' to begin.")
    
    def update_status(self, message: str, is_success: bool = True):
        """Update the status label with color coding"""
        self.status_label.setText(message)
        if is_success:
            if "Connected" in message or "Success" in message or "Received" in message:
                self.status_label.setStyleSheet(
                    "font-size: 12pt; font-weight: bold; padding: 5px; color: green;"
                )
            else:
                self.status_label.setStyleSheet(
                    "font-size: 12pt; font-weight: bold; padding: 5px; color: blue;"
                )
        else:
            self.status_label.setStyleSheet(
                "font-size: 12pt; font-weight: bold; padding: 5px; color: red;"
            )
    
    def add_log(self, message: str):
        """Add a message to the log area with timestamp"""
        # Check if log_text exists (may not be initialized yet)
        if not hasattr(self, 'log_text') or self.log_text is None:
            return
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {message}\n"
        self.log_text.moveCursor(QTextCursor.MoveOperation.End)
        self.log_text.insertPlainText(log_entry)
        self.log_text.moveCursor(QTextCursor.MoveOperation.End)
    
    def toggle_connection(self):
        """Connect or disconnect from AWS IoT"""
        if not self.is_connected:
            self.connect_to_iot()
        else:
            self.disconnect_from_iot()
    
    def connect_to_iot(self):
        """Establish MQTT connection to AWS IoT Core"""
        try:
            self.update_status("Connecting...", True)
            self.add_log("=" * 60)
            self.add_log("Attempting to connect to AWS IoT Core...")
            self.add_log(f"Endpoint: {self.endpoint}")
            self.add_log(f"Client ID: {self.client_id}")
            self.add_log(f"Thing Name: {self.thing_name}")
            self.connect_btn.setEnabled(False)
            
            # Step 1: Verify certificate files exist
            self.add_log("Step 1: Verifying certificate files...")
            cert_files = {
                "CA Root": self.ca_path,
                "Certificate": self.cert_path,
                "Private Key": self.key_path
            }
            
            missing_files = []
            for name, path in cert_files.items():
                if os.path.exists(path):
                    file_size = os.path.getsize(path)
                    self.add_log(f"  âœ“ {name}: {path} (Size: {file_size} bytes)")
                else:
                    missing_files.append(f"{name}: {path}")
                    self.add_log(f"  âœ— {name}: NOT FOUND - {path}")
            
            if missing_files:
                error_msg = f"Certificate files not found:\n" + "\n".join(missing_files)
                self.update_status("Connection Failed: Missing Files", False)
                self.add_log(f"ERROR: {error_msg}")
                self.connect_btn.setEnabled(True)
                QMessageBox.critical(self, "Connection Error", error_msg)
                return
            
            # Step 2: Build MQTT connection
            self.add_log("Step 2: Building MQTT connection with mTLS...")
            try:
                self.mqtt_connection = mqtt_connection_builder.mtls_from_path(
                    endpoint=self.endpoint,
                    cert_filepath=self.cert_path,
                    pri_key_filepath=self.key_path,
                    ca_filepath=self.ca_path,
                    client_id=self.client_id,
                    clean_session=False,
                    keep_alive_secs=30
                )
                self.add_log("  âœ“ MQTT connection object created successfully")
            except Exception as e:
                error_msg = f"Failed to create MQTT connection object: {str(e)}"
                self.add_log(f"ERROR: {error_msg}")
                self.add_log(f"Exception type: {type(e).__name__}")
                self.add_log(f"Traceback:\n{''.join(traceback.format_tb(e.__traceback__))}")
                self.update_status("Connection Failed: Build Error", False)
                self.connect_btn.setEnabled(True)
                QMessageBox.critical(self, "Connection Error", error_msg)
                return
            
            # Step 3: Establish connection
            self.add_log("Step 3: Establishing connection to AWS IoT Core...")
            try:
                connect_future = self.mqtt_connection.connect()
                self.add_log("  â†’ Waiting for connection (timeout: 10 seconds)...")
                connect_future.result(timeout=10)
                self.add_log("  âœ“ Connection established successfully!")
            except Exception as e:
                error_msg = f"Connection timeout or failed: {str(e)}"
                self.add_log(f"ERROR: {error_msg}")
                self.add_log(f"Exception type: {type(e).__name__}")
                self.add_log(f"Full traceback:\n{''.join(traceback.format_tb(e.__traceback__))}")
                
                # Additional diagnostics
                self.add_log("\nDiagnostics:")
                self.add_log(f"  - Check if endpoint is correct: {self.endpoint}")
                self.add_log(f"  - Check if certificate policy allows iot:Connect")
                self.add_log(f"  - Check if client ID is unique and not already in use")
                self.add_log(f"  - Check network connectivity to AWS IoT endpoint")
                
                self.update_status("Connection Failed", False)
                self.connect_btn.setEnabled(True)
                QMessageBox.critical(self, "Connection Error", 
                    f"{error_msg}\n\nCheck the log for detailed diagnostics.")
                self.mqtt_connection = None
                return
            
            # Success
            self.is_connected = True
            self.update_status("Connected!", True)
            self.add_log("=" * 60)
            self.add_log(f"âœ“ Successfully connected to AWS IoT Core!")
            self.add_log(f"  Endpoint: {self.endpoint}")
            self.add_log(f"  Client ID: {self.client_id}")
            self.add_log("=" * 60)
            
            # Enable buttons
            self.publish_btn.setEnabled(True)
            self.publish_shadow_btn.setEnabled(True)
            self.subscribe_btn.setEnabled(True)
            self.unsubscribe_btn.setEnabled(True)
            self.connect_btn.setText("Disconnect from AWS IoT")
            self.connect_btn.setEnabled(True)
            
        except FileNotFoundError as e:
            error_msg = f"Certificate file not found: {str(e)}"
            self.add_log(f"ERROR: {error_msg}")
            self.add_log(f"Exception type: {type(e).__name__}")
            self.add_log(f"Traceback:\n{''.join(traceback.format_tb(e.__traceback__))}")
            self.update_status("Connection Failed: File Not Found", False)
            self.connect_btn.setEnabled(True)
            QMessageBox.critical(self, "Connection Error", error_msg)
            self.mqtt_connection = None
        except Exception as e:
            error_msg = f"Unexpected error during connection: {str(e)}"
            self.add_log(f"ERROR: {error_msg}")
            self.add_log(f"Exception type: {type(e).__name__}")
            self.add_log(f"Full traceback:\n{''.join(traceback.format_exception(type(e), e, e.__traceback__))}")
            self.update_status("Connection Failed: Unexpected Error", False)
            self.connect_btn.setEnabled(True)
            QMessageBox.critical(self, "Connection Error", 
                f"{error_msg}\n\nCheck the log for full details.")
            self.mqtt_connection = None
    
    def disconnect_from_iot(self):
        """Disconnect from AWS IoT Core"""
        try:
            if self.mqtt_connection:
                # Unsubscribe from all topics first
                for topic in list(self.subscribed_topics):
                    try:
                        # Unsubscribe (returns tuple: (future, packet_id))
                        unsubscribe_future, packet_id = self.mqtt_connection.unsubscribe(topic)
                        unsubscribe_future.result(timeout=5)
                        self.add_log(f"Unsubscribed from: {topic}")
                    except Exception as e:
                        self.add_log(f"Error unsubscribing from {topic}: {e}")
                
                self.subscribed_topics.clear()
                
                # Disconnect
                disconnect_future = self.mqtt_connection.disconnect()
                disconnect_future.result(timeout=5)
                
                self.mqtt_connection = None
                self.is_connected = False
                self.update_status("Disconnected", False)
                self.add_log("Disconnected from AWS IoT Core")
                
                # Disable buttons
                self.publish_btn.setEnabled(False)
                self.publish_shadow_btn.setEnabled(False)
                self.subscribe_btn.setEnabled(False)
                self.unsubscribe_btn.setEnabled(False)
                self.connect_btn.setText("Connect to AWS IoT")
                self.connect_btn.setEnabled(True)
        except Exception as e:
            error_msg = f"Disconnect error: {str(e)}"
            self.add_log(f"ERROR: {error_msg}")
            self.mqtt_connection = None
            self.is_connected = False
            self.update_status("Disconnected (with errors)", False)
    
    def publish_message(self):
        """Publish a message to the specified topic"""
        if not self.is_connected or not self.mqtt_connection:
            QMessageBox.warning(self, "Not Connected", "Please connect to AWS IoT first.")
            return
        
        topic = self.publish_topic_edit.text().strip()
        payload_text = self.publish_payload_edit.toPlainText().strip()
        
        if not topic:
            QMessageBox.warning(self, "Invalid Topic", "Please enter a topic.")
            return
        
        if not payload_text:
            QMessageBox.warning(self, "Invalid Payload", "Please enter a JSON payload.")
            return
        
        try:
            # Validate JSON
            payload_dict = json.loads(payload_text)
            payload_json = json.dumps(payload_dict)
            
            # Publish (returns tuple: (future, packet_id))
            publish_future, packet_id = self.mqtt_connection.publish(
                topic=topic,
                payload=payload_json,
                qos=mqtt.QoS.AT_LEAST_ONCE
            )
            publish_future.result(timeout=5)
            
            self.update_status("Publish Success", True)
            self.add_log(f"Published to '{topic}': {payload_json}")
            
        except json.JSONDecodeError as e:
            error_msg = f"Invalid JSON: {str(e)}"
            self.update_status(error_msg, False)
            self.add_log(f"ERROR: {error_msg}")
            QMessageBox.warning(self, "Invalid JSON", error_msg)
        except Exception as e:
            error_msg = f"Publish failed: {str(e)}"
            self.update_status(error_msg, False)
            self.add_log(f"ERROR: {error_msg}")
            QMessageBox.critical(self, "Publish Error", error_msg)
    
    def publish_shadow_update(self):
        """Publish a shadow update to the device shadow"""
        if not self.is_connected or not self.mqtt_connection:
            QMessageBox.warning(self, "Not Connected", "Please connect to AWS IoT first.")
            return
        
        shadow_topic = f"$aws/things/{self.thing_name}/shadow/update"
        default_payload = {
            "state": {
                "desired": {
                    "status": "active",
                    "mode": "demo",
                    "brightness": 80
                }
            }
        }
        
        try:
            payload_json = json.dumps(default_payload)
            
            # Publish (returns tuple: (future, packet_id))
            publish_future, packet_id = self.mqtt_connection.publish(
                topic=shadow_topic,
                payload=payload_json,
                qos=mqtt.QoS.AT_LEAST_ONCE
            )
            publish_future.result(timeout=5)
            
            self.update_status("Shadow Update Published", True)
            self.add_log(f"Published shadow update to '{shadow_topic}': {payload_json}")
            
        except Exception as e:
            error_msg = f"Shadow update failed: {str(e)}"
            self.update_status(error_msg, False)
            self.add_log(f"ERROR: {error_msg}")
            QMessageBox.critical(self, "Shadow Update Error", error_msg)
    
    def subscribe_topic(self):
        """Subscribe to the specified topic filter"""
        if not self.is_connected or not self.mqtt_connection:
            QMessageBox.warning(self, "Not Connected", "Please connect to AWS IoT first.")
            return
        
        topic_filter = self.subscribe_topic_edit.text().strip()
        
        if not topic_filter:
            QMessageBox.warning(self, "Invalid Topic", "Please enter a topic filter.")
            return
        
        if topic_filter in self.subscribed_topics:
            QMessageBox.information(self, "Already Subscribed", f"Already subscribed to: {topic_filter}")
            return
        
        try:
            # Define callback function for received messages
            def on_message_received(topic, payload, **kwargs):
                """Callback function called when a message is received"""
                try:
                    payload_str = payload.decode('utf-8')
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    # Use signal to safely update GUI from callback thread
                    self.message_receiver.message_received.emit(timestamp, topic, payload_str)
                except Exception as e:
                    # If signal fails, try direct invoke (fallback)
                    QMetaObject.invokeMethod(
                        self,
                        "on_message_received",
                        Qt.ConnectionType.QueuedConnection,
                        Q_ARG(str, datetime.now().strftime("%Y-%m-%d %H:%M:%S")),
                        Q_ARG(str, topic),
                        Q_ARG(str, f"Error decoding payload: {e}")
                    )
            
            # Subscribe
            subscribe_future, packet_id = self.mqtt_connection.subscribe(
                topic=topic_filter,
                qos=mqtt.QoS.AT_LEAST_ONCE,
                callback=on_message_received
            )
            subscribe_future.result(timeout=5)
            
            self.subscribed_topics.add(topic_filter)
            self.update_status(f"Subscribed to: {topic_filter}", True)
            self.add_log(f"Subscribed to topic filter: {topic_filter}")
            
        except Exception as e:
            error_msg = f"Subscribe failed: {str(e)}"
            self.update_status(error_msg, False)
            self.add_log(f"ERROR: {error_msg}")
            QMessageBox.critical(self, "Subscribe Error", error_msg)
    
    def unsubscribe_topic(self):
        """Unsubscribe from the specified topic filter"""
        if not self.is_connected or not self.mqtt_connection:
            QMessageBox.warning(self, "Not Connected", "Please connect to AWS IoT first.")
            return
        
        topic_filter = self.subscribe_topic_edit.text().strip()
        
        if not topic_filter:
            QMessageBox.warning(self, "Invalid Topic", "Please enter a topic filter.")
            return
        
        if topic_filter not in self.subscribed_topics:
            QMessageBox.information(self, "Not Subscribed", f"Not subscribed to: {topic_filter}")
            return
        
        try:
            # Unsubscribe (returns tuple: (future, packet_id))
            unsubscribe_future, packet_id = self.mqtt_connection.unsubscribe(topic_filter)
            unsubscribe_future.result(timeout=5)
            
            self.subscribed_topics.discard(topic_filter)
            self.update_status(f"Unsubscribed from: {topic_filter}", True)
            self.add_log(f"Unsubscribed from topic filter: {topic_filter}")
            
        except Exception as e:
            error_msg = f"Unsubscribe failed: {str(e)}"
            self.update_status(error_msg, False)
            self.add_log(f"ERROR: {error_msg}")
            QMessageBox.critical(self, "Unsubscribe Error", error_msg)
    
    def init_database(self):
        """Initialize SQLite database and create table if it doesn't exist"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Create messages table if it doesn't exist
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    topic TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            
            # Create index on timestamp for faster queries
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp)
            ''')
            
            # Create index on topic for faster queries
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_topic ON messages(topic)
            ''')
            
            conn.commit()
            conn.close()
            self.add_log(f"SQLite database initialized: {self.db_path}")
        except Exception as e:
            self.add_log(f"Error initializing database: {e}")
    
    def insert_message_to_db(self, timestamp: str, topic: str, payload: str):
        """Insert received message into SQLite database"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO messages (timestamp, topic, payload)
                VALUES (?, ?, ?)
            ''', (timestamp, topic, payload))
            
            conn.commit()
            conn.close()
        except Exception as e:
            self.add_log(f"Error inserting message to database: {e}")
    
    def on_message_received(self, timestamp: str, topic: str, payload: str):
        """Handle received message (called from signal, thread-safe)"""
        try:
            # Insert message into SQLite database
            self.insert_message_to_db(timestamp, topic, payload)
            
            # Try to format JSON if possible
            try:
                payload_dict = json.loads(payload)
                formatted_payload = json.dumps(payload_dict, indent=2)
            except:
                formatted_payload = payload
            
            log_message = f"Received on '{topic}': {formatted_payload}"
            self.add_log(log_message)
            self.update_status("Message Received", True)
            
        except Exception as e:
            self.add_log(f"Error processing received message: {e}")
    
    def show_all_messages(self):
        """Show all messages from SQLite database in a dialog"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Get all messages ordered by timestamp (newest first)
            cursor.execute('''
                SELECT id, timestamp, topic, payload, created_at
                FROM messages
                ORDER BY timestamp DESC
            ''')
            
            rows = cursor.fetchall()
            conn.close()
            
            # Create dialog window
            dialog = QDialog(self)
            dialog.setWindowTitle("All Messages in Database")
            dialog.setGeometry(100, 100, 1400, 700)  # Larger dialog to show more content
            
            layout = QVBoxLayout(dialog)
            
            # Add label with count
            count_label = QLabel(f"Total messages: {len(rows)}")
            count_label.setStyleSheet("font-size: 11pt; font-weight: bold; padding: 5px;")
            layout.addWidget(count_label)
            
            # Create table
            table = QTableWidget()
            table.setColumnCount(5)
            table.setHorizontalHeaderLabels(["ID", "Timestamp", "Topic", "Payload", "Created At"])
            
            # Set table properties
            table.setRowCount(len(rows))
            table.setAlternatingRowColors(True)
            table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
            table.setWordWrap(True)  # Enable word wrapping
            table.horizontalHeader().setStretchLastSection(False)
            
            # Set column resize modes
            table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)  # ID
            table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)  # Timestamp
            table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)  # Topic
            table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)  # Payload - stretch to fill
            table.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)  # Created At
            
            # Set minimum widths for better visibility
            table.setColumnWidth(0, 60)   # ID
            table.setColumnWidth(1, 180)  # Timestamp
            table.setColumnWidth(2, 250)  # Topic
            table.setColumnWidth(3, 600)  # Payload - minimum width
            table.setColumnWidth(4, 180)  # Created At
            
            # Populate table
            for row_idx, row_data in enumerate(rows):
                for col_idx, value in enumerate(row_data):
                    # Format payload if it's JSON
                    if col_idx == 3 and value:  # Payload column
                        try:
                            # Try to parse and format JSON
                            payload_dict = json.loads(str(value))
                            formatted_value = json.dumps(payload_dict, indent=2)
                        except:
                            # Not JSON, use as is
                            formatted_value = str(value)
                    else:
                        formatted_value = str(value)
                    
                    item = QTableWidgetItem(formatted_value)
                    item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)  # Make read-only
                    
                    # Enable text wrapping for payload column
                    if col_idx == 3:  # Payload column
                        item.setTextAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
                    
                    table.setItem(row_idx, col_idx, item)
                
                # Set row height to accommodate wrapped text
                table.setRowHeight(row_idx, 100)  # Initial height, will auto-adjust
            
            # Adjust row heights based on content
            table.resizeRowsToContents()
            
            layout.addWidget(table)
            
            # Add close button
            close_btn = QPushButton("Close")
            close_btn.clicked.connect(dialog.close)
            layout.addWidget(close_btn)
            
            dialog.exec()
            
        except Exception as e:
            error_msg = f"Error retrieving messages from database: {e}"
            self.add_log(error_msg)
            QMessageBox.critical(self, "Database Error", error_msg)
    
    def start_update_check(self):
        """Start update check in background thread"""
        def check_update():
            """Check for updates in background thread"""
            try:
                logger.info("Starting update check...")
                
                # Get local git commit SHA
                local_sha = None
                try:
                    result = subprocess.run(
                        ['git', 'rev-parse', 'HEAD'],
                        cwd=self.script_dir,
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
                    if result.returncode == 0:
                        local_sha = result.stdout.strip()
                        logger.info(f"Local commit SHA: {local_sha[:8]}")
                    else:
                        logger.warning("Could not get local commit SHA (not a git repo or git not available)")
                except Exception as e:
                    logger.warning(f"Error getting local commit SHA: {e}")
                
                # Get remote commit SHA from GitHub API
                remote_sha = None
                if REQUESTS_AVAILABLE:
                    try:
                        api_url = "https://api.github.com/repos/thienanlktl/Pideployment/commits/main"
                        response = requests.get(api_url, timeout=10)
                        if response.status_code == 200:
                            data = response.json()
                            remote_sha = data.get('sha', '').strip()
                            logger.info(f"Remote commit SHA: {remote_sha[:8]}")
                        else:
                            logger.warning(f"GitHub API returned status {response.status_code}")
                    except Exception as e:
                        logger.warning(f"Error checking remote commit: {e}")
                else:
                    logger.warning("requests library not available, cannot check for updates")
                
                # Compare and emit signal
                if local_sha and remote_sha:
                    if local_sha != remote_sha:
                        logger.info("Update available!")
                        self.update_checker.update_available.emit(remote_sha, local_sha)
                    else:
                        logger.info("Application is up to date")
                
                self.update_checker.check_complete.emit(True)
            except Exception as e:
                logger.error(f"Error in update check: {e}")
                self.update_checker.check_complete.emit(False)
        
        # Run in background thread
        thread = threading.Thread(target=check_update, daemon=True)
        thread.start()
    
    def on_update_available(self, remote_sha: str, local_sha: str):
        """Handle update available signal"""
        self.latest_remote_sha = remote_sha
        self.local_sha = local_sha
        logger.info(f"Update available: {remote_sha[:8]} (current: {local_sha[:8]})")
        
        # Show update notification
        self.update_notification_label.setVisible(True)
        self.update_now_btn.setVisible(True)
    
    def on_update_check_complete(self, success: bool):
        """Handle update check completion"""
        if success:
            logger.info("Update check completed")
        else:
            logger.warning("Update check completed with errors")
    
    def perform_update(self):
        """Perform application update"""
        reply = QMessageBox.question(
            self,
            "Confirm Update",
            "This will update the application and restart it.\n\n"
            "Do you want to continue?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )
        
        if reply != QMessageBox.StandardButton.Yes:
            return
        
        try:
            logger.info("Starting application update...")
            self.add_log("=" * 60)
            self.add_log("Starting application update...")
            
            # Disable update button
            self.update_now_btn.setEnabled(False)
            self.update_now_btn.setText("Updating...")
            
            # Update git repository
            self.add_log("Updating code from repository...")
            
            try:
                # Fetch latest changes
                result = subprocess.run(
                    ['git', 'fetch', 'origin'],
                    cwd=self.script_dir,
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                if result.returncode != 0:
                    raise Exception(f"git fetch failed: {result.stderr}")
                
                # Reset to latest main
                result = subprocess.run(
                    ['git', 'reset', '--hard', 'origin/main'],
                    cwd=self.script_dir,
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                if result.returncode != 0:
                    raise Exception(f"git reset failed: {result.stderr}")
                
                self.add_log("Code updated successfully")
            except Exception as e:
                error_msg = f"Failed to update code: {e}"
                logger.error(error_msg)
                self.add_log(f"ERROR: {error_msg}")
                QMessageBox.critical(self, "Update Error", error_msg)
                self.update_now_btn.setEnabled(True)
                self.update_now_btn.setText("Update Now")
                return
            
            # Update Python dependencies
            self.add_log("Updating Python dependencies...")
            
            try:
                # Find venv python
                venv_python = self.script_dir / "venv" / "bin" / "python3"
                if not venv_python.exists():
                    venv_python = sys.executable
                
                result = subprocess.run(
                    [str(venv_python), '-m', 'pip', 'install', '-r', 'requirements.txt', '--upgrade'],
                    cwd=self.script_dir,
                    capture_output=True,
                    text=True,
                    timeout=300
                )
                if result.returncode != 0:
                    logger.warning(f"pip upgrade had warnings: {result.stderr}")
                    self.add_log(f"Warning: {result.stderr}")
                else:
                    self.add_log("Dependencies updated successfully")
            except Exception as e:
                error_msg = f"Failed to update dependencies: {e}"
                logger.warning(error_msg)
                self.add_log(f"WARNING: {error_msg}")
                # Continue anyway
            
            # Restart application
            self.add_log("Restarting application...")
            self.add_log("=" * 60)
            
            QMessageBox.information(
                self,
                "Update Complete",
                "Application will restart now."
            )
            
            # Restart the application
            python_executable = sys.executable
            script_path = str(self.script_dir / "iot_pubsub_gui.py")
            
            # Use os.execv to replace current process
            os.execv(python_executable, [python_executable, script_path])
            
        except Exception as e:
            error_msg = f"Update failed: {e}"
            logger.error(error_msg)
            self.add_log(f"ERROR: {error_msg}")
            QMessageBox.critical(
                self,
                "Update Error",
                f"Failed to update application:\n{error_msg}"
            )
            self.update_now_btn.setEnabled(True)
            self.update_now_btn.setText("Update Now")
    
    def closeEvent(self, event):
        """Handle window close event"""
        if self.is_connected:
            self.disconnect_from_iot()
        event.accept()


def main():
    """Main entry point"""
    app = QApplication(sys.argv)
    app.setStyle('Fusion')  # Modern look
    
    window = AWSIoTPubSubGUI()
    window.show()
    
    sys.exit(app.exec())


if __name__ == "__main__":
    main()


IOT_PUBSUB_GUI_EOF

print_success "Extracted iot_pubsub_gui.py"

# Extract requirements.txt
cat > "$INSTALL_DIR/requirements.txt" << 'REQUIREMENTS_EOF'
# AWS IoT Pub/Sub GUI - Python Dependencies
# Core application dependencies
PyQt6>=6.0.0
awsiotsdk>=1.0.0
awscrt>=0.19.0
cryptography>=3.0.0
python-dateutil>=2.8.0
requests>=2.28.0


REQUIREMENTS_EOF

print_success "Extracted requirements.txt"

# Extract VERSION
cat > "$INSTALL_DIR/VERSION" << 'VERSION_EOF'
1.0.0

VERSION_EOF

print_success "Extracted VERSION"

# Extract desktop launcher template
cat > "$INSTALL_DIR/iot-pubsub-gui.desktop" << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=IoT PubSub GUI
Comment=Launch IoT PubSub GUI Application
Exec=bash -c "cd '$HOME/iot-pubsub-gui' && source venv/bin/activate && python3 iot_pubsub_gui.py"
Path=$HOME/iot-pubsub-gui
Icon=application-x-executable
Terminal=false
Categories=Network;Utility;
StartupNotify=true
Keywords=IoT;AWS;MQTT;PubSub;


DESKTOP_EOF

print_success "Extracted desktop launcher"

# ============================================================================
# Step 3.5: Initialize git repository for future updates
# ============================================================================
print_step "Step 3.5: Setting Up Git Repository for Auto-Updates"

# Check if git is installed
if command -v git &> /dev/null; then
    print_info "Initializing git repository for future auto-updates..."
    
    cd "$INSTALL_DIR"
    
    # Initialize git repository if not already one
    if [ ! -d ".git" ]; then
        git init
        git config user.name "IoT PubSub GUI Installer"
        git config user.email "installer@iot-pubsub-gui.local"
        
        # Add remote origin
        git remote add origin https://github.com/thienanlktl/Pideployment.git 2>/dev/null || \
        git remote set-url origin https://github.com/thienanlktl/Pideployment.git
        
        # Add all files
        git add .
        
        # Create initial commit
        git commit -m "Initial installation from standalone installer v1.0.0" || {
            print_warning "Could not create initial commit (this is okay if files are already committed)"
        }
        
        # Set up branch to track origin/main (for future updates)
        git branch -M main 2>/dev/null || true
        git branch --set-upstream-to=origin/main main 2>/dev/null || true
        
        print_success "Git repository initialized for auto-updates"
    else
        print_info "Git repository already exists"
    fi
else
    print_warning "Git is not installed. Auto-update feature will not work."
    print_info "To enable auto-updates later, install git and run:"
    print_info "  cd $INSTALL_DIR"
    print_info "  git init"
    print_info "  git remote add origin https://github.com/thienanlktl/Pideployment.git"
    print_info "  git add ."
    print_info "  git commit -m 'Initial commit'"
    print_info "  git branch -M main"
fi

# ============================================================================
# Step 4: Create virtual environment
# ============================================================================
print_step "Step 4: Creating Virtual Environment"

VENV_DIR="$INSTALL_DIR/venv"

if [ -d "$VENV_DIR" ]; then
    print_info "Virtual environment already exists"
else
    print_info "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    print_success "Virtual environment created"
fi

# Activate virtual environment
print_info "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
print_info "Upgrading pip..."
pip install --upgrade pip --quiet

# ============================================================================
# Step 5: Install Python dependencies
# ============================================================================
print_step "Step 5: Installing Python Dependencies"

print_info "Installing Python packages from requirements.txt (this may take 10-30 minutes on first run)..."

if pip install -r requirements.txt; then
    print_success "Python dependencies installed"
else
    print_error "Failed to install Python dependencies"
    exit 1
fi

# Verify critical packages
print_info "Verifying critical packages..."
python3 -c "import PyQt6; import awsiot; import sqlite3" && {
    print_success "Critical packages verified"
} || {
    print_error "Critical packages verification failed"
    exit 1
}

# Verify SQLite3 database support
print_info "Verifying SQLite3 database support..."
python3 -c "import sqlite3; conn = sqlite3.connect(':memory:'); conn.execute('CREATE TABLE test (id INTEGER)'); conn.close()" && {
    print_success "SQLite3 database support verified"
} || {
    print_error "SQLite3 database support verification failed"
    print_warning "The application requires SQLite3 for message storage"
    exit 1
}

# ============================================================================
# Step 6: Create desktop launcher
# ============================================================================
print_step "Step 6: Creating Desktop Launcher"

DESKTOP_DIR="$HOME/Desktop"
DESKTOP_FILE="$DESKTOP_DIR/iot-pubsub-gui.desktop"

# Ensure Desktop directory exists
mkdir -p "$DESKTOP_DIR"

# Update desktop file with correct paths
print_info "Creating desktop launcher..."

cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=IoT PubSub GUI
Comment=Launch IoT PubSub GUI Application
Exec=bash -c "cd '$INSTALL_DIR' && source venv/bin/activate && python3 iot_pubsub_gui.py"
Path=$INSTALL_DIR
Icon=application-x-executable
Terminal=false
Categories=Network;Utility;
StartupNotify=true
Keywords=IoT;AWS;MQTT;PubSub;
EOF

# Make launcher executable
chmod +x "$DESKTOP_FILE"

# Make desktop file trusted (required for some desktop environments)
if command -v gio &> /dev/null; then
    gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
fi

# Refresh desktop (if possible)
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

print_success "Desktop launcher created: $DESKTOP_FILE"

# ============================================================================
# Step 7: Verify installation
# ============================================================================
print_step "Step 7: Verifying Installation"

# Check main application file
if [ ! -f "$INSTALL_DIR/iot_pubsub_gui.py" ]; then
    print_error "Main application file not found"
    exit 1
fi
print_success "Main application file found"

# Verify SQLite3 is available in Python
print_info "Verifying SQLite3 in Python environment..."
if python3 -c "import sqlite3; print('SQLite3 version:', sqlite3.sqlite_version)" 2>/dev/null; then
    print_success "SQLite3 is available in Python"
else
    print_warning "SQLite3 may not be properly configured in Python"
fi

# Check certificate files (warn if missing, but don't fail)
CERT_FILES=(
    "AmazonRootCA1.pem"
    "ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt"
    "ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key"
)

MISSING_CERTS=()
for cert in "${CERT_FILES[@]}"; do
    if [ ! -f "$INSTALL_DIR/$cert" ]; then
        MISSING_CERTS+=("$cert")
    fi
done

if [ ${#MISSING_CERTS[@]} -gt 0 ]; then
    print_warning "Some certificate files are missing (application may not connect to AWS IoT):"
    for cert in "${MISSING_CERTS[@]}"; do
        echo "  - $cert"
    done
    print_info "You can add certificate files to: $INSTALL_DIR"
else
    print_success "All certificate files found"
fi

# ============================================================================
# Installation Complete
# ============================================================================
print_step "Installation Complete!"

print_success "IoT PubSub GUI has been successfully installed!"
echo ""
print_info "Installation directory: $INSTALL_DIR"
print_info "Desktop launcher: $DESKTOP_FILE"
echo ""
print_info "To run the application:"
echo "  1. Double-click the 'IoT PubSub GUI' icon on your desktop"
echo ""
echo "  2. Or run from terminal:"
echo "     cd $INSTALL_DIR"
echo "     source venv/bin/activate"
echo "     python3 iot_pubsub_gui.py"
echo ""
print_info "Note: Certificate files are required for AWS IoT connection."
print_info "Note: SQLite3 database will be created automatically when the application runs."
echo ""
