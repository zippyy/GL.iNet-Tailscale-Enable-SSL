# GL.iNet Tailscale SSL Enabler

Helper scripts to install **Tailscale-issued HTTPS certificates** on:

- **GL.iNet routers** (nginx on port 443)
- **GL-KVM devices** (kvmd)

This lets you access your device securely using its **Tailnet FQDN**
(e.g. `device-name.tailnet.ts.net`) with a trusted certificate instead of the
default self-signed Cert.

> ⚠️ **Important**
> - This is a **manual process**
> - You must re-run the script about **every 90 days** to renew the cert OR Setup a cronjob or service etc...
> - The certificate will only validate for the **Tailnet hostname**, not the LAN IP
> - You must have HTTPS enabled in your tailnet admin settings
> - You must be using an up to date tailscale version, this works on both routers and kvm thanks to [Admon](https://github.com/admonstrator/glinet-tailscale-updater): ```bash wget -q https://get.admon.me/tailscale -O update-tailscale.sh ; sh update-tailscale.sh ```

---

## What this repo does

Each script:

1. Detects the device’s **Tailnet domain**
2. Runs `tailscale cert <domain>` to generate / refresh cert files
3. Backs up the existing HTTPS certs
4. Installs the Tailscale cert into the correct service
5. Restarts the service safely
6. Verifies the cert is actually being served

The scripts are:
- **GL.iNET/OpenWrt safe**
- Tested on real hardware

---

## Supported devices (Tested Devices)

### Routers
- Flint 3 (GL-BE9300)
- Slate 7 (GL-BE3600)
- Puli AX (GL-XE3000)
- Other GL.iNet routers using nginx for HTTPS should work

### KVM
- GL-RM1 (kvmd)
- Other GLKVM devices using kvmd should work

---

### KVM Script

****Run the updater without cloning the repository:****

```bash
wget -q https://raw.githubusercontent.com/zippyy/GL.iNet-Tailscale-Enable-SSL/main/tailscale-ssl-kvm.sh -O tailscale-ssl-kvm.sh ; sh tailscale-ssl-kvm.sh
```

## Router Script 

****Run the updater without cloning the repository:****

```bash
wget -q https://raw.githubusercontent.com/zippyy/GL.iNet-Tailscale-Enable-SSL/main/tailscale-ssl-router.sh -O tailscale-ssl-router.sh ; sh tailscale-ssl-router.sh
```
