#!/usr/bin/env bash

while read oldrev newrev ref
do
  if [[ $ref =~ .*/main$ ]]; then
    echo "Main ref received.  Deploying main branch to production..."
    git --work-tree=/var/www/html --git-dir=$HOME/proj checkout -f
  else
    echo "Ref $ref successfully received.  Doing nothing: only the main branch may be deployed on this server."
  fi
done
