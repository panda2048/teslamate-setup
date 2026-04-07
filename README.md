# TeslaMate on Google Cloud Free Tier (HTTPS + Password)

**Super simple** — just change your email in one line.

### Steps

1. Create VM:
   - Region: **us-west1**
   - Machine type: **e2-micro**
   - Boot disk: **Debian 12**, **Standard persistent disk**, **30 GB**
   - Firewall: Check **Allow HTTP traffic**

2. In **Startup script** box, paste this **one line** and **change your email**:

   ```bash
   curl -sSL https://raw.githubusercontent.com/panda2048/teslamate-setup/main/teslamate-setup.sh | USER_EMAIL=your-email@gmail.com bash
