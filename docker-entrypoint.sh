#!/bin/bash
set -e

if [ -z "$MYSQL_PORT_3306_TCP" ]; then
	echo >&2 'error: missing MYSQL_PORT_3306_TCP environment variable'
	echo >&2 '  Did you forget to --link some_mysql_container:mysql ?'
	exit 1
fi

# if we're linked to MySQL, and we're using the root user, and our linked
# container has a default "root" password set up and passed through... :)
: ${DISCUZ_DB_USER:=root}
if [ "$DISCUZ_DB_USER" = 'root' ]; then
	: ${DISCUZ_DB_PASSWORD:=$MYSQL_ENV_MYSQL_ROOT_PASSWORD}
fi
: ${DISCUZ_DB_NAME:=discuz}

if [ -z "$DISCUZ_DB_PASSWORD" ]; then
	echo >&2 'error: missing required DISCUZ_DB_PASSWORD environment variable'
	echo >&2 '  Did you forget to -e DISCUZ_DB_PASSWORD=... ?'
	echo >&2
	echo >&2 '  (Also of interest might be DISCUZ_DB_USER and DISCUZ_DB_NAME.)'
	exit 1
fi

if ! [ -e index.php ]; then
        echo >&2 "Discuz not found in $(pwd) - copying now..."
        rsync --archive --one-file-system --quiet /usr/src/discuz/ ./
        echo >&2 "Complete! Discuz has been successfully copied to $(pwd)"
fi

set_config() {
	key="$1"
	value="$2"
	php_escaped_value="$(php -r 'var_export($argv[1]);' "$value")"
	sed_escaped_value="$(echo "$php_escaped_value" | sed 's/[\/&]/\\&/g')"
	sed -ri "s/(\[(['\"])$key\2\]\s*\=\s*)(['\"]).*\3/\1$sed_escaped_value/" config/config_global_default.php
}

DISCUZ_DB_HOST="${MYSQL_PORT_3306_TCP#tcp://}"

set_config 'dbhost' "$DISCUZ_DB_HOST"
set_config 'dbuser' "$DISCUZ_DB_USER"
set_config 'dbpw' "$DISCUZ_DB_PASSWORD"
set_config 'dbname' "$DISCUZ_DB_NAME"


TERM=dumb php -- "$DISCUZ_DB_HOST" "$DISCUZ_DB_USER" "$DISCUZ_DB_PASSWORD" "$DISCUZ_DB_NAME" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

list($host, $port) = explode(':', $argv[1], 2);
$mysql = new mysqli($host, $argv[2], $argv[3], '', (int)$port);

if ($mysql->connect_error) {
	file_put_contents('php://stderr', 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
	exit(1);
}

if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($argv[4]) . '`')) {
	file_put_contents('php://stderr', 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
	$mysql->close();
	exit(1);
}

$mysql->close();
EOPHP

chown -R "$APACHE_RUN_USER:$APACHE_RUN_GROUP" .

exec "$@"
