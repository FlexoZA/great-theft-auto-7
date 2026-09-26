# Dedicated server image (docs/dedicated-server.md). Build from the repo root:
#   docker build -t gta7-server .
#   docker run -d --name gta7 -p 22122:22122/udp -v gta7-data:/data gta7-server
FROM ubuntu:24.04

# The Ubuntu image drops man pages and the love package's post-install step
# registers one, so it fails unless man pages are allowed back in first.
RUN sed -i "/usr\\/share\\/man/d" /etc/dpkg/dpkg.cfg.d/excludes \
 && apt-get update \
 && apt-get install -y --no-install-recommends love \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /game
COPY main.lua conf.lua ./
COPY src ./src
COPY lib ./lib
COPY assets ./assets

# Saves and settings live under /data (LÖVE's save directory follows XDG_DATA_HOME).
ENV GTA7_SERVER=1 XDG_DATA_HOME=/data GTA7_WORLD=world GTA7_NAME="Dedicated server"
VOLUME /data
EXPOSE 22122/udp 22123/udp
CMD ["love", "/game"]
