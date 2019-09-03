FROM arm32v7/node:latest

COPY qemu-arm-static /usr/bin/

RUN echo "Getting Filedrop" && \
	curl \
		--location \
		--fail \
		--silent \
		--show-error \
		--output /opt/filedrop.tar.gz \
		https://github.com/zix99/filedrop/archive/master.tar.gz && \
	mkdir /opt/filedrop && \
	tar xf /opt/filedrop.tar.gz \
		--directory /opt/filedrop \
		--strip-components=1 && \
	rm /opt/filedrop.tar.gz

WORKDIR /opt/filedrop/
RUN npm install --production

ENV filedrop_target=/var/drops
RUN mkdir -p $filedrop_target
EXPOSE 8080

CMD ["node", "index.js"]
