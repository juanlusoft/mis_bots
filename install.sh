#!/usr/bin/env bash
set -euo pipefail

# === utilidades ===
color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }           # 31 rojo, 32 verde, 33 amarillo, 36 cian
ask() { # ask "Pregunta" "valor_por_defecto" -> responde por echo
  local q="$1" def="${2:-}" ans
  if [[ -n "$def" ]]; then
    read -r -p "$(color 36 "$q") [${def}]: " ans || true
    echo "${ans:-$def}"
  else
    read -r -p "$(color 36 "$q"): " ans || true
    echo "$ans"
  fi
}
ask_secret() { # pregunta oculta
  local q="$1" def="${2:-}" ans
  if [[ -n "$def" ]]; then
    read -r -s -p "$(color 36 "$q") [oculto] " ans || true; echo
    echo "${ans:-$def}"
  else
    read -r -s -p "$(color 36 "$q") [oculto] " ans || true; echo
    echo "$ans"
  fi
}

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# === comprobar docker/compose ===
if ! command -v docker >/dev/null 2>&1; then
  color 31 "ERROR: Docker no está instalado.\n"
  echo "Instálalo y vuelve a ejecutar este script. Ej.:"
  echo "  curl -fsSL https://get.docker.com | sh"
  exit 1
fi
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose -f ${repo_root}/docker-compose.yml"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose -f ${repo_root}/docker-compose.yml"
else
  color 31 "ERROR: docker compose no disponible.\n"
  echo "Instala el plugin 'docker compose' o 'docker-compose'."
  exit 1
fi

# === lee valores previos si existe .env ===
get_env() { # get_env CLAVE -> valor_actual (si existe en .env)
  [[ -f .env ]] || { echo ""; return; }
  awk -F= -v k="$1" '$1==k{ $1=""; sub(/^=/,""); print; }' .env
}

# === preguntas ===
echo
color 33 "Configuración del Plex Bot\n"
echo "Deja vacío para usar el valor por defecto entre corchetes."

# Plex
PLEX_URL_DEF="$(get_env PLEX_URL)"
PLEX_URL="$(ask "PLEX_URL (http://IP:32400)" "${PLEX_URL_DEF:-http://192.168.1.4:32400}")"
# normaliza
[[ "$PLEX_URL" =~ ^https?:// ]] || PLEX_URL="http://${PLEX_URL}"

PLEX_TOKEN_DEF="$(get_env PLEX_TOKEN)"
PLEX_TOKEN="$(ask_secret "PLEX_TOKEN" "${PLEX_TOKEN_DEF:-}")"

# Telegram
TELEGRAM_BOT_TOKEN_DEF="$(get_env TELEGRAM_BOT_TOKEN)"
TELEGRAM_BOT_TOKEN="$(ask_secret "TELEGRAM_BOT_TOKEN" "${TELEGRAM_BOT_TOKEN_DEF:-}")"

TELEGRAM_ALLOWED_IDS_DEF="$(get_env TELEGRAM_ALLOWED_IDS)"
TELEGRAM_ALLOWED_IDS="$(ask "TELEGRAM_ALLOWED_IDS (IDs separados por coma, o vacío para permitir a cualquiera)" "${TELEGRAM_ALLOWED_IDS_DEF:-}")"

TELEGRAM_NOTIFY_CHAT_ID_DEF="$(get_env TELEGRAM_NOTIFY_CHAT_ID)"
TELEGRAM_NOTIFY_CHAT_ID="$(ask "TELEGRAM_NOTIFY_CHAT_ID (chat al que notificar novedades)" "${TELEGRAM_NOTIFY_CHAT_ID_DEF:-${TELEGRAM_ALLOWED_IDS%%,*}}")"

# Idioma / servidor HTTP
DEFAULT_LANG_DEF="$(get_env DEFAULT_LANG)"
DEFAULT_LANG="$(ask "DEFAULT_LANG" "${DEFAULT_LANG_DEF:-es}")"

HOST_DEF="$(get_env HOST)"
HOST="$(ask "HOST" "${HOST_DEF:-0.0.0.0}")"

PORT_DEF="$(get_env PORT)"
PORT="$(ask "PORT" "${PORT_DEF:-8080}")"

# TMDB
TMDB_API_KEY_DEF="$(get_env TMDB_API_KEY)"
TMDB_API_KEY="$(ask_secret "TMDB_API_KEY (opcional, para trailers)" "${TMDB_API_KEY_DEF:-}")"

TMDB_LANGUAGE_DEF="$(get_env TMDB_LANGUAGE)"
TMDB_LANGUAGE="$(ask "TMDB_LANGUAGE" "${TMDB_LANGUAGE_DEF:-es-ES}")"

TMDB_REGION_DEF="$(get_env TMDB_REGION)"
TMDB_REGION="$(ask "TMDB_REGION" "${TMDB_REGION_DEF:-ES}")"

# Base de datos (persistente dentro de ./data)
DATABASE_URL_DEF="$(get_env DATABASE_URL)"
DATABASE_URL="${DATABASE_URL_DEF:-sqlite:///data/data.db}"

echo
color 33 "Resumen:\n"
cat <<SUM
PLEX_URL                = $PLEX_URL
PLEX_TOKEN              = ${PLEX_TOKEN:+(oculto)}
TELEGRAM_BOT_TOKEN      = ${TELEGRAM_BOT_TOKEN:+(oculto)}
TELEGRAM_ALLOWED_IDS    = ${TELEGRAM_ALLOWED_IDS:-<libre>}
TELEGRAM_NOTIFY_CHAT_ID = ${TELEGRAM_NOTIFY_CHAT_ID:-<vacío>}
DEFAULT_LANG            = $DEFAULT_LANG
HOST:PORT               = $HOST:$PORT
TMDB_API_KEY            = ${TMDB_API_KEY:+(oculto)}
TMDB_LANGUAGE/REGION    = $TMDB_LANGUAGE / $TMDB_REGION
DATABASE_URL            = $DATABASE_URL
SUM
echo
read -r -p "$(color 36 "¿Crear/actualizar .env con estos valores y lanzar el contenedor? [S/n]") " cont || true
cont="${cont:-S}"
if [[ ! "$cont" =~ ^[sS]$ ]]; then
  color 33 "Cancelado.\n"; exit 0
fi

# === escribir .env ===
mkdir -p data
cat > .env <<EOF
# === Plex ===
PLEX_URL=$PLEX_URL
PLEX_TOKEN=$PLEX_TOKEN

# === Telegram ===
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_ALLOWED_IDS=$TELEGRAM_ALLOWED_IDS
TELEGRAM_NOTIFY_CHAT_ID=$TELEGRAM_NOTIFY_CHAT_ID

# === Idioma ===
DEFAULT_LANG=$DEFAULT_LANG

# === Servidor HTTP ===
HOST=$HOST
PORT=$PORT

# === TMDB ===
TMDB_API_KEY=$TMDB_API_KEY
TMDB_LANGUAGE=$TMDB_LANGUAGE
TMDB_REGION=$TMDB_REGION

# === Base de datos ===
DATABASE_URL=$DATABASE_URL
EOF

color 32 "✅ .env creado/actualizado\n"

# === levantar docker ===
$COMPOSE up -d --build
color 32 "✅ Contenedor desplegado\n"

# === probar health ===
sleep 1
if command -v curl >/dev/null 2>&1; then
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    color 32 "✅ /health responde correctamente en puerto ${PORT}\n"
  else
    color 33 "⚠ No se pudo contactar /health en 127.0.0.1:${PORT}. Revisa 'docker logs -f plex-bot'\n"
  fi
else
  color 33 "⚠ curl no está instalado; no se pudo probar /health\n"
fi

echo
echo "Comandos útiles:"
echo "  docker logs -f plex-bot"
echo "  docker ps --format 'table {{.Names}}\t{{.Ports}}'"
echo
echo "Telegram: /help  |  /novedades  |  /actualizar  |  /invitar"
