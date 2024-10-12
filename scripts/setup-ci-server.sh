#!/usr/bin/env bash
PROJECT_NAME='my-ci1'
GIT_REPO_PATH='/Users/chenjf/projects/my-ci1'
CI_SERVER='detachmentsoft.top'
CI_USER=''
CI_PASSWORD=''
set -eou pipefail

[ -z $PROJECT_NAME ] && echo "PROJECT_NAME cannot be empty" && exit 2
[ -z $GIT_REPO_PATH ] && echo "GIT_REPO_PATH cannot be empty" && exit 2

if sudo -n /usr/bin/true 2>/dev/null; then
  echo "This script will run with passwordless sudo"
else
  echo "This script needs a user with passwordless sudo permission,will abort"
  exit 127
fi

[ -z $CI_SERVER ] && echo "CI_SERVER cannot be empty" && exit 2

: ${CI_USER:=${PROJECT_NAME}ci}
: ${CI_PASSWORD:="Passw0rd"}



# - create a CI user ::
# For each project, a dedicated user would be created on the CI machine
# to run the CI script.


if ! getent passwd "$CI_USER" >/dev/null 2>&1; then
  sudo useradd -m "$CI_USER"
  printf "%s\n%s\n" "${CI_PASSWORD}" "${CI_PASSWORD}"| sudo passwd "$CI_USER"
  printf "%s\n" "$CI_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/999-cloud-init-user-${CI_USER} > /dev/null
else
  printf "%s\n" "$CI_USER already exists, skip creating user"
  printf "%s\n" "Please make sure the user $CI_USER is the EXACT user you want to use to do the CI job."
fi



# - init a bare =git= repo ::
# No need to work on the source tree on the CI machine, so we only create
# a =bare= git repo on the CI machine.


sudo -u $CI_USER mkdir -p /home/$CI_USER/$PROJECT_NAME.git
sudo -u $CI_USER mkdir -p /home/$CI_USER/$PROJECT_NAME.work
sudo -u $CI_USER mkdir -p /home/$CI_USER/$PROJECT_NAME.build
sudo -u $CI_USER git -C /home/$CI_USER/$PROJECT_NAME.git init --bare



# - add a =pre-receive= hook to check permission to avoid unauthorized push ::
# There is a dedicated git branch *main* for =CI= build, when this branch pushed to
# the =CI= machine, a =CI= build will be kicked off.

# This =pre-receive= script will check permission to make sure
# only listed users can push to the branch dedicated for =CI= build.


cat << _EOFPreReceive | sudo -u $CI_USER tee /home/$CI_USER/$PROJECT_NAME.git/hooks/pre-receive > /dev/null
#!/usr/bin/env bash

# Git Hook for ban on push to main branch
changedBranch=\$(git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')
# Add allowed users to push to main
allowedUsers=($CI_USER)
if [ "\$changedBranch" == "main" ]; then
  if [[ \${allowedUsers[*]} =~ \$USER ]]; then
    true
  else
    echo "You are not allowed push changes in the main branch, only $CI_USER can do it"
    exit 1
  fi
fi
_EOFPreReceive
sudo -u $CI_USER chmod 755 /home/$CI_USER/$PROJECT_NAME.git/hooks/pre-receive



# - add the =post-receive= hook which will checkout the work tree and call the =ci= script ::
# If the dedicated =CI= build branch *main* has been pushed to the =CI= machine
# by a authorized user, the =CI= build flow will be kicked off.

# First, a working tree will be restored under a directory.

# Then, the =CI= script within the source tree will be called to do
# the real =CI= work.


cat << _EOFPostReceive | sudo -u $CI_USER tee /home/$CI_USER/$PROJECT_NAME.git/hooks/post-receive > /dev/null
#!/usr/bin/env bash

target_branch="main"
working_tree="/home/$CI_USER/$PROJECT_NAME.work"
build_output="/home/$CI_USER/$PROJECT_NAME.build"
while read -r oldrev newrev refname
do
  branch=\$(git rev-parse --symbolic --abbrev-ref "\$refname")
  if [ -n "\$branch" ] && [ "\$target_branch" = "\$branch" ]; then
    mkdir -p "\$working_tree"
    GIT_WORK_TREE=\$working_tree git checkout \$target_branch -f
    NOW=\$(date +"%Y%m%d-%H%M%S")
    git tag "release_\$NOW" \$target_branch
    echo " /==============================="
    echo " | RESTORE WORKING TREE COMPLETED"
    echo " | Target branch: \$target_branch"
    echo " | Target folder: \$working_tree"
    echo " | Tag name : release_\$NOW"
    echo " | Now kick off the CI"
    echo " \=============================="
    "\$working_tree"/.poormanscicd/ci.sh "\$working_tree" "\$newrev" "\$build_output"/ci-artifact-$PROJECT_NAME-\$newrev.tar.gz > "\$build_output"/ci.log 2>&1 &
  fi
done
_EOFPostReceive
sudo -u $CI_USER chmod 755 /home/$CI_USER/$PROJECT_NAME.git/hooks/post-receive
