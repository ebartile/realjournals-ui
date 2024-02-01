#!/usr/bin/env bash
set -euo pipefail

UNAMEOUT="$(uname -s)"

WHITE='\033[1;37m'
NC='\033[0m'

echo "We are running the application on $UNAMEOUT"

# Verify operating system is supported...
case "${UNAMEOUT}" in
Linux*) MACHINE=linux ;;
Darwin*) MACHINE=mac ;;
*) MACHINE="UNKNOWN" ;;
esac

if [ "$MACHINE" == "UNKNOWN" ]; then
	echo "Unsupported operating system [$(uname -s)]. Server supports macOS, Linux, and Windows (WSL2)." >&2 && exit 1
fi

if [[ $EUID -eq 0 ]]; then
	echo -e "You cannot start Server as root." >&2 && exit 1
fi

echo -e "Setting environment variables" 

# Define environment variables...
export TERMINAL_SERVICE=${TERMINAL_SERVICE:-"terminal"}
export HOST_TERMINAL_UID=${HOST_TERMINAL_UID:-$(id -u "terminaluser")}
export TERMINAL_USER=${HOST_TERMINAL_UID}
export ADMIN_SERVICE=${ADMIN_SERVICE:-"admin"}
export HOST_ADMIN_UID=${HOST_ADMIN_UID:-$(id -u "adminuser")}
export ADMIN_USER=${HOST_ADMIN_UID}
export CHARTS_SERVICE=${CHARTS_SERVICE:-"charts"}
export HOST_CHARTS_UID=${HOST_CHARTS_UID:-$(id -u "chartsuser")}
export CHARTS_USER=${HOST_CHARTS_UID}

if [ "$MACHINE" == "linux" ]; then
	export SEDCMD="sed -i"
elif [ "$MACHINE" == "mac" ]; then
	export SEDCMD="sed -i .bak"
fi

echo -e "Ensuring that Docker is running..." 
# Ensure that Docker is running...
if ! docker info >/dev/null 2>&1; then	
	echo -e "Docker is not running. Installing docker" >&2 && exit 1
fi

eval "docker run --rm \
	    -u root \
		-v "$(pwd)":/terminal \
		-w /terminal node:16"

eval "docker run --rm \
	    -u root \
		-v "$(pwd)":/admin \
		-w /admin node:16"

eval "docker run --rm \
	    -u root \
		-v "$(pwd)":/charts \
		-w /charts node:16"

echo -e "Setting up letsencrypt..." 
# Setting up letsencrypt
mkdir -p "${HOME}"/www/certbot
mkdir -p "${HOME}"/lib/letsencrypt
mkdir -p "${HOME}"/log/letsencrypt
mkdir -p "${HOME}"/letsencrypt

if [ ! -f "${HOME}"/letsencrypt/ssl-dhparams.pem ]; then
	openssl dhparam -out "${HOME}"/letsencrypt/ssl-dhparams.pem 2048
fi

echo -e "Creating external nginx network..." 
# Create external nginx network
if ! docker network inspect nginx-proxy >/dev/null 2>&1; then
	docker network create nginx-proxy
fi

function initialize_env() {
	set -euo pipefail

	echo -e "Initializing Env" 
	
	if [ ! -f ./.env ]; then
		cp ./.env.example ./.env

		echo -e "env initialized"
	else
		echo -e "env file exists"
	fi
}

function initialize_project() {
	set -euo pipefail

	DEFAULT_ALIAS=${PWD##*/}

	initialize_env

	echo -e "Setting up docker image server."


	echo -e "Server installed successfully."
}

if [ $# -gt 0 ]; then
	# Initialize project
	if [ "$1" == "init-project" ]; then
		initialize_project && exit 0

	# Initialize .env
	elif [ "$1" == "init-env" ]; then
		initialize_env && exit 0

	fi
fi

function server_is_not_running() {
	echo -e "Server is not running." >&2 && exit 1
}

if [ $# -gt 0 ]; then
	# Source environment files
	if [ -f ./.env ]; then
		source ./.env
	else
		echo -e "${WHITE}.env file does not exists:${NC}" >&2
		echo -e "Run 'init' command first." >&2 && exit 1
	fi

	if [ "$TERMINAL_ENV" == "production" ] && [ "$TERMINAL_DEBUG" == "true" ]; then
		echo "You need to set TERMINAL_DEBUG=false in production" >&2 && exit 1
	fi

	if [ "$ADMIN_ENV" == "production" ] && [ "$ADMIN_DEBUG" == "true" ]; then
		echo "You need to set ADMIN_DEBUG=false in production" >&2 && exit 1
	fi

	if [[ $TERMINAL_HOST ]]; then
		export TERMINAL_DOMAIN=${TERMINAL_HOST}
	else
		echo "The value of TERMINAL_HOST is invalid." >&2 && exit 1
	fi

	if [[ $ADMIN_HOST ]]; then
		export ADMIN_DOMAIN=${ADMIN_HOST}
	else
		echo "The value of ADMIN_HOST is invalid." >&2 && exit 1
	fi

	function set_nginx_ssl_directive() {
		CERTIFICATE_TERMINAL_DIR="${HOME}/letsencrypt/live/${TERMINAL_DOMAIN}"
		CERTIFICATE_ADMIN_DIR="${HOME}/letsencrypt/live/${ADMIN_DOMAIN}"

		export NGINX_HTTP_PORT="80"
		export NGINX_HTTPS_PORT="443"

		if  [ -f "${CERTIFICATE_TERMINAL_DIR}/fullchain.pem" ] && [ -f "${CERTIFICATE_TERMINAL_DIR}/privkey.pem" ]; then
			export NGINX_DEFAULT_TERMINAL_CONFIG="/etc/nginx/conf.d/terminal.ssl"
		else
			export NGINX_DEFAULT_TERMINAL_CONFIG="/etc/nginx/conf.d/terminal"
		fi

		if  [ -f "${CERTIFICATE_ADMIN_DIR}/fullchain.pem" ] && [ -f "${CERTIFICATE_ADMIN_DIR}/privkey.pem" ]; then
			export NGINX_DEFAULT_ADMIN_CONFIG="/etc/nginx/conf.d/admin.ssl"
		else
			export NGINX_DEFAULT_ADMIN_CONFIG="/etc/nginx/conf.d/admin"
		fi
	}

	set_nginx_ssl_directive

	CERTBOT="docker run -it --rm -u $(id -u):$(id -g) \
	-v ${HOME}/letsencrypt:/etc/letsencrypt \
	-v ${HOME}/lib/letsencrypt:/var/lib/letsencrypt \
	-v ${HOME}/log/letsencrypt:/var/log/letsencrypt \
	-v ${HOME}/www/certbot:/var/www/certbot \
	certbot/certbot"

	# Determine if Server is currently up...
	if docker-compose ps 2>/dev/null | grep -q 'Exit'; then
		EXEC="no"
	elif [ -n "$(docker-compose ps -q 2>/dev/null)" ]; then
		EXEC="yes"
	else
		EXEC="no"
	fi

	# Run ssl to secure container...
	if [ "$1" == "ssl" ]; then
		shift 1

		if [ -z "$CERTBOT_EMAIL" ]; then
			echo -e "Set CERTBOT_EMAIL to proceed." >&2 && exit 1
		fi

		if [ "$EXEC" == "yes" ]; then
			eval "$CERTBOT" certonly --webroot --webroot-path=/var/www/certbot \
				--email "$CERTBOT_EMAIL" --agree-tos --no-eff-email --force-renewal \
				-d "$ADMIN_DOMAIN"

			eval "$CERTBOT" certonly --webroot --webroot-path=/var/www/certbot \
				--email "$CERTBOT_EMAIL" --agree-tos --no-eff-email --force-renewal \
				-d "$TERMINAL_DOMAIN"

			set_nginx_ssl_directive

			docker-compose up -d
		else
			server_is_not_running
		fi

	# Renew ssl to secure container...
	elif [ "$1" == "ssl-renew" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			eval "$CERTBOT" renew && docker-compose restart
		else
			server_is_not_running
		fi

	# Disable 'down' and 'rm' commands
	elif [ "$1" == "down" ] || [ "$1" == "rm" ]; then
		echo -e "The command is disabled." >&2 && exit 1

	elif [ "$1" == "terminal-exec-app-no-tty" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$TERMINAL_USER" \
				-T "$TERMINAL_SERVICE" \
				"$@"
		else
			server_is_not_running
		fi

	# Proxy Node commands to the "node" binary on the application container...
	elif [ "$1" == "terminal-node" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$TERMINAL_USER" \
				"$TERMINAL_SERVICE" \
				node "$@"
		else
			server_is_not_running
		fi

	# Proxy NPM commands to the "npm" binary on the application container...
	elif [ "$1" == "terminal-npm" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$TERMINAL_USER" \
				"$TERMINAL_SERVICE" \
				npm "$@"
		else
			server_is_not_running
		fi

	# Proxy NPX commands to the "npx" binary on the application container...
	elif [ "$1" == "terminal-npx" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$TERMINAL_USER" \
				"$TERMINAL_SERVICE" \
				npx "$@"
		else
			server_is_not_running
		fi

	# Initiate a Bash shell within the application container...
	elif [ "$1" == "terminal-shell" ] || [ "$1" == "bash" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$TERMINAL_USER" \
				"$TERMINAL_SERVICE" \
				bash
		else
			server_is_not_running
		fi

	# Initiate a root user Bash shell within the application container...
	elif [ "$1" == "terminal-root-shell" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				"$TERMINAL_SERVICE" \
				bash
		else
			server_is_not_running
		fi

	elif [ "$1" == "admin-exec-app-no-tty" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$ADMIN_USER" \
				-T "$ADMIN_SERVICE" \
				"$@"
		else
			server_is_not_running
		fi

	# Proxy Node commands to the "node" binary on the application container...
	elif [ "$1" == "admin-node" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$ADMIN_USER" \
				"$ADMIN_SERVICE" \
				node "$@"
		else
			server_is_not_running
		fi

	# Proxy NPM commands to the "npm" binary on the application container...
	elif [ "$1" == "admin-npm" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$ADMIN_USER" \
				"$ADMIN_SERVICE" \
				npm "$@"
		else
			server_is_not_running
		fi

	# Proxy NPX commands to the "npx" binary on the application container...
	elif [ "$1" == "admin-npx" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$ADMIN_USER" \
				"$ADMIN_SERVICE" \
				npx "$@"
		else
			server_is_not_running
		fi

	# Initiate a Bash shell within the application container...
	elif [ "$1" == "admin-shell" ] || [ "$1" == "bash" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				-u "$ADMIN_USER" \
				"$ADMIN_SERVICE" \
				bash
		else
			server_is_not_running
		fi

	# Initiate a root user Bash shell within the application container...
	elif [ "$1" == "admin-root-shell" ]; then
		shift 1

		if [ "$EXEC" == "yes" ]; then
			docker-compose exec \
				"$ADMIN_SERVICE" \
				bash
		else
			server_is_not_running
		fi

	# Redirect the default 'start' command to 'up'...
	elif [ "$1" == "start" ]; then
		shift 1

		docker-compose up -d

	# Pass unknown commands to the "docker-compose"...
	else
		docker-compose "$@"
	fi
else
	docker-compose ps
fi

