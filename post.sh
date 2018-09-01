#!/bin/bash

if [ $# -ne 2 ]; then
  echo "引数にチーム名と点数を入力してください。" 1>&2
  echo "e.g. sh post.sh xxxx 10000"
  exit 1
fi

FIREBASE=ishocon2-geeoki-201809
TEAM=$1
SCORE=$2

curl https://$FIREBASE.firebaseio.com/teams/$TEAM.json -d "{\"score\":$SCORE, \"timestamp\":`date +%s`}"

