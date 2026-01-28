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
from pathlib import Path
from datetime import datetime
from typing import Optional

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QTextEdit, QPushButton, QGroupBox, QMessageBox,
    QDialog, QTableWidget, QTableWidgetItem, QHeaderView
)
from PyQt6.QtCore import Qt, QObject, pyqtSignal, QMetaObject, Q_ARG
from PyQt6.QtGui import QTextCursor, QColor

from awscrt import mqtt
from awsiot import mqtt_connection_builder


class MessageReceiver(QObject):
    """Signal emitter for thread-safe GUI updates from MQTT callbacks"""
    message_received = pyqtSignal(str, str, str)  # timestamp, topic, payload


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
        
        self.init_ui()
        self.init_database()  # Initialize database after UI so log_text exists
        self.update_status("Disconnected", False)
    
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
        
        # Status of update label (red)
        self.update_status_label = QLabel("Status of update")
        self.update_status_label.setStyleSheet("font-size: 12pt; font-weight: bold; padding: 5px; color: black;")
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

