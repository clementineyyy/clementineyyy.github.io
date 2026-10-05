FROM amirpourmand/al-folio:latest

# Add Node.js with npm (the base image has nodejs but not npm)
RUN curl -fsSL https://nodejs.org/dist/v20.18.0/node-v20.18.0-linux-x64.tar.xz | tar -xJ -C /usr/local --strip-components=1 && \
    npm install -g purgecss

# Use local entry_point.sh
COPY bin/entry_point.sh /tmp/entry_point.sh

CMD ["/tmp/entry_point.sh"]