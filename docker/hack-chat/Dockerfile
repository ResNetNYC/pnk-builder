FROM lsiobase/alpine:arm32v7-3.10
MAINTAINER J
 
RUN apk update && apk add git make nodejs nodejs-npm python
RUN git clone https://github.com/hack-chat/main.git /app \
&& cd /app \
#&& git checkout 345dbfec41062408171b521f297f03e122f762c0 \
&& cd server \
&& npm install \
&& mkdir -p config \
&& ln -sT main.js server.js \
&& cd ../client \
&& npm install -g less jade http-server \
&& apk del git make \
&& rm -rf /var/cache/apk/* \
&& rm -rf /root \
&& mkdir -p / /root \
&& mkdir -p /var/log/client \
&& chown -R nobody:nobody /var/log/client \
&& mkdir -p /var/log/server \
&& chown -R nobody:nobody /var/log/server

COPY root/ /
COPY config.json /app/server/config/config.json
 
EXPOSE 8080 6060
