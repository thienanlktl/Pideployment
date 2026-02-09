#!/bin/bash
# Launcher for IoT PubSub GUI (in repo so it survives in-app update / git clean)
cd "$(dirname "$(readlink -f "$0")")"
exec ./venv/bin/python3 iot_pubsub_gui.py "$@"
