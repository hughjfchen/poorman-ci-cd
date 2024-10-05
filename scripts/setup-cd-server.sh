#!/usr/bin/env bash
PROJECT_NAME='my-ci1'
GIT_REPO_PATH='my-ci1'
CD_SERVER='mycdserver.com'
CD_USER=''
CD_PASSWORD=''
set -eou pipefail

[ -z $PROJECT_NAME ] && echo "PROJECT_NAME cannot be empty" && exit 2
[ -z $GIT_REPO_PATH ] && echo "GIT_REPO_PATH cannot be empty" && exit 2

if sudo -n /usr/bin/true 2>/dev/null; then
  echo "This script will run with passwordless sudo"
else
  echo "This script needs a user with passwordless sudo permission,will abort"
  exit 127
fi

[ -z $CD_SERVER ] && echo "CD_SERVER cannot be empty" && exit 2

: ${CD_USER:=${PROJECT_NAME}cd}
: ${CD_PASSWORD:="Passw0rd"}

if ! getent passwd "$CD_USER" >/dev/null 2>&1; then
  sudo useradd "$CD_USER"
  printf "%s\n%s\n" "Passw0rd" | sudo passwd "$CD_USER"
  sudo printf "%s\n" "$CD_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-cloud-init-users
else
  printf "%s\n" "$CD_USER already exists, skip creating user"
  printf "%s\n" "Please make sure the user $CI_USER is the EXACT user you want to use to do the CI job."
fi

sudo -u $CD_USER mkdir -p /home/$CD_USER/$PROJECT_NAME.git
sudo -u $CD_USER git -C /home/$CD_USER/$PROJECT_NAME.git init --bare

# Git Hook for ban on push to main branch
sudo -u $CD_USER cat << _EOFPreReceive > /home/$CD_USER/$PROJECT_NAME.git/.hooks/pre-receive
changedBranch=$(git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')
# Add blocked user username
blockedUsers=($CD_USER)
if [[ ${blockedUsers[*]} =~ $USER ]]; then
  if [ "$changedBranch" == "main" ]; then
    echo "You are not allowed commit changes in the main branch"
  exit 1
  fi
fi
_EOFPreReceive
sudo -u $CD_USER chmod 755 /home/$CD_USER/$PROJECT_NAME.git/.hooks/pre-receive

sudo -u $CD_USER cat << _EOFPostReceive > /home/$CD_USER/$PROJECT_NAME.git/.hooks/post-receive
target_branch="main"
working_tree="<project_name>.deploy"
while read -r oldrev newrev refname
do
  branch=$(git rev-parse --symbolic --abbrev-ref "$refname")
  if [ -n "$branch" ] && [ "$target_branch" = "$branch" ]; then
    mkdir -p "$working_tree"
    GIT_WORK_TREE=$working_tree git checkout $target_branch -f
    NOW=$(date +"%Y%m%d-%H%M")
    git tag "release_$NOW" $target_branch
    echo " /==============================="
    echo " | RESTORE WORKING TREE COMPLETED"
    echo " | Target branch: $target_branch"
    echo " | Target folder: $working_tree"
    echo " | Tag name : release_$NOW"
    echo " | Now kick off the CD"
    echo " \=============================="
    "$working_tree"/.poormanscicd/cd.sh
  fi
done
_EOFPostReceive
sudo -u $CD_USER chmod 755 /home/$CD_USER/$PROJECT_NAME.git/.hooks/post-receive
