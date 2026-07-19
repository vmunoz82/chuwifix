FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Enable source repos so 'apt source' works.
RUN sed -i 's/Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources \
    && cat /etc/apt/sources.list.d/ubuntu.sources

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        bc \
        kmod \
        cpio \
        flex \
        bison \
        libelf-dev \
        libdw-dev \
        libssl-dev \
        dwarves \
        zstd \
        rsync \
        ca-certificates \
        dpkg-dev \
        debhelper \
        fakeroot \
        quilt \
        patch \
        wget \
        xz-utils \
        python3 \
        pahole \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
