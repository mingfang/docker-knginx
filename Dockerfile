FROM ubuntu:14.04
 
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
RUN locale-gen en_US en_US.UTF-8
ENV LANG en_US.UTF-8
RUN echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" >> /root/.bashrc

#Runit
RUN apt-get install -y runit 
CMD export > /etc/envvars && /usr/sbin/runsvdir-start
RUN echo 'export > /etc/envvars' >> /root/.bashrc

#Utilities
RUN apt-get install -y vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc

#nginx
RUN wget http://nginx.org/keys/nginx_signing.key -O - | apt-key add - && \
    echo 'deb http://nginx.org/packages/mainline/ubuntu/ trusty nginx' > /etc/apt/sources.list.d/nginx.list && \
    apt-get update
RUN apt-get install -y nginx 

#Confd
RUN wget -O /usr/local/bin/confd  https://github.com/kelseyhightower/confd/releases/download/v0.9.0/confd-0.9.0-linux-amd64 && \
    chmod +x /usr/local/bin/confd

ADD etc/confd /etc/confd

#Add runit services
ADD sv /etc/service 

