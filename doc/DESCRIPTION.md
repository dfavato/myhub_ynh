MyHub is a personal daily dashboard that displays:

- **Weather**: Current conditions and 3-day forecast powered by Open-Meteo, with AI-generated weather tips and alerts.
- **Sports**: Recent match results for Cruzeiro and Seleção Brasileira, powered by API-Football (optional).

A daily cron job (systemd timer) generates a static HTML page at 5:00 AM. The page uses a dark theme with responsive mobile layout.

No database, no PHP, no web server daemon — just a static HTML file served by NGINX.
