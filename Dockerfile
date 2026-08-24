FROM couchdb:3.5.0

COPY --chown=5984:5984 config/livesync.ini /opt/couchdb/etc/local.d/livesync.ini
