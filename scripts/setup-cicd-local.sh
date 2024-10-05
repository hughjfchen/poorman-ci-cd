#!/usr/bin/env bash
PROJECT_NAME='my-ci1'
GIT_REPO_PATH='my-ci1'
CI_SERVER='myciserver.com'
CD_SERVER='mycdserver.com'
CI_USER=''
CI_PASSWORD=''
CD_USER=''
CD_PASSWORD=''
set -eou pipefail
set -x

[ -z $CI_SERVER ] && echo "CI_SERVER cannot be empty" && exit 2
[ -z $CD_SERVER ] && echo "CD_SERVER cannot be empty" && exit 2

: ${CI_USER:=${PROJECT_NAME}ci}
: ${CI_PASSWORD:="Passw0rd"}
: ${CD_USER:=${PROJECT_NAME}cd}
: ${CD_PASSWORD:="Passw0rd"}

[ -f ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER ] || printf "\n\n\n" | ssh-keygen -t rsa -b 4096 -C "$CI_USER@$CI_SERVER" -f ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER
[ -f ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER ] || printf "\n\n\n" | ssh-keygen -t rsa -b 4096 -C "$CD_USER@$CD_SERVER" -f ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER

printf "%s\n" "$CI_PASSWORD" | ssh-copy-id -i ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER "$CI_USER"@"$CI_SERVER"
printf "%s\n" "$CD_PASSWORD" | ssh-copy-id -i ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER "$CD_USER"@"$CD_SERVER"

cat << _SSH_CONFIG_FOR_CI >> ~/.ssh/config
Host $CI_SERVER
  User $CI_USER
  IdentityFile ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER
  IdentitiesOnly yes
_SSH_CONFIG_FOR_CI
cat << _SSH_CONFIG_FOR_CD >> ~/.ssh/config
Host $CD_SERVER
  User $CD_USER
  IdentityFile ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER
  IdentitiesOnly yes
_SSH_CONFIG_FOR_CD

git remote add ci-at-$CI_SERVER ssh://$CI_USER@$CI_SERVER:/home/$CI_USER/$PROJECT_NAME.git
git remote add cd-at-$CD_SERVER ssh://$CD_USER@$CD_SERVER:/home/$CD_USER/$PROJECT_NAME.git



# - define a =git= =pre-push= hook to fetch the =CI= artifact and forware to the =CD= machine ::


cat << _EOFPrePush > $$GIT_REPO_PATH/.git/.hooks/pre-push
: ${RELATED_CI_SERVER:=$CI_SERVER}

target_branch="main"
working_tree="<project_name>.build"
while read -r remotename remotelocation refname
do
  branch=$(git rev-parse --symbolic --abbrev-ref "$refname")
  if [ -n "$branch" ] && [ "$target_branch" = "$branch" ]; then
    mkdir -p "$working_tree"
    GIT_WORK_TREE=$working_tree git checkout $target_branch -f
    NOW=$(date +"%Y%m%d-%H%M")
    git tag "release_$NOW" $target_branch
    echo " /==============================="
    echo " | DEPLOYMENT COMPLETED"
    echo " | Target branch: $target_branch"
    echo " | Target folder: $working_tree"
    echo " | Tag name : release_$NOW"
    echo " | Now kick off the CD"
    echo " \=============================="
    "$working_tree"/.mycicd/cd.sh
  fi
done
_EOFPrePush
chmod 755 $$GIT_REPO_PATH/.git/.hooks/pre-push

cat << _FOLLOW_CI_LOG_SCRIPT > $GIT_REPOS/.poormanscicd/follow-ci-log-$CI_SERVER.sh
ssh $CI_USER@$CI_SERVER -c "tail -f /home/$CI_USER/$PROJECT_NAME.build/ci.log"
_FOLLOW_CI_LOG_SCRIPT
chmod 755 $GIT_REPOS/.poormanscicd/follow-ci-log-$CI_SERVER.sh
cat << _FOLLOW_CD_LOG_SCRIPT > $GIT_REPOS/.poormanscicd/follow-cd-log-$CD_SERVER.sh
ssh $CD_USER@$CD_SERVER -c "tail -f /home/$CD_USER/$PROJECT_NAME.deploy/cd.log"
_FOLLOW_CD_LOG_SCRIPT
chmod 755 $GIT_REPOS/.poormanscicd/follow-cd-log-$CD_SERVER.sh

cat << _VIEW_CI_LOG_SCRIPT > $GIT_REPOS/.poormanscicd/view-ci-log-$CI_SERVER.sh
ssh $CI_USER@$CI_SERVER -c "cat /home/$CI_USER/$PROJECT_NAME.build/ci.log"
_VIEW_CI_LOG_SCRIPT
chmod 755 $GIT_REPOS/.poormanscicd/view-ci-log-$CI_SERVER.sh
cat << _VIEW_CD_LOG_SCRIPT > $GIT_REPOS/.poormanscicd/view-cd-log-$CD_SERVER.sh
ssh $CD_USER@$CD_SERVER -c "cat /home/$CD_USER/$PROJECT_NAME.deploy/cd.log"
_VIEW_CD_LOG_SCRIPT
chmod 755 $GIT_REPOS/.poormanscicd/view-cd-log-$CD_SERVER.sh
