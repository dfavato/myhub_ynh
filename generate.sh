#!/bin/bash

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ID="$(basename "$APP_DIR")"
DATA_DIR="/home/yunohost.app/$APP_ID"

# API endpoints
OPEN_METEO_WEATHER_URL="https://api.open-meteo.com/v1/forecast"
API_FOOTBALL_URL="https://v3.football.api-sports.io"

# Sports team IDs
CRUZEIRO_TEAM_ID="1967"
SELECAO_TEAM_ID="1227"

# Read settings
SETTINGS_FILE="/etc/yunohost/apps/$APP_ID/settings.yml"
if [ -f "$SETTINGS_FILE" ]; then
    CITY_LAT=$(grep '^city_lat:' "$SETTINGS_FILE" | awk '{print $2}' | tr -d '"')
    CITY_LON=$(grep '^city_lon:' "$SETTINGS_FILE" | awk '{print $2}' | tr -d '"')
    CITY_NAME=$(grep '^city_resolved_name:' "$SETTINGS_FILE" | awk '{print $2}' | tr -d '"')
    API_FOOTBALL_KEY=$(grep '^api_football_key:' "$SETTINGS_FILE" | awk '{print $2}' | tr -d '"')
else
    echo "ERROR: Settings file not found"
    exit 1
fi

TODAY=$(date +%Y-%m-%d)
TODAY_COMPACT=$(date +%Y%m%d)

#=================================================
# WEATHER
#=================================================

echo "Fetching weather data..."

WEATHER_DIR="$DATA_DIR/weather"
mkdir -p "$WEATHER_DIR/summaries"

WEATHER_JSON="$WEATHER_DIR/${TODAY}.json"

curl -sf "${OPEN_METEO_WEATHER_URL}?latitude=${CITY_LAT}&longitude=${CITY_LON}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,sunrise,sunset&timezone=auto&forecast_days=3" \
    -o "$WEATHER_JSON" 2>/dev/null

if [ ! -s "$WEATHER_JSON" ]; then
    echo "WARNING: Failed to fetch weather data"
fi

# Generate weather summary with opencode
SUMMARY_FILE="$WEATHER_DIR/summaries/${TODAY_COMPACT}.txt"

if [ -s "$WEATHER_JSON" ] && command -v opencode &>/dev/null; then
    echo "Generating weather summary with opencode..."

    WEATHER_PROMPT="You are a weather summarizer. Given the following weather JSON for $CITY_NAME, produce a short HTML snippet (no <html> or <body> tags, just inner content). Include:
1. A brief natural-language summary of today's weather (2-3 sentences)
2. A tips/alerts section with colored boxes (use inline CSS) for things like: high UV, rain expected, extreme heat/cold, strong winds

Rules:
- Use inline CSS for styling (no external stylesheets)
- Output ONLY the HTML snippet, nothing else
- Keep it concise
- Use Portuguese language

Weather JSON:
$(cat "$WEATHER_JSON")"

    echo "$WEATHER_PROMPT" | opencode --model big-pickle --quiet > "$SUMMARY_FILE" 2>/dev/null || true

    if [ -s "$SUMMARY_FILE" ]; then
        echo "Weather summary generated"
    else
        echo "WARNING: opencode failed to generate weather summary"
    fi
else
    echo "Skipping weather summary (no data or opencode not available)"
fi

#=================================================
# SPORTS
#=================================================

if [ -n "$API_FOOTBALL_KEY" ] && [ "$API_FOOTBALL_KEY" != "null" ]; then
    echo "Fetching sports data..."

    SPORTS_DIR="$DATA_DIR/sports"
    mkdir -p "$SPORTS_DIR/$CRUZEIRO_TEAM_ID" "$SPORTS_DIR/$SELECAO_TEAM_ID"

    for TEAM_ID in "$CRUZEIRO_TEAM_ID" "$SELECAO_TEAM_ID"; do
        TEAM_DIR="$SPORTS_DIR/$TEAM_ID"
        TEAM_JSON="$TEAM_DIR/${TODAY}.json"

        # Get last 5 matches for the team
        curl -sf "${API_FOOTBALL_URL}/fixtures?team=${TEAM_ID}&last=5" \
            -H "x-apisports-key: ${API_FOOTBALL_KEY}" \
            -o "$TEAM_JSON" 2>/dev/null || true

        if [ ! -s "$TEAM_JSON" ]; then
            echo "WARNING: Failed to fetch sports data for team $TEAM_ID"
        else
            echo "Fetched data for team $TEAM_ID"
        fi

        # Keep only last 14 days of sports data
        find "$TEAM_DIR" -name "*.json" -mtime +14 -delete 2>/dev/null || true
    done
else
    echo "No API-Football key configured, skipping sports section"
fi

#=================================================
# ASSEMBLE HTML
#=================================================

echo "Assembling index.html..."

TODAY_HUMAN=$(date +"%A, %B %d, %Y")
TODAY_HUMAN_PT=$(date +"%d/%m/%Y")

# Build weather section
WEATHER_SECTION=""
if [ -s "$WEATHER_JSON" ]; then
    CURRENT_TEMP=$(jq -r '.current.temperature_2m // "N/A"' "$WEATHER_JSON" 2>/dev/null)
    CURRENT_FEELS=$(jq -r '.current.apparent_temperature // "N/A"' "$WEATHER_JSON" 2>/dev/null)
    CURRENT_HUMIDITY=$(jq -r '.current.relative_humidity_2m // "N/A"' "$WEATHER_JSON" 2>/dev/null)
    CURRENT_WIND=$(jq -r '.current.wind_speed_10m // "N/A"' "$WEATHER_JSON" 2>/dev/null)
    WEATHER_CODE=$(jq -r '.current.weather_code // 0' "$WEATHER_JSON" 2>/dev/null)

    # Decode weather code to emoji and description
    case "$WEATHER_CODE" in
        0) WICON="☀️"; WDESC="Céu limpo" ;;
        1|2|3) WICON="⛅"; WDESC="Parcialmente nublado" ;;
        45|48) WICON="🌫️"; WDESC="Nevoeiro" ;;
        51|53|55) WICON="🌦️"; WDESC="Chuvisco" ;;
        61|63|65) WICON="🌧️"; WDESC="Chuva" ;;
        71|73|75) WICON="🌨️"; WDESC="Neve" ;;
        80|81|82) WICON="⛈️"; WDESC="Chuva forte" ;;
        95|96|99) WICON="⛈️"; WDESC="Tempestade" ;;
        *) WICON="🌡️"; WDESC="N/A" ;;
    esac

    # Daily forecast
    DAILY_HTML=""
    for i in 0 1 2; do
        D_DATE=$(jq -r ".daily.time[$i] // empty" "$WEATHER_JSON" 2>/dev/null)
        D_MAX=$(jq -r ".daily.temperature_2m_max[$i] // empty" "$WEATHER_JSON" 2>/dev/null)
        D_MIN=$(jq -r ".daily.temperature_2m_min[$i] // empty" "$WEATHER_JSON" 2>/dev/null)
        D_RAIN=$(jq -r ".daily.precipitation_probability_max[$i] // 0" "$WEATHER_JSON" 2>/dev/null)

        if [ -n "$D_DATE" ]; then
            D_DAY=$(date -d "$D_DATE" +"%a" 2>/dev/null || echo "")
            DAILY_HTML="${DAILY_HTML}
            <div class=\"forecast-day\">
                <div class=\"forecast-date\">${D_DAY}</div>
                <div class=\"forecast-temp\">${D_MIN}° / ${D_MAX}°</div>
                <div class=\"forecast-rain\">💧 ${D_RAIN}%</div>
            </div>"
        fi
    done

    # Read summary
    SUMMARY_HTML=""
    if [ -s "$SUMMARY_FILE" ]; then
        SUMMARY_HTML="<div class=\"weather-summary\">$(cat "$SUMMARY_FILE")</div>"
    fi

    WEATHER_SECTION="
    <section class=\"card weather-card\">
        <h2>🌤️ Clima em ${CITY_NAME:-Cidade}</h2>
        <div class=\"weather-current\">
            <div class=\"weather-icon\">${WICON}</div>
            <div class=\"weather-info\">
                <div class=\"weather-temp\">${CURRENT_TEMP}°C</div>
                <div class=\"weather-desc\">${WDESC}</div>
                <div class=\"weather-details\">
                    <span>Sensação: ${CURRENT_FEELS}°C</span>
                    <span>Umidade: ${CURRENT_HUMIDITY}%</span>
                    <span>Vento: ${CURRENT_WIND} km/h</span>
                </div>
            </div>
        </div>
        <div class=\"weather-forecast\">${DAILY_HTML}</div>
        ${SUMMARY_HTML}
    </section>"
else
    WEATHER_SECTION="<section class=\"card\"><h2>🌤️ Clima</h2><p>Dados meteorológicos não disponíveis.</p></section>"
fi

# Build sports section
SPORTS_SECTION=""

if [ -n "$API_FOOTBALL_KEY" ] && [ "$API_FOOTBALL_KEY" != "null" ]; then
    # Cruzeiro matches
    CRUZEIRO_HTML=""
    CRUZEIRO_JSON="$DATA_DIR/sports/$CRUZEIRO_TEAM_ID/${TODAY}.json"

    if [ -s "$CRUZEIRO_JSON" ]; then
        MATCHES=$(jq -r '.response[]? | "<div class=\"match\">\(.fixture.date | split("T")[0]) - \(.teams.home.name) \(.goals.home // "-") x \(.goals.away // "-") \(.teams.away.name)</div>"' "$CRUZEIRO_JSON" 2>/dev/null || echo "")
        if [ -n "$MATCHES" ]; then
            CRUZEIRO_HTML="$MATCHES"
        else
            CRUZEIRO_HTML="<p class=\"no-matches\">Nenhum jogo recente encontrado.</p>"
        fi
    else
        CRUZEIRO_HTML="<p class=\"no-matches\">Dados não disponíveis.</p>"
    fi

    # Seleção matches
    SELECAO_HTML=""
    SELECAO_JSON="$DATA_DIR/sports/$SELECAO_TEAM_ID/${TODAY}.json"

    if [ -s "$SELECAO_JSON" ]; then
        MATCHES=$(jq -r '.response[]? | "<div class=\"match\">\(.fixture.date | split("T")[0]) - \(.teams.home.name) \(.goals.home // "-") x \(.goals.away // "-") \(.teams.away.name)</div>"' "$SELECAO_JSON" 2>/dev/null || echo "")
        if [ -n "$MATCHES" ]; then
            SELECAO_HTML="$MATCHES"
        else
            SELECAO_HTML="<p class=\"no-matches\">Nenhum jogo recente encontrado.</p>"
        fi
    else
        SELECAO_HTML="<p class=\"no-matches\">Dados não disponíveis.</p>"
    fi

    SPORTS_SECTION="
    <section class=\"card sports-card\">
        <h2>⚽ Esportes</h2>
        <div class=\"team-section\">
            <h3>🔵⚪ Cruzeiro</h3>
            <div class=\"matches\">${CRUZEIRO_HTML}</div>
        </div>
        <div class=\"team-section\">
            <h3>🟡🟢 Seleção Brasileira</h3>
            <div class=\"matches\">${SELECAO_HTML}</div>
        </div>
    </section>"
else
    SPORTS_SECTION=""
fi

# Assemble full page
cat > "$APP_DIR/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MyHub - Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f0f1a;
            color: #e0e0e0;
            min-height: 100vh;
            padding: 20px;
        }
        .header {
            text-align: center;
            padding: 30px 0;
        }
        .header h1 {
            font-size: 2.5rem;
            color: #fff;
            margin-bottom: 5px;
        }
        .header .date {
            color: #888;
            font-size: 1.1rem;
        }
        .dashboard {
            max-width: 900px;
            margin: 0 auto;
            display: flex;
            flex-direction: column;
            gap: 24px;
        }
        .card {
            background: #1a1a2e;
            border-radius: 16px;
            padding: 28px;
            border: 1px solid #2a2a4a;
            box-shadow: 0 4px 20px rgba(0,0,0,0.3);
        }
        .card h2 {
            font-size: 1.4rem;
            margin-bottom: 20px;
            color: #fff;
            border-bottom: 2px solid #2a2a4a;
            padding-bottom: 12px;
        }
        .card h3 {
            font-size: 1.1rem;
            margin: 16px 0 10px;
            color: #ccc;
        }

        /* Weather */
        .weather-current {
            display: flex;
            align-items: center;
            gap: 24px;
            margin-bottom: 20px;
        }
        .weather-icon { font-size: 4rem; }
        .weather-temp { font-size: 2.8rem; font-weight: 700; color: #fff; }
        .weather-desc { font-size: 1.2rem; color: #aaa; margin: 4px 0; }
        .weather-details {
            display: flex;
            gap: 16px;
            flex-wrap: wrap;
            font-size: 0.9rem;
            color: #888;
        }
        .weather-forecast {
            display: flex;
            gap: 12px;
            margin-top: 16px;
        }
        .forecast-day {
            background: #16162a;
            border-radius: 10px;
            padding: 12px 16px;
            text-align: center;
            flex: 1;
        }
        .forecast-date { font-weight: 600; color: #aaa; text-transform: uppercase; }
        .forecast-temp { font-size: 1.1rem; color: #fff; margin: 6px 0; }
        .forecast-rain { font-size: 0.85rem; color: #6aa3ff; }

        /* Weather summary tips */
        .weather-summary { margin-top: 16px; }
        .weather-summary .alert-box, .weather-summary .tip-box {
            border-radius: 10px;
            padding: 14px 18px;
            margin-top: 10px;
            font-size: 0.95rem;
            line-height: 1.5;
        }
        .weather-summary .alert-box { background: #2d1b1b; border-left: 4px solid #ff6b6b; color: #ffb3b3; }
        .weather-summary .tip-box { background: #1b2d1b; border-left: 4px solid #6bff6b; color: #b3ffb3; }

        /* Sports */
        .team-section { margin-bottom: 16px; }
        .match {
            background: #16162a;
            border-radius: 8px;
            padding: 10px 14px;
            margin-top: 8px;
            font-size: 0.95rem;
        }
        .no-matches { color: #666; font-style: italic; margin-top: 8px; }

        /* Responsive */
        @media (max-width: 600px) {
            body { padding: 12px; }
            .header h1 { font-size: 1.8rem; }
            .weather-current { flex-direction: column; text-align: center; }
            .weather-forecast { flex-direction: column; }
            .weather-details { justify-content: center; }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>MyHub</h1>
        <div class="date">${TODAY_HUMAN_PT} - ${CITY_NAME:-Dashboard}</div>
    </div>
    <div class="dashboard">
        ${WEATHER_SECTION}
        ${SPORTS_SECTION}
    </div>
</body>
</html>
HTMLEOF

echo "Dashboard generated: $APP_DIR/index.html"
