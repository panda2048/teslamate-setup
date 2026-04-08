# TeslaMate + Cloudflare Tunnel - One-Click Setup

Simple and secure way to run TeslaMate on Google Cloud Free Tier using Cloudflare Tunnel.

### Features
- Fully automated setup using single startup script
- Uses Cloudflare Tunnel (no open ports, more secure)
- Includes Grafana
- Safe to reboot (setup runs only once)
- Lightweight for e2-micro

### How to Use (Very Simple)

#### Step 1: Create Cloudflare Tunnel (Do this first)
1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com)
2. Networks → Connectors → Create a tunnel
3. Name it `teslamate`
4. Copy the **Tunnel Token** (long random string)

#### Step 2: Create Google Cloud VM
1. Go to Google Cloud Console → Compute Engine → VM instances → Create Instance
2. Set these exact values:
   - **Region**: `us-west1` (must be this for free tier)
   - **Machine type**: `e2-micro`
   - **Boot disk**: Debian 12, **Standard persistent disk**, 30 GB
   - **Firewall**: Check **Allow HTTP traffic** (Cloudflare Tunnel will handle access)
3. In **Advanced options** → **Management** → **Automation**, paste this one line in **Startup script**:

```bash
curl -sSL https://raw.githubusercontent.com/panda2048/teslamate-setup/main/setup.sh | TUNNEL_TOKEN=your-actual-token-here bash
