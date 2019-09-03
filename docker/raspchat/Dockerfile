FROM arm32v7/node:8

COPY qemu-arm-static /usr/bin/

RUN echo "Getting Raspchat" && \
	curl \
		--location \
		--fail \
		--silent \
		--show-error \
		--output /opt/raspchat.tar.gz \
		https://github.com/zix99/raspchat/archive/master.tar.gz && \
	mkdir /opt/raspchat && \
	tar xf /opt/raspchat.tar.gz \
		--directory /opt/raspchat \
		--strip-components=1 && \
	rm /opt/raspchat.tar.gz

WORKDIR /opt/raspchat/
RUN npm install && npm rebuild uws

EXPOSE 3030

CMD ["node", "src/index.js"]
