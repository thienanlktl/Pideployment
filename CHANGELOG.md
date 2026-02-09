# Update log (Changelog)

All notable changes to the IoT PubSub GUI project.

## [1.0.4] – Release branch

- In-app self-update: GitPython-based update from latest Release branch (no external script).
- Update progress dialog: improved UI with status log and clear success/error states.
- Fullscreen by default; optional "Exit fullscreen" button.
- One-click installer: `install.sh` clones from main, uses SSH keys from `~/.ssh`.
- Desktop icon and menu shortcut created by installer.
- Removed dependency on `update_service.py`; all update logic in main app.

## [1.0.3]

- Bug fixes and stability improvements.

## [1.0.2]

- SQLite message storage; view all messages in database.
- AWS IoT Core MQTT publish/subscribe with certificate-based auth.

## [1.0.1]

- Initial PyQt6 GUI; connect to AWS IoT, publish, subscribe.
- Real-time message log.

## [1.0.0]

- Project setup; requirements and deployment guides.

---

For detailed deployment, see [README.md](README.md) and [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md).
