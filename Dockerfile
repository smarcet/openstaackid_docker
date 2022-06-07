FROM ubuntu:20.04 AS base

ARG REPO_URL=https://github.com/OpenStackweb/openstackid.git
ARG BRANCH=main
ARG SERVER_NAME=idp.local.fnopen.com
ARG CONFIG_DIR=/etc/$SERVER_NAME
ARG RELEASE_BASE_DIR=/srv/deployments
ARG WEB_DIR=/var/www/$SERVER_NAME
ARG PHP_VERSION="7.4"
ARG PHP_FPM_HOME=/etc/php/$PHP_VERSION/fpm
ARG NGINX_HOME=/etc/nginx
ARG APP_ENV=testing
ARG REDIS_HOST="127.0.0.1"
ARG REDIS_PASSWORD="1qaz2wsx"
ARG REDIS_PORT=6378
ARG GITHUB_OAUTH_TOKEN=""
ARG RABBITMQ_HOST=""
ARG RABBITMQ_PASSWORD=""
ARG NVM_VERSION="v0.37.2"
ARG DB_MIGRATE=0
ARG DB_SEED=0
ARG PHP_MAX_POST_SIZE="100M"
ARG PHP_MEMORY_LIMIT="128M"
ARG PHP_PM_MAX_CHILDREN=200
ARG PHP_LISTEN="127.0.0.1:9000"
ARG NGINX_CLIENT_MAX_BODY="100m"
ARG NGINX_FASTCGI_TIMEOUT=300
ARG NODE_NBR=1
ARG DB_USER="openstackid_test_user"
ARG DB_PASSWORD="1qaz2wsx"
ARG DB_NAME="openstackid_test"
ARG NODE_VERSION="v12.19.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV RELEASE_BASE_DIR=$RELEASE_BASE_DIR
ENV CONFIG_DIR=$CONFIG_DIR
ENV APP_ENV=$APP_ENV
ENV SERVER_NAME=$SERVER_NAME
ENV REPO_URL=$REPO_URL
ENV WEB_DIR=$WEB_DIR
ENV DEPLOYMENT_ID=0
ENV BRANCH=$BRANCH
ENV REDIS_PASSWORD=$REDIS_PASSWORD
ENV REDIS_PORT=$REDIS_PORT
ENV REDIS_HOST=$REDIS_HOST
ENV GITHUB_OAUTH_TOKEN=$GITHUB_OAUTH_TOKEN
ENV STORAGE_HOME=/srv/storage
ENV RABBITMQ_HOST=$RABBITMQ_HOST
ENV RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD
ENV NVM_VERSION=$NVM_VERSION
ENV PHP_VERSION=$PHP_VERSION
ENV DB_SEED=$DB_SEED
ENV DB_MIGRATE=$DB_MIGRATE
ENV NODE_NBR=$NODE_NBR
ENV LOG_DIR=$WEB_DIR/storage/logs
ENV NODE_VERSION=$NODE_VERSION
ENV DB_USER=$DB_USER
ENV DB_PASSWORD=$DB_PASSWORD
ENV DB_NAME=$DB_NAME
# base packages

RUN apt-get update && \
  apt-get -y install git wget gnupg apt-utils software-properties-common tar zip curl lsof nano htop \
  redis-tools nginx unzip mysql-client-core-8.0 build-essential ufw apt-utils sed iputils-ping net-tools sudo supervisor \
  apt-utils rsyslog cron unattended-upgrades

RUN dpkg-reconfigure unattended-upgrades

# php 7.X
RUN apt-get update && \
    apt-get install -y php$PHP_VERSION-fpm php$PHP_VERSION-curl php$PHP_VERSION-mysqlnd php$PHP_VERSION-xml php$PHP_VERSION-mbstring php$PHP_VERSION \
    php$PHP_VERSION-curl php$PHP_VERSION-json php$PHP_VERSION-gd php$PHP_VERSION-gmp php$PHP_VERSION-ssh2

# node
RUN apt install -y nodejs npm

# nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash
RUN  \. ~/.nvm/nvm.sh && nvm install $NODE_VERSION

# yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
RUN  apt update && apt install -y yarn

RUN  if [ "$APP_ENV" = "local" ] ; then \
mkdir -p /etc/letsencrypt/live/$SERVER_NAME && \
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
-subj "/C=US/ST=California/L=San Francisco/O=FNTech/OU=IT Department/CN=${SERVER_NAME}" \
-keyout /etc/letsencrypt/live/$SERVER_NAME/privkey.pem \
-out /etc/letsencrypt/live/$SERVER_NAME/fullchain.pem; \
fi

# php config
COPY php/fpm/php.ini $PHP_FPM_HOME/php.ini
RUN sed -i "s*@PHP_MAX_POST_SIZE*$PHP_MAX_POST_SIZE*g" $PHP_FPM_HOME/php.ini
RUN sed -i "s*@PHP_MEMORY_LIMIT*$PHP_MEMORY_LIMIT*g" $PHP_FPM_HOME/php.ini

COPY php/fpm/pool.d/www.conf $PHP_FPM_HOME/pool.d/www.conf
RUN sed -i "s*@PHP_PM_MAX_CHILDREN*$PHP_PM_MAX_CHILDREN*g" $PHP_FPM_HOME/pool.d/www.conf
RUN sed -i "s*@PHP_LISTEN*$PHP_LISTEN*g" $PHP_FPM_HOME/pool.d/www.conf

RUN mkdir -p /run/php
COPY nginx/gzip.conf $NGINX_HOME/gzip.conf

COPY nginx/nginx.conf $NGINX_HOME/nginx.conf
RUN sed -i "s*@NGINX_CLIENT_MAX_BODY*$NGINX_CLIENT_MAX_BODY*g" $NGINX_HOME/nginx.conf

COPY nginx/php-fpm.conf $NGINX_HOME/php-fpm.conf
RUN sed -i "s*@PHP_LISTEN*$PHP_LISTEN*g" $NGINX_HOME/php-fpm.conf
RUN sed -i "s*@NGINX_FASTCGI_TIMEOUT*$NGINX_FASTCGI_TIMEOUT*g" $NGINX_HOME/php-fpm.conf

COPY nginx/snippets/letsencrypt.conf $NGINX_HOME/snippets/letsencrypt.conf
RUN mkdir -p /etc/ssl && cd /etc/ssl && openssl dhparam -out ssl-dhparams.pem 2048
COPY nginx/sites-available/idp.conf $NGINX_HOME/sites-available/$SERVER_NAME
RUN sed -i "s/@SERVER_NAME/$SERVER_NAME/g" $NGINX_HOME/sites-available/$SERVER_NAME
RUN sed -i "s*@WEB_DIR*$WEB_DIR*g" $NGINX_HOME/sites-available/$SERVER_NAME

RUN ln -s $NGINX_HOME/sites-available/$SERVER_NAME $NGINX_HOME/sites-enabled/$SERVER_NAME
RUN rm $NGINX_HOME/sites-enabled/default

# cron tab

# Add crontab file in the cron directory
COPY crontab/laravel /etc/cron.d/laravel

# Give execution rights on the cron job
RUN chmod 0644 /etc/cron.d/laravel

# replace variables
RUN sed -i "s*@WEB_DIR*$WEB_DIR*g" /etc/cron.d/laravel

# Create the log file to be able to run tail
RUN touch /var/log/cron.log

# supervisor
COPY supervisor/supervisor.conf /etc/supervisor/conf.d/supervisor.conf
RUN sed -i "s*@WEB_DIR*$WEB_DIR*g" /etc/supervisor/conf.d/supervisor.conf
RUN sed -i "s*@PHP_VERSION*$PHP_VERSION*g" /etc/supervisor/conf.d/supervisor.conf

# entry point
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod 770 /usr/local/bin/docker-entrypoint.sh \
    && ln -s /usr/local/bin/docker-entrypoint.sh /

RUN mkdir -p /etc/scripts && chmod 770 /etc/scripts
COPY scripts/deployment.sh /etc/scripts/deployment.sh
COPY scripts/server-status.sh /etc/scripts/server-status.sh
COPY scripts/supervisor_watchdog.sh /etc/scripts/supervisor_watchdog.sh
RUN cd /etc/scripts && chmod 770 *.sh
RUN ln -s /etc/scripts/deployment.sh /usr/local/bin/deployment.sh && \
    ln -s /etc/scripts/deployment.sh /
# deployment file

# forward request and error logs to docker log collector
RUN touch /var/log/supervisord.log && \
    ln -sf /dev/stdout /var/log/supervisord.log

VOLUME $STORAGE_HOME

FROM base AS test

COPY app/.env.testing $CONFIG_DIR/.env.testing

RUN chown root:www-data $CONFIG_DIR/.env.testing && \
    chmod 640 $CONFIG_DIR/.env.testing
# replace variables
RUN sed -i "s/@REDIS_PORT/$REDIS_PORT/g" $CONFIG_DIR/.env.testing
RUN sed -i "s/@REDIS_PASSWORD/$REDIS_PASSWORD/g" $CONFIG_DIR/.env.testing
RUN sed -i "s/@DB_USER/$DB_USER/g" $CONFIG_DIR/.env.testing
RUN sed -i "s/@DB_NAME/$DB_NAME/g" $CONFIG_DIR/.env.testing
RUN sed -i "s/@DB_PASSWORD/$DB_PASSWORD/g" $CONFIG_DIR/.env.testing
RUN sed -i "s/@SERVER_NAME/$SERVER_NAME/g" $CONFIG_DIR/.env.testing
RUN sed -i "s/@NODE_NBR/$NODE_NBR/g" $CONFIG_DIR/.env.testing
RUN  ln -s $CONFIG_DIR/.env.testing $CONFIG_DIR/.env

# local mysql config / redis
RUN apt-get -y install mysql-server redis zip unzip
RUN service mysql stop
RUN usermod -d /var/lib/mysql/ mysql
RUN mkdir -p /var/lib/mysql /var/run/mysqld \
    && chown -R mysql:mysql /var/lib/mysql /var/run/mysqld \
    && chmod 777 /var/run/mysqld
RUN sed -i 's/# pid-file/pid-file/' /etc/mysql/mysql.conf.d/mysqld.cnf
RUN sed -i 's/# socket/socket/' /etc/mysql/mysql.conf.d/mysqld.cnf
RUN sed -i 's/mysqlx-bind-address/# mysqlx-bind-address/' /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo "max_connections = 1024" >> /etc/mysql/mysql.conf.d/mysqld.cnf;
RUN echo 'sql_mode = "NO_ENGINE_SUBSTITUTION"' >> /etc/mysql/mysql.conf.d/mysqld.cnf;

VOLUME /var/lib/mysql
# local redis config
COPY scripts/tests.sh /etc/scripts/tests.sh
RUN cd /etc/scripts && chmod 770 *.sh
COPY redis/redis.conf.$APP_ENV /etc/redis/redis.conf
# replace variables
RUN sed -i "s/@REDIS_PORT/$REDIS_PORT/g" /etc/redis/redis.conf
RUN sed -i "s/@REDIS_PASSWORD/$REDIS_PASSWORD/g" /etc/redis/redis.conf
RUN mkdir -p /var/run/redis

RUN ln -s /etc/scripts/tests.sh /usr/local/bin/tests.sh && \
    ln -s /etc/scripts/tests.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]

FROM base AS deploy

RUN mkdir -p $CONFIG_DIR && \
    chown root:www-data $CONFIG_DIR && \
    chmod 770 $CONFIG_DIR

COPY app/.env.$APP_ENV $CONFIG_DIR/.env

RUN chown root:www-data $CONFIG_DIR/.env && \
    chmod 640 $CONFIG_DIR/.env

# replace variables
RUN sed -i "s/@REDIS_PORT/$REDIS_PORT/g" $CONFIG_DIR/.env
RUN sed -i "s/@REDIS_PASSWORD/$REDIS_PASSWORD/g" $CONFIG_DIR/.env
RUN sed -i "s/@SERVER_NAME/$SERVER_NAME/g" $CONFIG_DIR/.env
RUN sed -i "s/@NODE_NBR/$NODE_NBR/g" $CONFIG_DIR/.env
# do intial deployment
RUN ./deployment.sh 1 "$TAG" "$CHANGE"
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["supervisord"]

STOPSIGNAL SIGTERM

EXPOSE 443
EXPOSE 80
