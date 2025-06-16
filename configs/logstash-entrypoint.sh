#!/bin/bash
set -e

# Download the JDBC driver if not present
if [ ! -f /usr/share/logstash/postgresql-42.7.6.jar ]; then
  curl -L -o /usr/share/logstash/postgresql-42.7.6.jar https://jdbc.postgresql.org/download/postgresql-42.7.6.jar
fi

# Start Logstash
exec /usr/local/bin/docker-entrypoint