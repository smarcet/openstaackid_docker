#!/usr/bin/env bash
dt=`date '+%d/%m/%Y %H:%M:%S'`
output=$(supervisorctl status | grep -i "FATAL");

if test -z "$output"
then
      echo "[$dt] - everything running just fine";
else
      echo "[$dt] - some process has stopped, reloading supervisor";
      echo "$output"
      supervisorctl reload;
fi
