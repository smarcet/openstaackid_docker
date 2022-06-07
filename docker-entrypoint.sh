#!/bin/bash

set -e
set -x
echo "entrypoint"

if [ "$1" = 'supervisord' ]; then
    echo "starting supervisord"
    exec /usr/bin/supervisord
fi

if [ "$1" = 'migrate' ]; then
    echo "starting db migrations"
    DEPLOYMENT_ID_FILE=$RELEASE_BASE_DIR/.deploymentid
    if [ -f $DEPLOYMENT_ID_FILE ]; then
      . $DEPLOYMENT_ID_FILE
    fi
    service redis start
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan doctrine:migrations:migrate --connection=model --force --env=$APP_ENV;

    exit 0
fi

if [ "$1" = 'seed' ]; then
    echo "starting db seed"
    DEPLOYMENT_ID_FILE=$RELEASE_BASE_DIR/.deploymentid
    if [ -f $DEPLOYMENT_ID_FILE ]; then
      . $DEPLOYMENT_ID_FILE
    fi
    service redis start
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan db:seed --force --env=$APP_ENV;

    exit 0
fi

exec "$@";