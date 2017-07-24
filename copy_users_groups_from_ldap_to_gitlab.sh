#!/bin/bash
#
# This script gets all users from LDAP. For each user :
# - if his group does not exist in Gitlab, it creates it ;
# - if the user does not exist in Gitlab, it creates it ;
# - if the user is not a member of his group in Gitlab, it adds it.
#
# Prerequisites : use of ldapsearch from ldap-utils package

LDAP_URL="ldap://0.0.0.0"
LDAP_USERS_DN="ou=people,dc=ldap,dc=test,dc=org objectClass=person"

GITLAB_API_URL="http://127.0.0.1/api/v4"
GITLAB_ADMIN_PRIVATE_TOKEN="8jH4Kzs_N1mTjsePRLzR"

_gitlabGroupId=""
_gitlabUserId=""

# Search for gitlab group. If it does not exist, it creates it.
processGroup() {
  local group=$1

  local response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" -XGET "$GITLAB_API_URL/groups?search=$group")

  if [[ "[]" == "$response" ]]; then
    # Creating Gitlab group
    echo "Creating Gitlab group : $group"
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" --data "name=$group&path=$group" -XPOST "$GITLAB_API_URL/groups")
  fi

  _gitlabGroupId=$(echo $response | sed 's/\(.*\"id\":\)\([0-9]*\)\(,.*\)/\2/')
}

# Search for gitlab user. If it does not exist, it creates it.
processUser() {
  local uid=$1
  local name=$2
  local mail=$3

  local response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" -XGET "$GITLAB_API_URL/users?username=$uid")

  if [[ "[]" == "$response" ]]; then
    # Creating Gitlab user
    echo "Creating Gitlab user username : $uid, e-mail : $mail, name : $name"
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" --data "username=$uid&email=$mail&name=$name&reset_password=true" -XPOST "$GITLAB_API_URL/users")
  fi

  # Return Gitlab user id
  _gitlabUserId=$(echo $response | sed 's/\(.*\"id\":\)\([0-9]*\)\(,.*\)/\2/')
}

# Main part : basically, for each LDAP user...
REGEX_UID="uid: (.*)"
REGEX_NAME="cn: (.*)"
REGEX_MAIL="mail: (.*)"
REGEX_GROUPE="ou: (.*)"

uid=''
name=''
mail=''
group=''

ldapsearch -xLLL -H $LDAP_URL -b $LDAP_USERS_DN uid cn mail ou |
while IFS= read -r line;
do

  if [[ $line =~ $REGEX_UID ]]; then
    uid="$(echo "$line" | sed 's/uid: \(.*\)/\1/')"
  fi

  if [[ $line =~ $REGEX_NAME ]]; then
    name="$(echo "$line" | sed 's/cn: \(.*\)/\1/')"
  fi

  if [[ $line =~ $REGEX_MAIL ]]; then
    mail="$(echo "$line" | sed 's/mail: \(.*\)/\1/')"
  fi

  if [[ $line =~ $REGEX_GROUPE ]]; then
    group=$(echo "$line" | sed 's/ou: \(.*\)/\1/')
  fi

  if [[ "$uid" != "" && "$name" != "" && "$mail" != "" && "$group" != "" ]]; then

    processGroup "$group"

    processUser "$uid" "$name" "$mail"

    if [[ "$_gitlabUserId" != "" && "$_gitlabGroupId" != "" ]]; then
      echo "Adding user $uid (Gitlab user id $_gitlabUserId) as a member to group $group (Gitlab group id $_gitlabGroupId) :"

      curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" -XPOST "$GITLAB_API_URL/groups/$_gitlabGroupId/members?user_id=$_gitlabUserId&access_level=30"

      echo ""
    fi

    uid=''
    name=''
    mail=''
    group=''
    _gitlabGroupId=''
    _gitlabUserId=''
  fi

done
