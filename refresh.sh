#!/bin/sh
set -e

# Helper function to normalize boolean values
normalize_bool() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) echo "true" ;;
    *) echo "false" ;;
  esac
}

# Helper function to validate integer
is_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Helper function to validate port number
is_valid_port() {
  is_integer "$1" && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# Validate required environment variables
: "${NATPMP_SERVICE:?NATPMP_SERVICE environment variable is required (e.g., natpmp-service:8080)}"
: "${INTERNAL_PORT:?INTERNAL_PORT environment variable is required (e.g., 6881)}"
: "${DURATION:=60}"
: "${REFRESH_INTERVAL:=45}"
: "${ENABLE_TCP:=true}"
: "${ENABLE_UDP:=true}"
: "${MAX_RETRIES:=3}"
: "${RETRY_DELAY:=5}"
: "${MAX_CONSECUTIVE_FAILURES:=10}"

# Validate INTERNAL_PORT
if ! is_valid_port "$INTERNAL_PORT"; then
  echo "Error: INTERNAL_PORT must be a valid port number (1-65535), got: $INTERNAL_PORT"
  exit 1
fi

# Validate DURATION
if ! is_integer "$DURATION" || [ "$DURATION" -le 0 ]; then
  echo "Error: DURATION must be a positive integer, got: $DURATION"
  exit 1
fi

# Validate REFRESH_INTERVAL
if ! is_integer "$REFRESH_INTERVAL" || [ "$REFRESH_INTERVAL" -le 0 ]; then
  echo "Error: REFRESH_INTERVAL must be a positive integer, got: $REFRESH_INTERVAL"
  exit 1
fi

# Validate timing: REFRESH_INTERVAL must be less than DURATION
if [ "$REFRESH_INTERVAL" -ge "$DURATION" ]; then
  echo "Error: REFRESH_INTERVAL ($REFRESH_INTERVAL) must be less than DURATION ($DURATION)"
  echo "Recommended: REFRESH_INTERVAL should be ~75% of DURATION"
  exit 1
fi

# Validate MAX_RETRIES
if ! is_integer "$MAX_RETRIES" || [ "$MAX_RETRIES" -lt 0 ]; then
  echo "Error: MAX_RETRIES must be a non-negative integer, got: $MAX_RETRIES"
  exit 1
fi

# Validate RETRY_DELAY
if ! is_integer "$RETRY_DELAY" || [ "$RETRY_DELAY" -lt 0 ]; then
  echo "Error: RETRY_DELAY must be a non-negative integer, got: $RETRY_DELAY"
  exit 1
fi

# Validate MAX_CONSECUTIVE_FAILURES
if ! is_integer "$MAX_CONSECUTIVE_FAILURES" || [ "$MAX_CONSECUTIVE_FAILURES" -le 0 ]; then
  echo "Error: MAX_CONSECUTIVE_FAILURES must be a positive integer, got: $MAX_CONSECUTIVE_FAILURES"
  exit 1
fi

# Normalize boolean values
ENABLE_TCP=$(normalize_bool "$ENABLE_TCP")
ENABLE_UDP=$(normalize_bool "$ENABLE_UDP")

# Optional API token for authentication
if [ -n "$API_TOKEN" ]; then
  AUTH_HEADER="Authorization: Bearer $API_TOKEN"
  echo "Using Bearer token authentication"
else
  AUTH_HEADER=""
  echo "Warning: No API_TOKEN set - running without authentication"
fi

# Build protocol list based on flags
PROTOCOLS=""
if [ "$ENABLE_TCP" = "true" ]; then
  PROTOCOLS="tcp"
fi
if [ "$ENABLE_UDP" = "true" ]; then
  PROTOCOLS="${PROTOCOLS:+$PROTOCOLS }udp"
fi

# Ensure at least one protocol is enabled
if [ -z "$PROTOCOLS" ]; then
  echo "Error: At least one protocol must be enabled (ENABLE_TCP or ENABLE_UDP)"
  exit 1
fi

# Graceful shutdown handler
shutdown() {
  echo ""
  echo "Received shutdown signal, exiting gracefully..."
  exit 0
}
trap shutdown TERM INT

# Initialize consecutive failure counter
CONSECUTIVE_FAILURES=0

echo "Starting NAT-PMP refresh service..."
echo "Service: http://${NATPMP_SERVICE}/forward"
echo "Internal Port: ${INTERNAL_PORT}"
echo "Protocols: ${PROTOCOLS}"
echo "Duration: ${DURATION}s"
echo "Refresh Interval: ${REFRESH_INTERVAL}s"
echo "Max Retries: ${MAX_RETRIES}"
echo "Retry Delay: ${RETRY_DELAY}s"
echo "Max Consecutive Failures: ${MAX_CONSECUTIVE_FAILURES}"
echo ""

while true; do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Requesting NAT-PMP port mappings for port ${INTERNAL_PORT}..."

  REQUEST_SUCCESS=false

  for protocol in $PROTOCOLS; do
    echo "  → ${protocol} mapping..."

    # Build request data
    BODY_DATA="{\"internal_port\": ${INTERNAL_PORT}, \"protocol\": \"${protocol}\", \"duration\": ${DURATION}}"

    # Retry loop for this protocol
    PROTOCOL_SUCCESS=false
    for attempt in $(seq 0 $MAX_RETRIES); do
      if [ "$attempt" -gt 0 ]; then
        echo "    Retry attempt $attempt/$MAX_RETRIES after ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
      fi

      # Create temp file for headers
      TEMP_HEADERS=$(mktemp)

      # Make request with server response headers
      if [ -n "$AUTH_HEADER" ]; then
        RESPONSE=$(wget -q -S -O- --timeout=30 \
          --header='Content-Type: application/json' \
          --header="$AUTH_HEADER" \
          --post-data="$BODY_DATA" \
          "http://${NATPMP_SERVICE}/forward" 2>"$TEMP_HEADERS" || true)
      else
        RESPONSE=$(wget -q -S -O- --timeout=30 \
          --header='Content-Type: application/json' \
          --post-data="$BODY_DATA" \
          "http://${NATPMP_SERVICE}/forward" 2>"$TEMP_HEADERS" || true)
      fi

      # Extract HTTP status code from headers (get last occurrence for redirects)
      HTTP_CODE=$(grep -o "HTTP/[0-9\.]* [0-9]*" "$TEMP_HEADERS" 2>/dev/null | tail -1 | grep -oE "[0-9]+$" || echo "000")
      rm -f "$TEMP_HEADERS"

      # Ensure HTTP_CODE is not empty (defense in depth)
      HTTP_CODE=${HTTP_CODE:-000}

      # Check if request was successful (2xx status codes)
      if [ "$HTTP_CODE" -ge 200 ] 2>/dev/null && [ "$HTTP_CODE" -lt 300 ] 2>/dev/null; then
        echo "  ✓ ${protocol} mapping successful: $RESPONSE"
        PROTOCOL_SUCCESS=true
        REQUEST_SUCCESS=true
        break
      else
        if [ "$HTTP_CODE" = "000" ]; then
          echo "  ✗ ${protocol} mapping failed: Network error or timeout"
        else
          echo "  ✗ ${protocol} mapping failed (HTTP ${HTTP_CODE}): $RESPONSE"
        fi
      fi
    done

    # If all retries failed for this protocol
    if [ "$PROTOCOL_SUCCESS" = "false" ]; then
      echo "  ✗ ${protocol} mapping failed after $MAX_RETRIES retries"
    fi
  done

  # Update consecutive failure counter
  if [ "$REQUEST_SUCCESS" = "true" ]; then
    CONSECUTIVE_FAILURES=0
  else
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    echo "  ⚠ All protocols failed. Consecutive failures: ${CONSECUTIVE_FAILURES}/${MAX_CONSECUTIVE_FAILURES}"

    # Check if max consecutive failures reached
    if [ "$CONSECUTIVE_FAILURES" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
      echo ""
      echo "ERROR: Reached maximum consecutive failures (${MAX_CONSECUTIVE_FAILURES})"
      echo "Exiting due to persistent connectivity issues. Please check:"
      echo "  - NAT-PMP service is running and accessible"
      echo "  - Network connectivity is stable"
      echo "  - API token is valid (if using authentication)"
      exit 1
    fi
  fi

  echo "  Sleeping ${REFRESH_INTERVAL}s until next renewal..."
  echo ""
  sleep "$REFRESH_INTERVAL"
done
