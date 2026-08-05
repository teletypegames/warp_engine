FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  default-libmysqlclient-dev \
  git \
  tzdata \
  libyaml-dev \
  pkg-config \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# The app source, the engine checkout (/warp_engine) and the bundle are all
# mounted at runtime by the compose file; the entrypoint bundles on first boot.
ENTRYPOINT ["./bin/docker-entrypoint"]

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
