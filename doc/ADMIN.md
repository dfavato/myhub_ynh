## Admin documentation

- Install directory: `__INSTALL_DIR__`
- Data directory: `__DATA_DIR__`
- Dashboard generated at: `__INSTALL_DIR__/index.html`
- Generation script: `__INSTALL_DIR__/generate.sh`
- Data files (weather, sports): stored in `__DATA_DIR__/`
- Systemd timer: `${__ID__}-generate.timer` (runs daily at 5:00 AM)
- Weather API: Open-Meteo (free, no key needed)
- Sports API: API-Football (requires API key, optional)

To manually trigger dashboard generation:

```bash
sudo -u __ID__ __INSTALL_DIR__/generate.sh
```

To check timer status:

```bash
systemctl status __ID__-generate.timer
```
