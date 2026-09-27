FROM dart:3.13.4

ENV HOME=/workspace \
    PUB_CACHE=/workspace/.pub-cache \
    DART_SUPPRESS_ANALYTICS=true
WORKDIR /workspace

COPY packages/api_contracts/ packages/api_contracts/
COPY apps/server/ apps/server/

WORKDIR /workspace/apps/server
RUN dart pub get --enforce-lockfile && chown -R 10001:10001 /workspace

USER 10001:10001
EXPOSE 8080
CMD ["dart", "run", "bin/server.dart"]
