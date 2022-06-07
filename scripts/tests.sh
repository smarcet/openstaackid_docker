#!/bin/bash
service redis-server start
service mysql start \
    & sleep 10
echo "DB_USER $DB_USER DB_NAME $DB_NAME..."
mysql -e "CREATE USER $DB_USER@'%' IDENTIFIED BY '$DB_PASSWORD';CREATE DATABASE IF NOT EXISTS $DB_NAME;GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'%';FLUSH PRIVILEGES;" \

./deployment.sh 0

ln -s $CONFIG_DIR/.env.testing $WEB_DIR/.env.testing;

cd $WEB_DIR && chmod 777 vendor/bin/phpunit
cd $WEB_DIR && php artisan config:clear
cd $WEB_DIR &&  ./vendor/bin/phpunit

exit 0