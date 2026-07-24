#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

myhub_data_dir="/home/yunohost.app/$app"

# Sports team IDs
CRUZEIRO_TEAM_ID="1967"
SELECAO_TEAM_ID="1227"

# API endpoints
OPEN_METEO_GEOCODING_URL="https://geocoding-api.open-meteo.com/v1/search"
OPEN_METEO_WEATHER_URL="https://api.open-meteo.com/v1/forecast"
API_FOOTBALL_URL="https://v3.football.api-sports.io"

# Get a setting value with a default
myhub_setting_get() {
    local key="$1"
    local default="$2"
    local value
    value=$(yunohost app setting get "$app" "$key" 2>/dev/null) || true
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}
