#!/bin/bash


date >> /var/log/nginx_status.log;
curl 127.0.0.1/nginx_status >> /var/log/nginx_status.log;

date >> /var/log/php_status.log;
curl 127.0.0.1/php_status >> /var/log/php_status.log;
