export CFLAGS=-DPG_NO_DEBUG
export PG_CONFIG=/usr/local/pgsql/bin/pg_config
./configure --without-libcurl
make
make install
