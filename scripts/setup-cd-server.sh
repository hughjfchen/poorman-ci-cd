#!/usr/bin/env bash
PROJECT_NAME='detachment-system'
GIT_REPO_PATH='/Users/chenjf/projects/detachment-system'
CD_SERVER='detachment-soft.top'
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
  sudo useradd -m "$CD_USER"

  printf "%s\n%s\n" "$CD_PASSWORD" "$CD_PASSWORD" | sudo passwd "$CD_USER"
  printf "%s\n" "$CD_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/999-cloud-init-user-${CD_USER} > /dev/null
else
  printf "%s\n" "$CD_USER already exists, skip creating user"
  printf "%s\n" "Please make sure the user $CD_USER is the EXACT user you want to use to do the CD job."
fi

sudo -u $CD_USER mkdir -p /home/$CD_USER/$PROJECT_NAME.git
sudo -u $CD_USER mkdir -p /home/$CD_USER/$PROJECT_NAME.work
sudo -u $CD_USER mkdir -p /home/$CD_USER/$PROJECT_NAME.build
sudo -u $CD_USER mkdir -p /home/$CD_USER/$PROJECT_NAME.deploy
sudo -u $CD_USER git -C /home/$CD_USER/$PROJECT_NAME.git init --bare

# Git Hook for ban on push to main branch
cat << _EOFPreReceive | sudo -u $CD_USER tee /home/$CD_USER/$PROJECT_NAME.git/hooks/pre-receive > /dev/null
#!/usr/bin/env bash

changedBranch=\$(git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')
# Add allowed users to push to main
allowedUsers=($CD_USER)
if [ "\$changedBranch" == "main" ]; then
  if [[ \${allowedUsers[*]} =~ \$USER ]]; then
    true
  else
    echo "You are not allowed to push changes to the main branch, only $CD_USER can do it"
    exit 1
  fi
fi
_EOFPreReceive
sudo -u $CD_USER chmod 755 /home/$CD_USER/$PROJECT_NAME.git/hooks/pre-receive

cat << _EOFPostReceive | sudo -u $CD_USER tee /home/$CD_USER/$PROJECT_NAME.git/hooks/post-receive > /dev/null
#!/usr/bin/env bash

target_branch="main"
working_tree="/home/$CD_USER/$PROJECT_NAME.work"
build_output="/home/$CD_USER/$PROJECT_NAME.build"
deploy_output="/home/$CD_USER/$PROJECT_NAME.deploy"
while read -r oldrev newrev refname
do
  branch=\$(git rev-parse --symbolic --abbrev-ref "\$refname")
  if [ -n "\$branch" ] && [ "\$target_branch" = "\$branch" ]; then
    mkdir -p "\$working_tree"
    GIT_WORK_TREE=\$working_tree git checkout \$target_branch -f
    NOW=\$(date +"%Y%m%d-%H%M")
    git tag "release_\$NOW" \$target_branch
    echo " /==============================="
    echo " | RESTORE WORKING TREE COMPLETED"
    echo " | Target branch: \$target_branch"
    echo " | Target folder: \$working_tree"
    echo " | Tag name : release_\$NOW"
    echo " | Now kick off the CD"
    echo " \=============================="
    nohup "\$working_tree"/.poormanscicd/cd.sh "\$working_tree" "\$newrev" "\$build_output"/ci-artifact-$PROJECT_NAME-\$newrev.tar.gz > "\$deploy_output"/cd.log 2>&1 &
  fi
done
_EOFPostReceive
sudo -u $CD_USER chmod 755 /home/$CD_USER/$PROJECT_NAME.git/hooks/post-receive
