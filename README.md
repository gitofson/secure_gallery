# secure_gallery

A Flutter-based encrypted photo gallery app with SMB network share support.

## Features

- **🔒 AES-256 Encryption** — All photos encrypted at rest with securely stored keys
- **👆 Biometric Auth** — Fingerprint/Face ID lock with auto-lock on background
- **📁 Albums** — Organize photos into encrypted albums with anonymous names
- **🌐 SMB Network Galleries** — Browse and import from network shares (read-only)
- **📤 Export** — Decrypt and export to system gallery with original filenames
- **🗂️ Move/Copy** — Flexible import with optional source deletion
- **🎨 Modern UI** — Material Design 3 with dark theme support

## Security

- Photos stored in `/storage/emulated/0/SecureGallery/` (survives uninstall)
- Anonymous file/folder names (HMAC-SHA256 hashes)
- No cloud — everything stays on your device
- Optional biometric lock with blur screen protection

## Tech Stack

Flutter • AES-256 • SMB/CIFS • photo_manager • local_auth • flutter_secure_storage
