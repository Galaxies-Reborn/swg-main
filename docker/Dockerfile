FROM ubuntu:18.04

ARG ORACLE_IC_VERSION=19.31.0.0.0dbru
ARG ORACLE_IC_DIR=1931000
ARG ORACLE_IC_HOME=/opt/oracle/instantclient_19_31

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ant \
        ant-optional \
        bash \
        bison \
        ca-certificates \
        cmake \
        curl \
        file \
        flex \
        g++ \
        g++-multilib \
        gcc \
        gcc-multilib \
        git \
        libaio1:i386 \
        libboost-program-options-dev \
        libcurl4-openssl-dev:i386 \
        libncurses5-dev:i386 \
        libpcre3-dev:i386 \
        libsqlite3-dev \
        libxml2-dev:i386 \
        make \
        netbase \
        openjdk-11-jdk:i386 \
        perl \
        procps \
        psmisc \
        python \
        python3 \
        rsync \
        sqlite3 \
        unzip \
        zlib1g-dev:i386 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/oracle \
    && cd /opt/oracle \
    && for package in basiclite sdk sqlplus jdbc; do \
        curl -fL -O "https://download.oracle.com/otn_software/linux/instantclient/${ORACLE_IC_DIR}/instantclient-${package}-linux-${ORACLE_IC_VERSION}.zip"; \
    done \
    && unzip -oq "instantclient-basiclite-linux-${ORACLE_IC_VERSION}.zip" \
    && unzip -oq "instantclient-sdk-linux-${ORACLE_IC_VERSION}.zip" \
    && unzip -oq "instantclient-sqlplus-linux-${ORACLE_IC_VERSION}.zip" \
    && unzip -oq "instantclient-jdbc-linux-${ORACLE_IC_VERSION}.zip" \
    && rm -f ./*.zip \
    && ln -sf "${ORACLE_IC_HOME}" /opt/oracle/instantclient \
    && cd "${ORACLE_IC_HOME}" \
    && ln -sf libclntsh.so.19.1 libclntsh.so \
    && ln -sf libocci.so.19.1 libocci.so \
    && mkdir -p lib \
    && ln -sf ../ojdbc8.jar lib/ojdbc8.jar \
    && echo "${ORACLE_IC_HOME}" > /etc/ld.so.conf.d/oracle-instantclient.conf \
    && ldconfig

ENV ORACLE_HOME=/opt/oracle/instantclient_19_31
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-i386
ENV NLS_LANG=american_america.utf8
ENV PATH="${ORACLE_HOME}:${JAVA_HOME}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${ORACLE_HOME}:${JAVA_HOME}/lib:${JAVA_HOME}/lib/server"

WORKDIR /swg-main

COPY docker/entrypoint.sh /usr/local/bin/swg-entrypoint
RUN chmod +x /usr/local/bin/swg-entrypoint

ENTRYPOINT ["/bin/bash", "/usr/local/bin/swg-entrypoint"]
CMD ["run"]
