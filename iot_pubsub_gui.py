"""
AWS IoT Pub/Sub GUI Application using PyQt6 and AWS IoT Device SDK v2

This app uses PyQt6 (not Tkinter). It includes in-app self-updating via GitPython,
fullscreen-by-default, and a one-click installer (install.sh) for Raspberry Pi.

Installation:
    pip install -r requirements.txt  # includes PyQt6, awsiotsdk, GitPython

Run:
    python iot_pubsub_gui.py

On Raspberry Pi: use install.sh for one-click setup, then run from menu or:
    cd ~/iot-pubsub-gui && venv/bin/python3 iot_pubsub_gui.py
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

# Check for required dependencies before importing PyQt6
def check_dependencies():
    """Check if all required dependencies are installed"""
    script_dir = Path(__file__).parent.absolute()
    
    # Check if we're using venv Python
    venv_python_paths = [
        script_dir / "venv" / "bin" / "python3",
        script_dir / "venv" / "bin" / "python",
        script_dir / "venv" / "Scripts" / "python.exe",
    ]
    
    is_venv_python = False
    for venv_path in venv_python_paths:
        if Path(sys.executable) == venv_path:
            is_venv_python = True
            break
    
    # Also check if we're in a virtual environment (hasattr(sys, 'real_prefix') or sys.base_prefix != sys.prefix)
    in_venv = hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix)
    
    missing_deps = []
    required_modules = {
        'PyQt6': 'PyQt6',
        'awscrt': 'awscrt',
        'awsiot': 'awsiotsdk',
    }
    
    for module_name, package_name in required_modules.items():
        try:
            __import__(module_name)
        except ImportError:
            missing_deps.append(package_name)
    
    if missing_deps:
        print("=" * 60)
        print("ERROR: Missing required dependencies!")
        print("=" * 60)
        print(f"The following packages are not installed: {', '.join(missing_deps)}")
        print(f"\nCurrent Python: {sys.executable}")
        
        # Check if venv exists
        venv_exists = any(p.exists() for p in venv_python_paths)
        
        if venv_exists and not (is_venv_python or in_venv):
            print("\n⚠ WARNING: Virtual environment exists but you're using system Python!")
            print("You should run the application using the virtual environment:")
            print(f"  {venv_python_paths[0] if venv_python_paths[0].exists() else venv_python_paths[1]} iot_pubsub_gui.py")
            print("\nOr activate the virtual environment first:")
            if sys.platform == 'win32':
                print("  venv\\Scripts\\activate")
            else:
                print("  source venv/bin/activate")
            print("  python3 iot_pubsub_gui.py")
        
        print("\nTo install dependencies:")
        if venv_exists and not (is_venv_python or in_venv):
            venv_python = next((p for p in venv_python_paths if p.exists()), None)
            if venv_python:
                print(f"  {venv_python} -m pip install -r requirements.txt")
        else:
            print("  pip install -r requirements.txt")
            if not venv_exists:
                print("\nOr create and use a virtual environment:")
                print("  python3 -m venv venv")
                if sys.platform == 'win32':
                    print("  venv\\Scripts\\activate")
                else:
                    print("  source venv/bin/activate")
                print("  pip install -r requirements.txt")
        
        print("=" * 60)
        sys.exit(1)

# Check dependencies before proceeding
check_dependencies()

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QTextEdit, QPushButton, QGroupBox, QMessageBox,
    QDialog, QTableWidget, QTableWidgetItem, QHeaderView, QProgressBar,
    QFrame, QScrollArea, QSizePolicy
)
from PyQt6.QtCore import Qt, QObject, pyqtSignal, QMetaObject, Q_ARG, QThread, QTimer
from PyQt6.QtGui import QTextCursor, QColor

from awscrt import mqtt
from awsiot import mqtt_connection_builder

# Try to import requests for update check
try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

# Try to import GitPython for in-app git updates
try:
    import git  # type: ignore[import-untyped]
    GITPYTHON_AVAILABLE = True
except ImportError:
    GITPYTHON_AVAILABLE = False

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
    log_message = pyqtSignal(str)  # log message from background thread


class UpdateProgressSignals(QObject):
    """Signals for update progress dialog (thread-safe GUI updates during git operations)"""
    status_message = pyqtSignal(str)
    log_line = pyqtSignal(str)  # append to progress log only (e.g. errors, details)
    finished = pyqtSignal(bool, str)  # success, message


class UpdateProgressDialog(QDialog):
    """
    Modal dialog shown during in-app update: progress bar, status log, cancel button.
    Update runs in a background thread; this dialog stays responsive and shows a live log.
    Log is also written to a text file when finished (if log_file_path is set).
    """
    def __init__(self, parent=None, cancel_event=None, log_file_path=None):
        super().__init__(parent)
        self.cancel_event = cancel_event or threading.Event()
        self.log_file_path = Path(log_file_path) if log_file_path else None
        self.setWindowTitle("Application Update")
        self.setModal(True)
        self.setFixedSize(500, 380)
        self._finished = False
        self._success = False

        # Main layout
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(20, 20, 20, 20)

        # Title
        title = QLabel("Updating IoT PubSub GUI")
        title.setStyleSheet(
            "font-size: 14pt; font-weight: bold; color: #1a73e8; padding: 4px 0;"
        )
        layout.addWidget(title)

        # Current status (prominent)
        self.status_label = QLabel("Preparing...")
        self.status_label.setWordWrap(True)
        self.status_label.setStyleSheet(
            "font-size: 11pt; color: #333; padding: 6px 0; min-height: 22px;"
        )
        layout.addWidget(self.status_label)

        # Progress bar
        self.progress_bar = QProgressBar(self)
        self.progress_bar.setRange(0, 0)
        self.progress_bar.setMinimumHeight(10)
        self.progress_bar.setStyleSheet("""
            QProgressBar {
                border: 1px solid #ccc;
                border-radius: 5px;
                text-align: center;
                background: #f0f0f0;
            }
            QProgressBar::chunk {
                background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
                    stop:0 #1a73e8, stop:1 #34a853);
                border-radius: 4px;
            }
        """)
        layout.addWidget(self.progress_bar)

        # Update log (scrollable); also written to update_progress.log when finished
        log_label = QLabel("Update log (saved to update_progress.log when finished)")
        log_label.setStyleSheet("font-size: 10pt; color: #666; padding-top: 8px;")
        layout.addWidget(log_label)
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setMaximumHeight(120)
        self.log_text.setStyleSheet("""
            QTextEdit {
                font-family: 'Consolas', 'Monaco', monospace;
                font-size: 9pt;
                background: #f8f9fa;
                border: 1px solid #dee2e6;
                border-radius: 4px;
                padding: 6px;
            }
        """)
        self.log_text.setPlaceholderText("Status messages will appear here...")
        layout.addWidget(self.log_text)

        # Button
        self.cancel_btn = QPushButton("Cancel")
        self.cancel_btn.setMinimumHeight(36)
        self.cancel_btn.setStyleSheet("""
            QPushButton {
                font-size: 11pt;
                padding: 8px 20px;
                background: #5f6368;
                color: white;
                border: none;
                border-radius: 6px;
            }
            QPushButton:hover { background: #4a4d52; }
            QPushButton:disabled { background: #bdc1c6; color: #5f6368; }
        """)
        self.cancel_btn.clicked.connect(self._on_cancel)
        layout.addWidget(self.cancel_btn)

        # Start log file when update runs (header line)
        if self.log_file_path:
            try:
                self.log_file_path.write_text(
                    f"===== Update started {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} =====\n",
                    encoding="utf-8",
                )
            except Exception as e:
                logger.warning("Could not write update log file header: %s", e)
        self._append_log("Preparing update...")

    def _append_log(self, line: str):
        ts = datetime.now().strftime("%H:%M:%S")
        self.log_text.append(f"[{ts}] {line}")
        self.log_text.moveCursor(QTextCursor.MoveOperation.End)
        # Append to log file as we go (so log exists even if dialog is closed)
        if self.log_file_path:
            try:
                with self.log_file_path.open("a", encoding="utf-8") as f:
                    f.write(f"[{ts}] {line}\n")
            except Exception:
                pass

    def _on_cancel(self):
        if not self._finished:
            self.cancel_event.set()
            self.status_label.setText("Cancelling...")
            self._append_log("Cancelling...")
            self.cancel_btn.setEnabled(False)

    def set_status(self, text: str):
        self.status_label.setText(text)
        self._append_log(text)

    def append_log_only(self, text: str):
        """Append a line to the progress log without changing the status label (e.g. errors, details)."""
        self._append_log(text)

    def set_finished(self, success: bool, message: str):
        self._finished = True
        self._success = success
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(100 if success else 0)
        if success:
            self.progress_bar.setStyleSheet("""
                QProgressBar {
                    border: 1px solid #34a853;
                    border-radius: 5px;
                    background: #e6f4ea;
                }
                QProgressBar::chunk { background: #34a853; border-radius: 4px; }
            """)
            self.status_label.setStyleSheet(
                "font-size: 11pt; font-weight: bold; color: #34a853; padding: 6px 0;"
            )
        else:
            self.progress_bar.setStyleSheet("""
                QProgressBar {
                    border: 1px solid #ea4335;
                    border-radius: 5px;
                    background: #fce8e6;
                }
                QProgressBar::chunk { background: #ea4335; border-radius: 4px; }
            """)
            self.status_label.setStyleSheet(
                "font-size: 11pt; font-weight: bold; color: #ea4335; padding: 6px 0;"
            )
        self.status_label.setText(message)
        self._append_log("Done: " + message)
        # Append footer to log file
        if self.log_file_path:
            try:
                with self.log_file_path.open("a", encoding="utf-8") as f:
                    f.write(f"\n===== Update finished ({'Success' if success else 'Failed'}) {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} =====\n\n")
                logger.info("Update progress log: %s", self.log_file_path)
            except Exception as e:
                logger.warning("Could not append update log footer: %s", e)
        self.cancel_btn.setText("Close")
        self.cancel_btn.setEnabled(True)
        self.cancel_btn.setStyleSheet("""
            QPushButton {
                font-size: 11pt;
                padding: 8px 20px;
                background: #1a73e8;
                color: white;
                border: none;
                border-radius: 6px;
            }
            QPushButton:hover { background: #1557b0; }
        """)
        try:
            self.cancel_btn.clicked.disconnect()
        except TypeError:
            pass
        self.cancel_btn.clicked.connect(self.accept)


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
        self.update_checker.log_message.connect(self.add_log)  # Connect log signal for thread-safe logging
        self.latest_release_version = None
        self.local_version = None
        self.script_dir = script_dir
        self._venv_python_for_restart = None  # Will be set during update process
        
        self.init_ui()
        self.init_database()  # Initialize database after UI so log_text exists
        self.update_status("Disconnected", False)
        
        # Start update check in background after UI is ready
        # Use QTimer to call it after the event loop starts
        QTimer.singleShot(1000, self.start_update_check)  # Wait 1 second for UI to be fully ready
    
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

        # Exit fullscreen button (non-intrusive, right side)
        self.exit_fullscreen_btn = QPushButton("Exit fullscreen")
        self.exit_fullscreen_btn.setStyleSheet(
            "font-size: 9pt; color: gray; padding: 4px 8px; "
            "background-color: transparent; border: 1px solid #ccc;"
        )
        self.exit_fullscreen_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.exit_fullscreen_btn.clicked.connect(self._exit_fullscreen)
        top_bar_layout.addWidget(self.exit_fullscreen_btn)
        
        # New version available label (clickable, next to version label, initially hidden)
        self.new_version_label = QPushButton()
        self.new_version_label.setStyleSheet(
            "font-size: 10pt; color: #2196F3; padding: 5px; "
            "background-color: transparent; border: none; text-decoration: underline;"
        )
        self.new_version_label.setCursor(Qt.CursorShape.PointingHandCursor)
        self.new_version_label.clicked.connect(self.on_new_version_clicked)
        self.new_version_label.setVisible(False)
        top_bar_layout.addWidget(self.new_version_label)
        
        top_bar_layout.addStretch()
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

    def _exit_fullscreen(self):
        """Exit fullscreen and show window normal (or maximized)."""
        if self.isFullScreen():
            self.showNormal()
            self.showMaximized()
    
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
                    self.add_log(f"  ✓ {name}: {path} (Size: {file_size} bytes)")
                else:
                    missing_files.append(f"{name}: {path}")
                    self.add_log(f"  ✗ {name}: NOT FOUND - {path}")
            
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
                self.add_log("  ✓ MQTT connection object created successfully")
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
                self.add_log("  → Waiting for connection (timeout: 10 seconds)...")
                connect_future.result(timeout=10)
                self.add_log("  ✓ Connection established successfully!")
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
            self.add_log(f"✓ Successfully connected to AWS IoT Core!")
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
    
    def _get_venv_python(self):
        """Get the virtual environment Python executable path"""
        venv_paths = [
            self.script_dir / "venv" / "bin" / "python3",
            self.script_dir / "venv" / "bin" / "python",
            self.script_dir / "venv" / "Scripts" / "python.exe",  # Windows
        ]
        
        for venv_path in venv_paths:
            if venv_path.exists():
                return venv_path
        return None
    
    def start_update_check(self):
        """Start update check in background thread - checks for Release/* branches"""
        def check_update():
            """Check for updates in background thread"""
            try:
                logger.info("Starting update check...")
                # Use signal to safely call add_log from background thread
                self.update_checker.log_message.emit("Checking for updates...")
                
                # Get local version
                local_version = __version__
                logger.info(f"Local version: {local_version}")
                
                # Check for Release branches using GitHub API
                update_available = False
                latest_release_version = None
                
                if REQUESTS_AVAILABLE:
                    try:
                        # Get all branches from GitHub
                        branches_url = "https://api.github.com/repos/thienanlktl/Pideployment/branches"
                        response = requests.get(branches_url, timeout=10)
                        
                        if response.status_code == 200:
                            branches_data = response.json()
                            logger.info(f"Found {len(branches_data)} branches")
                            
                            # Filter Release/* branches and extract versions
                            release_versions = []
                            for branch in branches_data:
                                branch_name = branch.get('name', '')
                                if branch_name.startswith('Release/'):
                                    # Extract version from branch name (Release/1.0.2 -> 1.0.2)
                                    version_str = branch_name.replace('Release/', '').strip()
                                    if version_str:
                                        release_versions.append(version_str)
                                        logger.info(f"Found Release branch: {branch_name} (version: {version_str})")
                            
                            if release_versions:
                                # Find the latest version by comparing all release versions
                                latest_release_version = release_versions[0]
                                for version in release_versions:
                                    if self._compare_versions(latest_release_version, version) < 0:
                                        latest_release_version = version
                                
                                logger.info(f"Latest Release branch version: {latest_release_version}")
                                
                                # Compare with local version
                                if self._compare_versions(local_version, latest_release_version) < 0:
                                    update_available = True
                                    logger.info(f"Update available! Latest Release: {latest_release_version}, Current: {local_version}")
                                else:
                                    logger.info(f"Application is up to date (current: {local_version}, latest release: {latest_release_version})")
                            else:
                                logger.info("No Release/* branches found")
                        else:
                            logger.warning(f"GitHub API returned status {response.status_code}")
                    except Exception as e:
                        logger.warning(f"Error checking Release branches: {e}")
                        self.update_checker.log_message.emit(f"Update check error: {e}")
                else:
                    logger.warning("requests library not available, cannot check for updates")
                    self.update_checker.log_message.emit("Update check unavailable: requests library not installed")
                
                # Emit signal if update is available
                if update_available and latest_release_version:
                    self.update_checker.update_available.emit(latest_release_version, local_version)
                    logger.info("Update notification sent to UI")
                else:
                    logger.info("Application is up to date")
                    self.update_checker.log_message.emit("Application is up to date")
                
                self.update_checker.check_complete.emit(True)
            except Exception as e:
                logger.error(f"Error in update check: {e}")
                self.update_checker.log_message.emit(f"Update check failed: {e}")
                self.update_checker.check_complete.emit(False)
        
        # Run in background thread
        thread = threading.Thread(target=check_update, daemon=True)
        thread.start()
    
    def _compare_versions(self, v1: str, v2: str) -> int:
        """Compare two version strings. Returns -1 if v1 < v2, 0 if equal, 1 if v1 > v2"""
        try:
            # Split version strings into parts
            parts1 = [int(x) for x in v1.split('.')]
            parts2 = [int(x) for x in v2.split('.')]
            
            # Pad with zeros to make same length
            max_len = max(len(parts1), len(parts2))
            parts1.extend([0] * (max_len - len(parts1)))
            parts2.extend([0] * (max_len - len(parts2)))
            
            # Compare
            for p1, p2 in zip(parts1, parts2):
                if p1 < p2:
                    return -1
                elif p1 > p2:
                    return 1
            return 0
        except Exception:
            # If version comparison fails, do string comparison
            if v1 < v2:
                return -1
            elif v1 > v2:
                return 1
            return 0
    
    def on_update_available(self, remote_version: str, local_version: str):
        """Handle update available signal"""
        self.latest_release_version = remote_version
        self.local_version = local_version
        logger.info(f"Update available: {remote_version} (current: {local_version})")
        
        # Update new version label text and make it visible
        self.new_version_label.setText(f"→ New version {remote_version} available (click to upgrade)")
        self.new_version_label.setVisible(True)
        
        # Add log message
        self.add_log(f"Update available! Latest version: {remote_version}, Current version: {local_version}")
    
    def on_new_version_clicked(self):
        """Handle click on new version label - show confirmation then run in-app update with progress dialog."""
        if not self.latest_release_version:
            return
        if not GITPYTHON_AVAILABLE:
            QMessageBox.warning(
                self,
                "Update Unavailable",
                "GitPython is not installed. Install it with: pip install gitpython\n\n"
                "Or update manually from the installation directory using git pull."
            )
            return

        reply = QMessageBox.question(
            self,
            "Confirm Update",
            f"A new version ({self.latest_release_version}) is available.\n\n"
            f"Current version: {self.local_version or __version__}\n\n"
            f"The update will run in the background. When finished, restart the application to apply changes.\n\n"
            f"Continue?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )

        if reply != QMessageBox.StandardButton.Yes:
            return

        self._run_in_app_update(self.latest_release_version)

    def on_update_check_complete(self, success: bool):
        """Handle update check completion"""
        if success:
            logger.info("Update check completed")
        else:
            logger.warning("Update check completed with errors")

    def _run_in_app_update(self, target_version: str):
        """
        Run update in background thread with a modal progress dialog.
        No restart; user is prompted to restart when done.
        """
        cancel_event = threading.Event()
        progress_signals = UpdateProgressSignals()
        log_file = self.script_dir / "update_progress.log"
        dialog = UpdateProgressDialog(self, cancel_event=cancel_event, log_file_path=log_file)
        progress_signals.status_message.connect(dialog.set_status)
        progress_signals.log_line.connect(dialog.append_log_only)
        progress_signals.finished.connect(dialog.set_finished)

        def worker():
            self._do_git_update(
                str(self.script_dir),
                target_version,
                progress_signals,
                cancel_event,
            )

        self.new_version_label.setEnabled(False)
        self.new_version_label.setText("Updating...")
        thread = threading.Thread(target=worker, daemon=True)
        thread.start()
        dialog.exec()
        # Re-enable label and restore text if update was cancelled or failed
        self.new_version_label.setText(f"→ New version {self.latest_release_version} available (click to upgrade)")
        self.new_version_label.setEnabled(True)

    def _get_git_env_with_ssh(self):
        """Build env with GIT_SSH_COMMAND so git uses SSH key from ~/.ssh (avoids permission denied)."""
        env = os.environ.copy()
        ssh_dir = Path.home() / ".ssh"
        key_file = None
        if (ssh_dir / "id_ed25519").exists():
            key_file = ssh_dir / "id_ed25519"
        elif (ssh_dir / "id_rsa").exists():
            key_file = ssh_dir / "id_rsa"
        if key_file:
            key_path = str(key_file.resolve())
            env["GIT_SSH_COMMAND"] = f"ssh -i '{key_path}' -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
        return env

    def _do_git_update(
        self,
        script_dir: str,
        target_version: str,
        signals: UpdateProgressSignals,
        cancel_event: threading.Event,
    ):
        """
        Perform git fetch, checkout Release/<target_version>, and pull.
        Uses SSH key from ~/.ssh to avoid permission denied. In-app update pulls from latest Release branch.
        Runs in background thread. Emits status_message and finished on signals.
        """
        try:
            signals.status_message.emit("Checking repository...")
            if cancel_event.is_set():
                signals.finished.emit(False, "Update cancelled.")
                return

            git_env = self._get_git_env_with_ssh()
            if "GIT_SSH_COMMAND" in git_env:
                signals.log_line.emit("Using SSH key from ~/.ssh for fetch/pull.")

            if not GITPYTHON_AVAILABLE:
                signals.log_line.emit("ERROR: GitPython not installed.")
                signals.finished.emit(False, "GitPython not installed. Run: pip install gitpython")
                return

            try:
                repo = git.Repo(script_dir)
            except Exception as e:
                signals.log_line.emit(f"ERROR: {e}")
                signals.finished.emit(False, "Not a git repository or access denied.")
                return

            if repo.bare:
                signals.log_line.emit("ERROR: Repository is bare.")
                signals.finished.emit(False, "Not a git repository (bare).")
                return

            # Force undo uncommitted changes so we can pull latest
            if repo.is_dirty():
                signals.status_message.emit("Discarding local changes...")
                signals.log_line.emit("Local uncommitted changes detected; discarding to pull latest.")
                try:
                    subprocess.run(
                        ["git", "reset", "--hard", "HEAD"],
                        cwd=script_dir,
                        timeout=15,
                        capture_output=True,
                        check=True,
                        text=True,
                    )
                    signals.log_line.emit("Reset uncommitted changes done.")
                    subprocess.run(
                        ["git", "clean", "-fd"],
                        cwd=script_dir,
                        timeout=15,
                        capture_output=True,
                        text=True,
                    )
                    signals.log_line.emit("Clean untracked files done.")
                except subprocess.TimeoutExpired:
                    signals.log_line.emit("ERROR: Timeout discarding local changes.")
                    signals.finished.emit(False, "Could not discard local changes (timeout).")
                    return
                except subprocess.CalledProcessError as e:
                    err = (e.stderr or e.stdout or "").strip() or str(e)
                    signals.log_line.emit(f"ERROR (reset): {err}")
                    signals.finished.emit(False, f"Could not discard local changes: {err}")
                    return

            signals.log_line.emit("Repository OK.")

            # Use SSH remote so GIT_SSH_COMMAND (and SSH key) is used; avoid permission denied
            try:
                origin_url = repo.remotes.origin.url
                if origin_url.startswith("https://github.com/"):
                    path = origin_url.replace("https://github.com/", "").strip("/").replace(".git", "")
                    ssh_url = f"git@github.com:{path}.git"
                    if ssh_url != origin_url:
                        repo.remotes.origin.set_url(ssh_url)
                        signals.log_line.emit(f"Using SSH remote for update: {ssh_url}")
                elif origin_url.startswith("https://gitlab.com/"):
                    path = origin_url.replace("https://gitlab.com/", "").strip("/").replace(".git", "")
                    ssh_url = f"git@gitlab.com:{path}.git"
                    if ssh_url != origin_url:
                        repo.remotes.origin.set_url(ssh_url)
                        signals.log_line.emit(f"Using SSH remote for update: {ssh_url}")
            except Exception as e:
                signals.log_line.emit(f"Note: Could not switch to SSH remote: {e}")

            release_branch = f"Release/{target_version}"
            # Fetch only the release branch (faster than full fetch) with timeout
            signals.status_message.emit("Fetching from remote...")
            if cancel_event.is_set():
                signals.finished.emit(False, "Update cancelled.")
                return
            try:
                # Fetch only latest commit (depth=1); use SSH key to avoid permission denied
                subprocess.run(
                    ["git", "fetch", "origin", release_branch, "--depth=1"],
                    cwd=script_dir,
                    timeout=60,
                    capture_output=True,
                    check=True,
                    text=True,
                    env=git_env,
                )
                signals.log_line.emit("Fetch completed (latest only).")
            except subprocess.TimeoutExpired:
                signals.log_line.emit("ERROR (fetch): Timeout after 60 seconds.")
                signals.finished.emit(False, "Fetch timed out. Check network and try again.")
                return
            except subprocess.CalledProcessError as e:
                err = (e.stderr or e.stdout or "").strip() or "Fetch failed."
                signals.log_line.emit(f"ERROR (fetch): {err}")
                if "permission denied" in err.lower() or "access denied" in err.lower() or "publickey" in err.lower():
                    signals.log_line.emit("Tip: Ensure SSH key is in ~/.ssh (id_ed25519 or id_rsa) and public key is added to GitHub/GitLab. Remote should use SSH URL (git@github.com:...).")
                signals.finished.emit(False, f"Fetch failed: {err}")
                return
            except Exception as e:
                logger.exception("Git fetch failed")
                err = str(e).strip() or "Network or permission error."
                signals.log_line.emit(f"ERROR (fetch): {err}")
                signals.finished.emit(False, f"Fetch failed: {err}")
                return

            signals.status_message.emit(f"Checking out {release_branch}...")
            if cancel_event.is_set():
                signals.finished.emit(False, "Update cancelled.")
                return

            try:
                repo.git.checkout(release_branch)
                signals.log_line.emit(f"Checkout: {release_branch}.")
            except Exception:
                try:
                    repo.git.checkout("-b", release_branch, f"origin/{release_branch}")
                    signals.log_line.emit(f"Checkout (new branch): {release_branch}.")
                except Exception as e:
                    logger.exception("Git checkout failed")
                    signals.log_line.emit(f"ERROR (checkout): {e}")
                    signals.finished.emit(False, f"Checkout failed: {e}")
                    return

            signals.status_message.emit("Applying updates...")
            if cancel_event.is_set():
                signals.finished.emit(False, "Update cancelled.")
                return

            try:
                # Pull only latest commit (depth=1); use SSH key to avoid permission denied
                subprocess.run(
                    ["git", "pull", "origin", release_branch, "--depth=1"],
                    cwd=script_dir,
                    timeout=90,
                    capture_output=True,
                    check=True,
                    text=True,
                    env=git_env,
                )
                signals.log_line.emit("Pull completed (latest only).")
            except subprocess.TimeoutExpired:
                signals.log_line.emit("ERROR (pull): Timeout after 90 seconds.")
                signals.finished.emit(False, "Pull timed out. Check network and try again.")
                return
            except subprocess.CalledProcessError as e:
                err = (e.stderr or e.stdout or "").strip()
                if "permission denied" in err.lower() or "access denied" in err.lower() or "publickey" in err.lower():
                    signals.log_line.emit("Tip: Use SSH key in ~/.ssh and add public key to GitHub/GitLab. Set remote: git remote set-url origin git@github.com:user/repo.git")
                try:
                    subprocess.run(
                        ["git", "reset", "--hard", f"origin/{release_branch}"],
                        cwd=script_dir,
                        timeout=30,
                        capture_output=True,
                        check=True,
                        text=True,
                        env=git_env,
                    )
                    signals.log_line.emit("Reset to origin completed.")
                except subprocess.TimeoutExpired:
                    signals.log_line.emit("ERROR (reset): Timeout.")
                    signals.finished.emit(False, "Update timed out.")
                    return
                except subprocess.CalledProcessError as e:
                    err = (e.stderr or e.stdout or "").strip() or str(e)
                    signals.log_line.emit(f"ERROR (pull/reset): {err}")
                    signals.finished.emit(False, f"Update failed: {err}")
                    return
            except Exception as e:
                logger.exception("Git pull failed")
                signals.log_line.emit(f"ERROR (pull): {e}")
                signals.finished.emit(False, f"Update failed: {e}")
                return

            logger.info("In-app update completed successfully")
            signals.log_line.emit("Update completed successfully.")
            self.update_checker.log_message.emit("Update completed. Restart the application to apply changes.")
            signals.finished.emit(
                True,
                "Update complete. Restart the application to apply changes.",
            )
        except Exception as e:
            logger.exception("Update failed")
            err_msg = str(e).strip() or type(e).__name__
            signals.log_line.emit(f"ERROR: {err_msg}")
            for line in traceback.format_exc().splitlines()[-5:]:
                if line.strip():
                    signals.log_line.emit(f"  {line.strip()}")
            signals.finished.emit(False, f"Update failed: {err_msg}")

    def perform_update(self):
        """Legacy: start in-app update if a new version is available."""
        if self.latest_release_version:
            self.on_new_version_clicked()
        else:
            self.add_log("No update available.")
    
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
    # Launch in fullscreen by default (Raspberry Pi kiosk-style)
    window.showFullScreen()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()

