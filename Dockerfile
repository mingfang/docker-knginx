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
RUN wget -O /usr/local/bin/confd  https://github.com/kelseyhightower/confd/releases/download/v0.15.0/confd-0.15.0-linux-amd64 && \
    chmod +x /usr/local/bin/confd

#Redis
RUN wget -O - http://download.redis.io/releases/redis-4.0.8.tar.gz | tar zx && \
    cd redis-* && \
    make -j$(nproc) && \
    make install && \
    cp redis.conf /etc/redis.conf && \
    rm -rf /redis-*

#libmodsecurity
RUN apt-get install -y m4 libtool automake libxml2-dev libyajl-dev libgeoip-dev libcurl4-gnutls-dev pkgconf
RUN wget -O - https://github.com/SpiderLabs/ModSecurity/releases/download/v3.0.0/modsecurity-v3.0.0.tar.gz | tar zx && \
    cd modsecurity* && \
    ./build.sh && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    rm -rf /modsecurity*

#OpenResty
RUN wget -O - https://github.com/SpiderLabs/ModSecurity-nginx/releases/download/v1.0.0/modsecurity-nginx-v1.0.0.tar.gz | tar zx && \
    wget -O - https://www.openssl.org/source/openssl-1.0.2n.tar.gz | tar zx && \
    wget -O - https://openresty.org/download/openresty-1.13.6.1.tar.gz | tar zx && \
    cd /openssl* && \
    ./config && \
    make install && \
    mv apps/openssl /usr/bin/ && \
    cd /openresty* && \
    ./configure -j$(grep -c '^processor' /proc/cpuinfo) \
      --with-http_v2_module \
      --with-pcre-jit \
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
      --add-module=/modsecurity-nginx-v1.0.0 \
    && \
    make -j$(nproc) && \
    make install && \
    rm -rf /openresty* && \
    rm -rf /openssl* && \
    rm -rf /modsecurity-nginx*

RUN mkdir -p /etc/nginx && \
    mkdir -p /var/log/nginx && \
    mkdir -p /var/cache/nginx/client_temp && \
    mkdir -p /var/cache/nginx/proxy_temp

#LuaRocks
RUN wget -O - http://luarocks.org/releases/luarocks-2.4.3.tar.gz | tar zx && \
    cd luarocks-* && \
    ./configure \
      --prefix=/usr/local/openresty/luajit \
      --with-lua=/usr/local/openresty/luajit/ \
      --lua-suffix=jit-2.1.0-beta3 \
      --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 && \
      make -j$(grep -c '^processor' /proc/cpuinfo) && \
      make install && \
      rm -rf /luarocks-*
RUN cd /usr/local/openresty/luajit/bin && \
    ln -s luajit-* lua
ENV PATH=/usr/local/openresty/luajit/bin:$PATH

#Lua Libraries
RUN luarocks install lua-resty-session
RUN luarocks install inspect
RUN luarocks install lua-resty-http
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
RUN wget -O - https://nodejs.org/dist/v8.10.0/node-v8.10.0-linux-x64.tar.gz | tar xz
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

#OWASP rules
RUN wget -O - https://github.com/SpiderLabs/owasp-modsecurity-crs/archive/v3.0.2.tar.gz | tar zx && \
    mv owasp* /etc/nginx/owasp
RUN cp /etc/nginx/owasp/crs-setup.conf.example /etc/nginx/owasp/owasp.conf
COPY modsec /etc/nginx/modsec

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

# Add runit services
COPY sv /etc/service 
ARG BUILD_INFO
LABEL BUILD_INFO=$BUILD_INFO
