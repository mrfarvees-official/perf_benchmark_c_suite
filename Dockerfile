FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       gcc \
       cmake \
       make \
       time \
       valgrind \
       procps \
       util-linux \
       linux-tools-common \
    && rm -rf /var/lib/apt/lists/*

COPY . /app
RUN chmod +x run_all_linux.sh scripts/*.sh || true

CMD ["./run_all_linux.sh", "docker_ubuntu"]
