#!/bin/bash

DEPLOY_TYPE=$1

echo "DEPLOY_TYPE $DEPLOY_TYPE";

function error_email
{
  echo "WEB DEPLOYMENT FAILED!" | mail -s "WEB DEPLOYMENT FAILED! EOM" $ERROR_EMAIL;
  exit 1;
}

function clear_redis_cache {
    echo "running redis FLUSHDB ..."
    redis-cli -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASSWORD" <<SCRIPT
    SELECT 0
    FLUSHDB
SCRIPT
}

function clear_orm_cache {
    echo "clearing doctrine metadata"
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan doctrine:clear:metadata:cache
    echo "clearing doctrine query cache"
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan doctrine:clear:query:cache
    echo "clearing doctrine result cache"
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan doctrine:clear:result:cache
    echo "generating doctrine proxies"
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan doctrine:generate:proxies
}

function clear_laravel_cache {
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan config:cache
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan route:clear
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan route:cache
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan view:clear
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan view:cache
}

if [ -z "$DEPLOY_TYPE" ]; then
    DEPLOY_TYPE=0;
fi


if [[ -n "$OVERRIDE_TAG" ]]; then
    echo "overriding repo tag"
    TAG=$OVERRIDE_TAG;
fi

if [[ -n "$OVERRIDE_CHANGE" ]]; then
    echo "overriding repo change"
    CHANGE=$OVERRIDE_CHANGE;
fi


DEPLOYMENT_ID_FILE=$RELEASE_BASE_DIR/.deploymentid

if [ -f $DEPLOYMENT_ID_FILE ]; then
   . $DEPLOYMENT_ID_FILE
else
   mkdir -p $RELEASE_BASE_DIR
   touch $DEPLOYMENT_ID_FILE
fi

DEPLOYMENT_ID=$((DEPLOYMENT_ID+1))
echo "DEPLOYMENT_ID=${DEPLOYMENT_ID}" > $DEPLOYMENT_ID_FILE

echo "DEPLOYMENT_ID $DEPLOYMENT_ID ON $RELEASE_BASE_DIR";
mkdir -p $RELEASE_BASE_DIR/$DEPLOYMENT_ID;

chmod 770 -R $RELEASE_BASE_DIR/$DEPLOYMENT_ID;

chown :www-data -R $RELEASE_BASE_DIR/$DEPLOYMENT_ID;
echo "clonning repo: git clone -b $BRANCH $REPO_URL $RELEASE_BASE_DIR/$DEPLOYMENT_ID";
git clone -b $BRANCH $REPO_URL $RELEASE_BASE_DIR/$DEPLOYMENT_ID;

if [[ $? -ne 0 ]]; then
  error_email;
fi

echo "copying configuration";
ln -s $CONFIG_DIR/.env $RELEASE_BASE_DIR/$DEPLOYMENT_ID/.env;
echo "installing composer";
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && curl -sS https://getcomposer.org/installer | php;

if [[ $? -ne 0 ]]; then
  error_email;
fi

if [[ -n "$GITHUB_OAUTH_TOKEN" ]]; then
   	cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php composer.phar config -g github-oauth.github.com $GITHUB_OAUTH_TOKEN;
fi

echo "setting file permissions";
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && mkdir storage/proxies;
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && mkdir -p storage/logs;
find $RELEASE_BASE_DIR/$DEPLOYMENT_ID -type f -print0 | xargs -0 chmod 644;
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && chown  :www-data -R *;
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && chmod 775 -R storage;
ln -s $STORAGE_HOME $RELEASE_BASE_DIR/$DEPLOYMENT_ID/storage/app/public;

clear_redis_cache

cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php composer.phar install;

if [[ $? -ne 0 ]]; then
  error_email;
fi

cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && chmod 0770 artisan;

clear_laravel_cache

clear_orm_cache

echo "setting file permissions";
find $RELEASE_BASE_DIR/$DEPLOYMENT_ID -type f -print0 | xargs -0 chmod 644;
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && chown  :www-data -R *;
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && chmod 0775 -R storage;

cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && chmod 0777 -R vendor/ezyang/htmlpurifier/library/HTMLPurifier/DefinitionCache/Serializer;

echo "running nvm"
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && \. ~/.nvm/nvm.sh && nvm use;
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && \. ~/.nvm/nvm.sh && nvm install;

echo "running yarn"
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && yarn install;
cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && yarn build;

if [[ $DB_MIGRATE -eq 1 ]]; then
    echo "running db migrations";

    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan doctrine:migrations:migrate --connection=model --force --env=$APP_ENV

    if [[ $? -ne 0 ]]; then
        error_email;
    fi
fi

if [[ $DB_SEED -eq 1 ]]; then
    echo "seeding db ...";
    cd $RELEASE_BASE_DIR/$DEPLOYMENT_ID && php artisan db:seed --force --env=$APP_ENV;
    if [[ $? -ne 0 ]]; then
        error_email;
    fi
fi

echo 'STOP nginx web server ...';
if [[ $DEPLOY_TYPE -eq 1 ]]; then
   service php$PHP_VERSION-fpm stop;
   service nginx stop;
else
   supervisorctl stop phpfpm;
   supervisorctl stop nginx;
fi

files=$(cd $RELEASE_BASE_DIR && ls -t | tail -n +4)
if [[ $files ]]; then
    echo "deleting older deployments";
    cd $RELEASE_BASE_DIR && ls -t | tail -n +4 | xargs sudo rm -R --
fi

echo 'cleaning 80/443 opened connections ...';
fuser -k 80/tcp;
fuser -k 443/tcp;

echo "relinking site to new slot $RELEASE_BASE_DIR/$DEPLOYMENT_ID to $WEB_DIR";
rm -f $WEB_DIR;
ln -s $RELEASE_BASE_DIR/$DEPLOYMENT_ID $WEB_DIR;

if [[ $DEPLOY_TYPE -eq 1 ]]; then
   echo 'restarting PHP-FPM...';
   service php$PHP_VERSION-fpm restart;
else
  echo 'restarting PHP-FPM...';
  supervisorctl start phpfpm;
  echo 'cleannin PHP-FPM cache...';
  service php$PHP_VERSION-fpm reload
  echo 'restarting NGINX ...';
  supervisorctl start nginx;
fi

echo "Restarting laravel queue worker ...";
cd $WEB_DIR && php artisan queue:restart;

if [[ $DEPLOY_TYPE -eq 0 ]]; then
  echo "supervisorctl reload";
  supervisorctl reload;
fi

exit 0;