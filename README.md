# *mouNT*FS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Human-AI](https://img.shields.io/badge/Built--with-AI-blue)](#contributors)

## What's *mouNT*FS

*mouNT*FS (pronounced "maun-tee-ef-es") helps you write to NTFS (pronounced "en-tee-ef-es") drives on your Mac. No more "read-only" frustration! Just select your drive, provide your password to confirm, and you're ready to go - with native macOS dialogs that feel right at home.

Currently, *mouNT*FS is just one simple shell script that does one thing well - mounting NTFS drives with write access. We keep it clean and focused.

🤝 This project is an experiment in human-AI collaboration, co-authored with AI buddies 🤖. All code is written by AI, with humans focusing on design, review, and direction - no direct human coding. This must be a fun ride and let's see where it goes.

### Features

- 🤖 Co-developed with AI buddies
- 📁 Native file picker for volume selection
- 🔐 Secure password handling through system dialog
- 📊 Detailed volume information:
  - Volume name and device path
  - Current usage and total size
  - File system and mount status
- 🔄 Automatic fallback between mount methods
- ✅ Write access verification

### Under the Hood

The script safely handles NTFS mounting by first unmounting the volume, then trying the `mount_ntfs` with read-write option. If that fails, it falls back to the more reliable `ntfs-3g`. After mounting, it verifies write access and uses native macOS dialogs throughout the process.

## Getting Started

### Requirements

- macOS
- [macFUSE](https://osxfuse.github.io) - FUSE file system support for macOS
- [ntfs-3g](https://github.com/tuxera/ntfs-3g) - NTFS driver with write support

### Installation

1. Install macFUSE and ntfs-3g-mac:

```bash
brew install --cask macfuse
brew install gromgit/fuse/ntfs-3g-mac
```

2. Download `mountfs.sh`:

```bash
curl -O https://raw.githubusercontent.com/guoquan/mountfs/main/mountfs.sh
chmod +x mountfs.sh
```

3. Configure security settings:
   - Trust macFUSE library in Settings → Privacy & Security (signed by "Benjamin Fleischer")
   - Trust ntfs-3g driver (may require a system restart)
   - Grant disk access when prompted

Note: These security settings are required by macOS to allow third-party filesystem drivers. They only need to be configured once.

### Usage

1. **Launch**:
   - Double-click in Finder, or
   - Run in terminal: `./mountfs.sh`

2. **Select Volume**:
   - Choose your NTFS volume in the native file picker
   - Non-NTFS volumes will be automatically rejected

3. **Review & Confirm**:
   - Check volume information
   - Confirm the mount operation

4. **Authenticate**:
   - Enter administrator password in the popup dialog

## Using *mouNT*FS

### Notes

- Requires administrator privileges for mounting
- Performs safe unmount before remounting
- Verifies write access after mounting
- Uses the best available mount method

### Troubleshooting

If mounting fails:

1. Ensure the volume is NTFS formatted
2. Check ntfs-3g installation (if using)
3. Try safely ejecting and reconnecting
4. Check system logs for errors

## Alternatives

- **[Mounty](https://mounty.app/)** - Popular free GUI app for NTFS mounting
- **[NTFS for Mac by Paragon](https://www.paragon-software.com/home/ntfs-mac/)** - Commercial solution with full NTFS support
- **[Tuxera NTFS](https://www.tuxera.com/products/tuxera-ntfs-for-mac/)** - Another commercial driver with high performance
- Feel free to explore other alternatives!

*mouNT*FS focuses on simplicity and native macOS integration while remaining free and open source. We ❤️ open source!

## Information

### Roadmap

- [ ] GUI interface with native macOS look and feel
- [ ] Better error messages and recovery options
- [ ] System tray integration for quick access
- [ ] Volume monitoring for automatic mounting
- [ ] Localization support for multiple languages

### Contribution

Contributions and suggestions are welcome! Feel free to open issues or pull requests.

As a human-AI collaboration project:

- For **code** contributions, please bring your AI buddy and keep the no-direct-human-coding spirit
- For **other** contributions (docs, testing, reviews, etc.), both humans and AI buddies are more than welcome!

Given wide-spread AI concerns, safety review is welcome.

### Contributors

| 🤖 AI | 👤 Humans |
|-------|-----------|
| 💫 [Claude](https://anthropic.com/claude) (3.5 Sonnet, via [Cursor](https://cursor.sh))<br> 🧠 [GPT](https://openai.com/index/gpt-4/) (GPT-4o) | 🐰 [guoquan](https://guoquan.net) |

### License

[MIT License](LICENSE) © 2024 Quan Guo
