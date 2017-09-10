FROM ubuntu:16.04 as base

ENV DEBIAN_FRONTEND=noninteractive TERM=xterm
RUN echo "export > /etc/envvars" >> /root/.bashrc && \
    echo "export PS1='\[\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" | tee -a /root/.bashrc /etc/skel/.bashrc && \
    echo "alias tcurrent='tail /var/log/*/current -f'" | tee -a /root/.bashrc /etc/skel/.bashrc

RUN apt-get update
RUN apt-get install -y locales && locale-gen en_US.UTF-8 && dpkg-reconfigure locales
ENV LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# Runit
RUN apt-get install -y --no-install-recommends runit
CMD export > /etc/envvars && /usr/sbin/runsvdir-start

# Utilities
RUN apt-get install -y --no-install-recommends vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc iproute python ssh rsync gettext-base

RUN apt-get install -y --no-install-recommends libreadline-dev libncurses5-dev libpcre3-dev zlib1g-dev perl make build-essential

#Confd
RUN wget -O /usr/local/bin/confd  https://github.com/kelseyhightower/confd/releases/download/v0.13.0/confd-0.13.0-linux-amd64 && \
    chmod +x /usr/local/bin/confd

#Redis
RUN wget -O - http://download.redis.io/releases/redis-4.0.1.tar.gz | tar zx && \
    cd redis-* && \
    make -j$(nproc) && \
    make install && \
    cp redis.conf /etc/redis.conf && \
    rm -rf /redis-*

#OpenResty
ENV NPS_VERSION 1.12.34.2
RUN wget -O - https://github.com/pagespeed/ngx_pagespeed/archive/v${NPS_VERSION}-beta.tar.gz | tar xz && \
    cd ngx_pagespeed* && \
    psol_url=https://dl.google.com/dl/page-speed/psol/${NPS_VERSION}.tar.gz && \
    [ -e scripts/format_binary_url.sh ] && psol_url=$(scripts/format_binary_url.sh PSOL_BINARY_URL) && \
    wget -O - ${psol_url} | tar xz && \
    cd / && \
    wget -O - https://www.openssl.org/source/openssl-1.0.2l.tar.gz | tar zx && \
    wget -O - https://openresty.org/download/openresty-1.11.2.4.tar.gz | tar zx && \
    cd /openssl* && \
    ./config && \
    make install && \
    mv apps/openssl /usr/bin/ && \
    cd /openresty* && \
    ./configure -j$(grep -c '^processor' /proc/cpuinfo) \
      --with-http_v2_module \
      --with-pcre-jit \
      --with-ipv6 \
      --prefix=/usr/local/openresty \
      --sbin-path=/usr/sbin/nginx \
      --conf-path=/etc/nginx/nginx.conf \
      --error-log-path=/var/log/nginx/error.log \
      --http-log-path=/var/log/nginx/access.log \
      --pid-path=/var/run/nginx.pid \
      --lock-path=/var/run/nginx.lock \
      --http-client-body-temp-path=/var/cache/nginx/client_temp \
      --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
      --with-file-aio \
      --with-threads \
      --with-stream \
      --with-http_stub_status_module \
      --with-openssl=$(ls -d /openssl*) \
      --with-http_sub_module \
      --with-http_realip_module \
      --add-module=/ngx_pagespeed-${NPS_VERSION}-beta && \
    make -j$(nproc) && \
    make install && \
    rm -rf /openresty* && \
    rm -rf /openssl* && \
    rm -rf /ngx_pagespeed*

RUN mkdir -p /etc/nginx && \
    mkdir -p /var/log/nginx && \
    mkdir -p /var/cache/nginx/client_temp && \
    mkdir -p /var/cache/nginx/proxy_temp

#LuaRocks
RUN wget -O - http://luarocks.org/releases/luarocks-2.3.0.tar.gz | tar zx && \
    cd luarocks-* && \
    ./configure \
      --prefix=/usr/local/openresty/luajit \
      --with-lua=/usr/local/openresty/luajit/ \
      --lua-suffix=jit-2.1.0-beta2 \
      --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 && \
      make -j4 && \
      make install && \
      rm -rf /luarocks-*
RUN cd /usr/local/openresty/luajit/bin && \
    ln -s luajit-* lua
ENV PATH=/usr/local/openresty/luajit/bin:$PATH

#Lua Libraries
RUN luarocks install lua-resty-session
RUN luarocks install inspect
RUN luarocks install lua-resty-http
RUN luarocks install nginx-lua-prometheus
RUN luarocks install lua-resty-cookie

#ssl
RUN openssl dhparam -out /etc/ssl/dhparams.pem 2048
RUN mkdir -p /etc/nginx/ssl && \
    cd /etc/nginx/ssl && \
    export PASSPHRASE=$(head -c 500 /dev/urandom | tr -dc a-z0-9A-Z | head -c 128; echo) && \
    openssl genrsa -des3 -out server.key -passout env:PASSPHRASE 2048 && \
    openssl req -new -batch -key server.key -out server.csr -subj "/C=/ST=/O=org/localityName=/commonName=org/organizationalUnitName=org/emailAddress=/" -passin env:PASSPHRASE && \
    openssl rsa -in server.key -out server.key -passin env:PASSPHRASE && \
    openssl x509 -req -days 3650 -in server.csr -signkey server.key -out server.crt

# Force triggering ERROR_PAGE_404 page
RUN rm -rf /usr/local/openresty/nginx/html

#Passport
RUN wget -O - https://nodejs.org/dist/v8.4.0/node-v8.4.0-linux-x64.tar.gz | tar xz
RUN mv node* node && \
    ln -s /node/bin/node /usr/local/bin/node && \
    ln -s /node/bin/npm /usr/local/bin/npm
ENV NODE_PATH /usr/local/lib/node_modules

COPY authenticator /authenticator
RUN cd /authenticator && \
    npm install && \
    npm run build

#Letsencrypt
RUN luarocks install lua-resty-http && \
    luarocks install lua-resty-auto-ssl
RUN mkdir -p /etc/resty-auto-ssl && \
    chown nobody /etc/resty-auto-ssl

#logrotate
RUN apt-get install -y logrotate cron
COPY logrotate.conf /etc/logrotate.d/nginx.conf
COPY crontab /

#Config
COPY nginx.conf /etc/nginx/
COPY etc/confd /etc/confd
COPY test.sh /
COPY redis.conf /etc/

#SAML
COPY saml/saml.conf /etc/nginx/
COPY saml/saml.lua /usr/local/openresty/lualib/
RUN chmod +r /usr/local/openresty/lualib/*

#Pagespeed data
RUN mkdir -p /var/cache/nginx/pagespeed && chown nobody /var/cache/nginx/pagespeed && \
    mkdir -p /var/log/pagespeed && chown nobody /var/log/pagespeed && \
    mkdir -p /var/nginx/cache && chown nobody /var/nginx/cache
COPY pagespeed-global.conf /etc/nginx/
COPY pagespeed-server.conf /etc/nginx/

# Add runit services
COPY sv /etc/service 
ARG BUILD_INFO
LABEL BUILD_INFO=$BUILD_INFO
