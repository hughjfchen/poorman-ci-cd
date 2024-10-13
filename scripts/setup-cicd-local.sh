#!/usr/bin/env bash
PROJECT_NAME='detachment-system'
GIT_REPO_PATH='/Users/chenjf/projects/detachment-system'
CI_SERVER='detachment-soft.top'
CD_SERVER='detachment-soft.top'
CI_USER=''
CI_PASSWORD=''
CD_USER=''
CD_PASSWORD=''
set -eou pipefail

[ -z $CI_SERVER ] && echo "CI_SERVER cannot be empty" && exit 2
[ -z $CD_SERVER ] && echo "CD_SERVER cannot be empty" && exit 2

: ${CI_USER:=${PROJECT_NAME}ci}
: ${CI_PASSWORD:="Passw0rd"}
: ${CD_USER:=${PROJECT_NAME}cd}
: ${CD_PASSWORD:="Passw0rd"}

[ -f ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER ] || printf "\n\n" | ssh-keygen -t rsa -b 4096 -C "$CI_USER@$CI_SERVER" -f ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER
[ -f ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER ] || printf "\n\n" | ssh-keygen -t rsa -b 4096 -C "$CD_USER@$CD_SERVER" -f ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER

# the printf tips does not work any more because ssh command
# read input from terminal directory instead from stdin
if type -p sshpass > /dev/null 2>&1; then
  sshpass -p "$CI_PASSWORD" ssh-copy-id -i ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER "$CI_USER"@"$CI_SERVER"
  sshpass -p "$CD_PASSWORD" ssh-copy-id -i ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER "$CD_USER"@"$CD_SERVER"
else
  ssh-copy-id -i ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER "$CI_USER"@"$CI_SERVER"
  ssh-copy-id -i ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER "$CD_USER"@"$CD_SERVER"
if

cat << _SSH_CONFIG_FOR_CI >> ~/.ssh/config

Host $CI_SERVER
  StrictHostKeyChecking accept-new
  User $CI_USER
  IdentityFile ~/.ssh/id_rsa.${PROJECT_NAME}_CI_at_$CI_SERVER
  IdentitiesOnly yes
_SSH_CONFIG_FOR_CI
cat << _SSH_CONFIG_FOR_CD >> ~/.ssh/config

Host $CD_SERVER
  StrictHostKeyChecking accept-new
  User $CD_USER
  IdentityFile ~/.ssh/id_rsa.${PROJECT_NAME}_CD_at_$CD_SERVER
  IdentitiesOnly yes
_SSH_CONFIG_FOR_CD

git -C "$GIT_REPO_PATH" remote remove ci-at-$CI_SERVER
git -C "$GIT_REPO_PATH" remote add ci-at-$CI_SERVER ssh://$CI_USER@$CI_SERVER:/home/$CI_USER/$PROJECT_NAME.git
git -C "$GIT_REPO_PATH" remote remove cd-at-$CD_SERVER
git -C "$GIT_REPO_PATH" remote add cd-at-$CD_SERVER ssh://$CD_USER@$CD_SERVER:/home/$CD_USER/$PROJECT_NAME.git



# - define a =git= =pre-push= hook to fetch the =CI= artifact and forware to the =CD= machine ::


if [ -e $GIT_REPO_PATH/.git/hooks/pre-push ]; then
  sed -i.bak.by.sed "s/######AppendAssociativeCIServerFollowingThisLine######/&\nRELATED_CI_SERVERS[\"${CD_SERVER}\"]=\"$CI_SERVER\"/" $GIT_REPO_PATH/.git/hooks/pre-push
  rm -fr $GIT_REPO_PATH/.git/hooks/pre-push.bak.by.sed
else
set +u
cat << _EOFPrePush > $GIT_REPO_PATH/.git/hooks/pre-push
#!/usr/bin/env zsh

# An example hook script to verify what is about to be pushed.  Called by "git
# push" after it has checked the remote status, but before anything has been
# pushed.  If this script exits with a non-zero status nothing will be pushed.
#
# This hook is called with the following parameters:
#
# $1 -- Name of the remote to which the push is being done
# $2 -- URL to which the push is being done
#
# If pushing without using a named remote those arguments will be equal.
#
# Information about the commits which are being pushed is supplied as lines to
# the standard input in the form:
#
#   <local ref> <local oid> <remote ref> <remote oid>
#
# This sample shows how to prevent push of commits where the log message starts
# with "WIP" (work in progress).
set -eo pipefail

remote="\$1"
url="\$2"

if [[ "\$remote" = "cd-at-"* ]]; then
declare -A RELATED_CI_SERVERS
######AppendAssociativeCIServerFollowingThisLine######
RELATED_CI_SERVERS["$CD_SERVER"]="$CI_SERVER"

target_branch="main"
ci_build_output="/home/$CI_USER/$PROJECT_NAME.build"
cd_build_output="/home/$CD_USER/$PROJECT_NAME.build"
cd_deploy_output="/home/$CD_USER/$PROJECT_NAME.deploy"
while read -r localref localsha remoteref remotesha
do
  branch=\$(git rev-parse --symbolic --abbrev-ref "\$remoteref")
  if [ -n "\$branch" ] && [ "\$target_branch" = "\$branch" ]; then
    THE_CD_SERVER=\$(echo "\$url" | cut -d'@' -f2 | cut -d':' -f1)
    THE_CI_SERVER=\${RELATED_CI_SERVERS["\$THE_CD_SERVER"]}
    TEMP_CI_ARTIFACT=\$(mktemp -d -t ci-artifact-$PROJECT_NAME.xxxx)
    if ssh ${CI_USER}@\$THE_CI_SERVER test -f \$ci_build_output/ci-artifact-$PROJECT_NAME-\$localsha.tar.gz; then
       scp $CI_USER@\$THE_CI_SERVER:\$ci_build_output/ci-artifact-$PROJECT_NAME-\$localsha.tar.gz \$TEMP_CI_ARTIFACT/
       scp \$TEMP_CI_ARTIFACT/ci-artifact-$PROJECT_NAME-\$localsha.tar.gz $CD_USER@\$THE_CD_SERVER:\$cd_build_output/
       rm -fr \$TEMP_CI_ARTIFACT
       echo "build artifact is available as \$cd_build_output/ci-artifact-$PROJECT_NAME-\$localsha.tar.gz on the machine \$THE_CD_SERVER"
    else
       echo "cannot found the CI artifact for main branch revision \$localsha on the CI server \$THE_CI_SERVER."
       echo "please run the command 'git push ci-at-\$THE_CI_SERVER \$branch' to build the project before you can deploy."
       echo "abort deployment."
       exit 111
    fi
  fi
done
fi
_EOFPrePush
set -u
fi
chmod 755 $GIT_REPO_PATH/.git/hooks/pre-push

[ -d $GIT_REPO_PATH/.poormanscicd ] || mkdir -p $GIT_REPO_PATH/.poormanscicd

cat << _FOLLOW_CI_LOG_SCRIPT > $GIT_REPO_PATH/.poormanscicd/follow-ci-log-$CI_SERVER.sh
ci_build_output="/home/$CI_USER/$PROJECT_NAME.build"
ssh $CI_USER@$CI_SERVER tail -f \$ci_build_output/ci.log
_FOLLOW_CI_LOG_SCRIPT
chmod 755 $GIT_REPO_PATH/.poormanscicd/follow-ci-log-$CI_SERVER.sh
cat << _FOLLOW_CD_LOG_SCRIPT > $GIT_REPO_PATH/.poormanscicd/follow-cd-log-$CD_SERVER.sh
cd_deploy_output="/home/$CD_USER/$PROJECT_NAME.deploy"
ssh $CD_USER@$CD_SERVER tail -f \$cd_deploy_output/cd.log
_FOLLOW_CD_LOG_SCRIPT
chmod 755 $GIT_REPO_PATH/.poormanscicd/follow-cd-log-$CD_SERVER.sh

[ -d $GIT_REPO_PATH/.poormanscicd ] || mkdir -p $GIT_REPO_PATH/.poormanscicd

cat << _VIEW_CI_LOG_SCRIPT > $GIT_REPO_PATH/.poormanscicd/view-ci-log-$CI_SERVER.sh
ci_build_output="/home/$CI_USER/$PROJECT_NAME.build"
ssh $CI_USER@$CI_SERVER cat \$ci_build_output/ci.log
_VIEW_CI_LOG_SCRIPT
chmod 755 $GIT_REPO_PATH/.poormanscicd/view-ci-log-$CI_SERVER.sh
cat << _VIEW_CD_LOG_SCRIPT > $GIT_REPO_PATH/.poormanscicd/view-cd-log-$CD_SERVER.sh
cd_deploy_output="/home/$CD_USER/$PROJECT_NAME.deploy"
ssh $CD_USER@$CD_SERVER cat \$cd_deploy_output/cd.log
_VIEW_CD_LOG_SCRIPT
chmod 755 $GIT_REPO_PATH/.poormanscicd/view-cd-log-$CD_SERVER.sh

set +u
cat << _CI_TEMPLATE_SCRIPT > $GIT_REPO_PATH/.poormanscicd/ci.sh
#!/usr/bin/env bash

# this script will be fed with three parameters when being invoked:
# \$1 - the working tree directory of the git repository
# \$2 - the revision hash of the git repository
# \$3 - the full path of the build artifact tarball
# This script should tar up the build result and put to the location
# of the \$3

set -eo pipefail

WORKING_TREE="\$1"
GIT_REV="\$2"
BUILD_TARBALL="\$3"

######## Put the CI commands below ######
echo "Please add your own CI commands in the $GIT_REPO_PATH/.poormanscicd/ci.sh"

#### the last step is to tar up the build result and dave to \$3 ###
touch "\$3"

_CI_TEMPLATE_SCRIPT
chmod 755 $GIT_REPO_PATH/.poormanscicd/ci.sh
cat << _CD_TEMPLATE_SCRIPT > $GIT_REPO_PATH/.poormanscicd/cd.sh
#!/usr/bin/env bash

# this script will be fed with three parameters when being invoked:
# \$1 - the working tree directory of the git repository
# \$2 - the revision hash of the git repository
# \$3 - the full path of the build artifact tarball
# This script should read the build tarball from the localtion of \$3

set -eo pipefail

WORKING_TREE="\$1"
GIT_REV="\$2"
BUILD_TARBALL="\$3"

######## Put the CD commands below ######
echo "Please add your own CD commands in the $GIT_REPO_PATH/.poormanscicd/cd.sh"

echo "build tarball: \$BUILD_TARBALL"

_CD_TEMPLATE_SCRIPT
chmod 755 $GIT_REPO_PATH/.poormanscicd/cd.sh
set -u
