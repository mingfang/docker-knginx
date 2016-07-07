FROM ubuntu:14.04
  
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    TERM=xterm
RUN locale-gen en_US en_US.UTF-8
RUN echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" >> /root/.bashrc
RUN apt-get update

# Runit
RUN apt-get install -y runit 
CMD export > /etc/envvars && /usr/sbin/runsvdir-start
RUN echo 'export > /etc/envvars' >> /root/.bashrc

# Utilities
RUN apt-get install -y vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc

RUN apt-get install -y libreadline-dev libncurses5-dev libpcre3-dev zlib1g-dev perl make build-essential

#Confd
RUN wget -O /usr/local/bin/confd  https://github.com/kelseyhightower/confd/releases/download/v0.11.0/confd-0.11.0-linux-amd64 && \
    chmod +x /usr/local/bin/confd

#Redis
RUN wget -O - http://download.redis.io/releases/redis-3.0.7.tar.gz | tar zx && \
    cd redis-* && \
    make -j4 && \
    make install && \
    cp redis.conf /etc/redis.conf && \
    rm -rf /redis-*

RUN curl -L https://github.com/pagespeed/ngx_pagespeed/archive/release-1.11.33.2-beta.tar.gz | tar xz
RUN cd ngx_pagespeed* && \
    curl https://dl.google.com/dl/page-speed/psol/1.11.33.2.tar.gz | tar xz

#OpenResty
RUN wget -O - https://github.com/openssl/openssl/archive/OpenSSL_1_0_2h.tar.gz | tar zx && \
    wget -O - https://github.com/nbs-system/naxsi/archive/0.54.tar.gz | tar zx && \
    wget -O - https://openresty.org/download/openresty-1.9.15.1.tar.gz | tar zx && \
    cd /openssl* && \
    ./config && \
    make install && \
    mv apps/openssl /usr/bin/ && \
    cd /openresty* && \
    ./configure \
      --add-module=../naxsi-0.54/naxsi_src/ \
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
      --add-module=/ngx_pagespeed-release-1.11.33.2-beta && \

    make -j4 && \
    make install && \
    rm -rf /openresty* && \
    rm -rf /naxsi* && \
    rm -rf /openssl*

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

RUN mkdir -p /var/ngx_pagespeed_cache && chmod 777 /var/ngx_pagespeed_cache
RUN mkdir -p /var/log/pagespeed && chmod 777 /var/log/pagespeed
RUN mkdir -p /var/nginx/cache && chmod 777 /var/nginx/cache

#Passport
RUN wget -O - https://nodejs.org/dist/v6.1.0/node-v6.1.0-linux-x64.tar.gz | tar xz
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

COPY nginx.conf /etc/nginx/
COPY etc/confd /etc/confd
COPY test.sh /
COPY redis.conf /etc/

#SAML
COPY saml/saml.conf /etc/nginx/
COPY saml/saml.lua /usr/local/openresty/lualib/

#NAXSI
COPY etc/naxsi.rules /etc/nginx/
COPY etc/naxsi/naxsi_core.rules /etc/nginx/naxsi/

COPY pagespeed.conf /etc/nginx/

# Add runit services
COPY sv /etc/service 
ARG BUILD_INFO
LABEL BUILD_INFO=$BUILD_INFO
