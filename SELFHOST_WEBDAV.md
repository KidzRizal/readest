# Self-host WebDAV untuk Readest (Ubuntu EC2 + domain sendiri)

> Sinkron library (file buku + progress baca + highlight) ke EC2 pribadi via WebDAV.
> Stack: **rclone serve webdav** (backend, ringan) + **Caddy** (HTTPS otomatis).
> Tidak perlu rebuild APK — WebDAV dikonfigurasi runtime di Settings app.

Ganti nilai berikut sesuai punya Anda:
- `read.example.com` → subdomain Anda
- `READEST_PASS` → password kuat pilihan Anda
- User Linux diasumsikan `ubuntu` (default Ubuntu AMI)

---

## A. Sisi AWS (Console)

1. **Elastic IP** — Allocate, lalu Associate ke instance EC2. Tujuannya IP publik
   tidak berubah saat reboot (penting untuk DNS).
2. **Security Group** — inbound rules:
   | Port | Source | Untuk |
   |---|---|---|
   | 22 (SSH) | IP Anda saja | akses admin |
   | 80 (HTTP) | 0.0.0.0/0 | ACME challenge Let's Encrypt |
   | 443 (HTTPS) | 0.0.0.0/0 | WebDAV |
3. **DNS** — di registrar/DNS Anda, buat **A record**:
   `read.example.com` → (Elastic IP EC2). Tunggu propagasi (cek: `nslookup read.example.com`).

---

## B. Install rclone + folder data (di EC2)

```bash
sudo apt update
curl https://rclone.org/install.sh | sudo bash      # rclone versi terbaru
rclone version

# Folder library di disk EBS (default ~30 GB)
sudo mkdir -p /srv/webdav
sudo chown ubuntu:ubuntu /srv/webdav
df -h /srv/webdav                                    # cek sisa ruang
```

---

## C. Jalankan WebDAV sebagai service (systemd)

Buat file `/etc/systemd/system/webdav.service`:

```ini
[Unit]
Description=rclone WebDAV server for Readest
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
ExecStart=/usr/bin/rclone serve webdav /srv/webdav \
  --addr 127.0.0.1:8080 \
  --user readest \
  --pass READEST_PASS
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Aktifkan + uji lokal:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now webdav
sudo systemctl status webdav --no-pager

# Harus balas 207/200, bukan 401/connection refused:
curl -u readest:READEST_PASS http://127.0.0.1:8080/
```

> **Hardening (opsional):** ganti `--user/--pass` dengan `--htpasswd /etc/webdav.htpasswd`
> (bikin dgn `sudo apt install apache2-utils && htpasswd -B -c /etc/webdav.htpasswd readest`)
> supaya password tidak terlihat di `ps`.

---

## D. HTTPS via Caddy

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

Isi `/etc/caddy/Caddyfile` (timpa isinya):

```
read.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

```bash
sudo systemctl reload caddy
sudo journalctl -u caddy -f        # lihat Caddy ambil sertifikat (tunggu "certificate obtained")
```

Uji dari laptop Anda:

```bash
curl -u readest:READEST_PASS https://read.example.com/
```

---

## E. Sisi App Readest

Di app (emulator atau HP): **Settings → Integrations → WebDAV**
- **Enable** WebDAV sync: ON
- **Server URL**: `https://read.example.com`
- **Username**: `readest`
- **Password**: `READEST_PASS`
- **Connect / Test** → harus sukses
- Strategi sync: `silent` (default — push & pull, latest writer wins)

---

## F. Verifikasi sinkron

1. Di app: **Import Books** → pilih satu buku.
2. Buka buku, baca beberapa halaman (memicu push progress, debounce ~15 dtk).
3. Di EC2, cek file muncul:
   ```bash
   ls -R /srv/webdav/Readest/books/ | head
   ```
   Akan ada folder `Readest/books/<hash>/` berisi `config.json`, file buku, dan cover.

Struktur di server: `<rootPath>/Readest/books/<hash>/config.json` + file buku + cover.

---

## Troubleshooting

| Gejala | Cek |
|---|---|
| App "connection failed" | DNS sudah arah ke Elastic IP? `nslookup read.example.com`. Port 443 open di Security Group? |
| Caddy gagal ambil sertifikat | Port 80 harus open ke 0.0.0.0/0 untuk ACME. Lihat `journalctl -u caddy` |
| 401 Unauthorized | Username/password di app != yang di `webdav.service` |
| Upload buku gagal/lambat | Cek sisa disk `df -h`; instance 1 GB RAM upload besar bisa lambat tapi tetap jalan |
| Mau ganti port internal | rclone `--addr 127.0.0.1:PORT` + sesuaikan `reverse_proxy` di Caddyfile |
