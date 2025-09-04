<p align="center">
  <img src="BTor.png" alt="Logo" width="300" height="300">
</p>

<h1 align="center">🧅 BTor – Tor Service & Browser Manager</h1>

<p align="center">
  Simple CLI + Manager for Tor Service & Tor Browser on Linux and Windows
</p>

---

<p align="center">
  <img src="https://img.shields.io/github/stars/linux-brat/btor?style=for-the-badge&logo=github&color=blue" alt="Stars"/>
  <img src="https://img.shields.io/github/forks/linux-brat/btor?style=for-the-badge&logo=github&color=blueviolet" alt="Forks"/>
  <img src="https://img.shields.io/github/issues/linux-brat/btor?style=for-the-badge&logo=github&color=red" alt="Issues"/>
  <img src="https://img.shields.io/github/license/linux-brat/btor?style=for-the-badge&color=success" alt="License"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Made%20for-Linux-2ea44f?style=for-the-badge&logo=linux" alt="Linux"/>
  <img src="https://img.shields.io/badge/Made%20for-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows"/>
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash"/>
  <img src="https://img.shields.io/badge/Tor-Network-7D4698?style=for-the-badge&logo=tor-project&logoColor=white" alt="Tor"/>
</p>

<div align="center">

[![GitButler](https://img.shields.io/badge/GitButler-%23B9F4F2?logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB3aWR0aD0iMzkiIGhlaWdodD0iMjgiIHZpZXdCb3g9IjAgMCAzOSAyOCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTI1LjIxNDUgMTIuMTk5N0wyLjg3MTA3IDEuMzg5MTJDMS41NDI5NSAwLjc0NjUzMiAwIDEuNzE0MDYgMCAzLjE4OTQ3VjI0LjgxMDVDMCAyNi4yODU5IDEuNTQyOTUgMjcuMjUzNSAyLjg3MTA3IDI2LjYxMDlMMjUuMjE0NSAxNS44MDAzQzI2LjcxOTcgMTUuMDcyMSAyNi43MTk3IDEyLjkyNzkgMjUuMjE0NSAxMi4xOTk3WiIgZmlsbD0iYmxhY2siLz4KPHBhdGggZD0iTTEzLjc4NTUgMTIuMTk5N0wzNi4xMjg5IDEuMzg5MTJDMzcuNDU3MSAwLjc0NjUzMiAzOSAxLjcxNDA2IDM5IDMuMTg5NDdWMjQuODEwNUMzOSAyNi4yODU5IDM3LjQ1NzEgMjcuMjUzNSAzNi4xMjg5IDI2LjYxMDlMMTMuNzg1NSAxNS44MDAzQzEyLjI4MDMgMTUuMDcyMSAxMi4yODAzIDEyLjkyNzkgMTMuNzg1NSAxMi4xOTk3WiIgZmlsbD0idXJsKCNwYWludDBfcmFkaWFsXzMxMF8xMjkpIi8%2BCjxkZWZzPgo8cmFkaWFsR3JhZGllbnQgaWQ9InBhaW50MF9yYWRpYWxfMzEwXzEyOSIgY3g9IjAiIGN5PSIwIiByPSIxIiBncmFkaWVudFVuaXRzPSJ1c2VyU3BhY2VPblVzZSIgZ3JhZGllbnRUcmFuc2Zvcm09InRyYW5zbGF0ZSgxNi41NzAxIDE0KSBzY2FsZSgxOS44NjQxIDE5LjgzODMpIj4KPHN0b3Agb2Zmc2V0PSIwLjMwMTA1NiIgc3RvcC1vcGFjaXR5PSIwIi8%2BCjxzdG9wIG9mZnNldD0iMSIvPgo8L3JhZGlhbEdyYWRpZW50Pgo8L2RlZnM%2BCjwvc3ZnPgo%3D)](https://gitbutler.com/)

</div>

---

## 🚀 Quick Start

Choose your platform and follow the official instructions on the Releases pages:

<p align="center">
  <a href="https://github.com/linux-brat/BTor/releases/tag/Windows">
    <img src="https://img.shields.io/badge/Refer%20to%20Windows%20Release-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows Release"/>
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/linux-brat/BTor/releases/tag/Linux">
    <img src="https://img.shields.io/badge/Refer%20to%20Linux%20Release-2ea44f?style=for-the-badge&logo=linux&logoColor=white" alt="Linux Release"/>
  </a>
</p>

---

## 🔧 Usage

### CLI Commands

```
btor                       # Launch interactive menu
btor start                 # Start Tor service
btor stop                  # Stop Tor service
btor restart               # Restart Tor service
btor enable                # Enable Tor at boot
btor disable               # Disable Tor at boot
btor status [--full]       # Show service status
btor update                # Update BTor
btor uninstall             # Uninstall BTor
```

---

## ⚙️ Environment Variables

| Variable               | Default                | Description                       |
|------------------------|------------------------|-----------------------------------|
| `BTOR_SERVICE_NAME`    | `tor.service`          | Override Tor systemd service name |
| `BTOR_HOME`            | `~/.btor`              | Installation directory            |
| `BTOR_BIN_LINK`        | `/usr/local/bin/btor`  | Symlink path for global access    |
| `BTOR_REPO_RAW`        | GitHub raw script URL  | Where updates are fetched from    |
| `BTOR_TOR_BROWSER_DIR` | `~/.local/tor-browser` | Where Tor Browser is installed    |
| `BTOR_TB_URL`          | Official Tor tarball   | Override download URL             |

Example:

```
BTOR_SERVICE_NAME=tor@default.service btor start
```

---

## 📜 License

MIT License © 2025 [linux-brat](LICENSE)