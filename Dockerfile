FROM alpine:3.23

COPY --chmod=755 refresh.sh /usr/local/bin/refresh.sh

ENV DURATION=60 \
    REFRESH_INTERVAL=45 \
    ENABLE_TCP=true \
    ENABLE_UDP=true \
    MAX_RETRIES=3 \
    RETRY_DELAY=5 \
    MAX_CONSECUTIVE_FAILURES=10

ENTRYPOINT ["/usr/local/bin/refresh.sh"]
