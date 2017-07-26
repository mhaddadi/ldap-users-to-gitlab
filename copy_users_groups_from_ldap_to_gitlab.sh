#!/bin/bash
#
# This script :
# - creates LDAP users into Gitlab ;
# - creates LDAP groups into Gitlab ;
# - adds LDAP group members into Gitlab.
#
# Prerequisites : use of ldapsearch from ldap-utils package

LDAP_URL="ldap://0.0.0.0"
LDAP_USERS_REQUEST="dc=gfi,dc=fr objectClass=inetOrgPerson"
LDAP_GROUPS_REQUEST="dc=gfi,dc=fr objectClass=groupOfUniqueNames"

GITLAB_API_URL="http://127.0.0.1/api/v4"
GITLAB_ADMIN_PRIVATE_TOKEN="fQH7coWrbeuJGMKYkPgz"

_gitlabGroupId=""

# Searches for gitlab group. If it does not exist, it creates it.
processGroup() {
  local group=$1

  local response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" -XGET "$GITLAB_API_URL/groups?search=$group")

  if [[ "[]" == "$response" ]]; then
    # Creating Gitlab group
    echo "-> Creating Gitlab group : $group"
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" --data "name=$group&path=$group" -XPOST "$GITLAB_API_URL/groups")
    echo $reponse
  fi

  # Set current Gitlab group id
  _gitlabGroupId=$(echo $response | sed 's/\(.*\"id\":\)\([0-9]*\)\(,.*\)/\2/')
}

# Searches for gitlab user. If it does not exist, it creates it.
processUser() {
  local uid=$1
  local name=$2
  local mail=$3

  local response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" -XGET "$GITLAB_API_URL/users?username=$uid")

  if [[ "[]" == "$response" ]]; then
    # Creating Gitlab user
    echo "-> Creating Gitlab user username : $uid, e-mail : $mail, name : $name"
    echo $(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" --data "username=$uid&email=$mail&name=$name&reset_password=true" -XPOST "$GITLAB_API_URL/users")
  fi

}

# Sync LDAP users into Gitlab
# ---------------------------
REGEX_UID="uid: (.*)"
REGEX_NAME="cn: (.*)"
REGEX_MAIL="mail: (.*)"

uid=""
name=""
mail=""

ldapsearch -xLLL -H $LDAP_URL -b $LDAP_USERS_REQUEST uid cn mail |
while IFS= read -r line;
do

  if [[ "$line" =~ $REGEX_UID ]]; then
    uid="$(echo "$line" | sed 's/uid: \(.*\)/\1/')"
  fi

  if [[ "$line" =~ $REGEX_NAME ]]; then
    name="$(echo "$line" | sed 's/cn: \(.*\)/\1/')"
  fi

  if [[ "$line" =~ $REGEX_MAIL ]]; then
    mail="$(echo "$line" | sed 's/mail: \(.*\)/\1/')"
  fi

  if [[ "$uid" != "" && "$name" != "" && "$mail" != "" ]]; then
    processUser "$uid" "$name" "$mail"
    uid=""
    name=""
    mail=""
  fi

done

# Sync LDAP groups and members into Gitlab
# ----------------------------------------
REGEX_GROUP_NAME="dn: cn=(.*)"
REGEX_MEMBER="uniqueMember: uid=(.*)"

groupName=""

ldapsearch -xLLL -H $LDAP_URL -b $LDAP_GROUPS_REQUEST uniqueMember |
while IFS= read -r line;
do

  if [[ "$line" =~ $REGEX_GROUP_NAME ]]; then
    _gitlabGroupId=""
    groupName="$(echo "$line" | sed 's/dn: cn=\(.[^,]*\)\(.*\)/\1/')"
    processGroup "$groupName"
  fi

  if [[ "$line" =~ $REGEX_MEMBER ]]; then

    memberUid="$(echo "$line" | sed 's/uniqueMember: uid=\(.[^,]*\)\(.*\)/\1/')"

    if [[ "$memberUid" != "none" ]]; then

      gitlabUserId=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" -XGET "$GITLAB_API_URL/users?username=$memberUid" | sed 's/\(.*\"id\":\)\([0-9]*\)\(,.*\)/\2/')

      if [[ "$gitlabUserId" == "[]" ]]; then
        echo "-> ERROR : user $memberUid was not created previously in Gitlab"
      else
        if [[ "$gitlabUserId" != "" && "$_gitlabGroupId" != "" ]]; then
          echo "-> Adding user $memberUid (Gitlab user id $gitlabUserId) as a member to group $groupName (Gitlab group id $_gitlabGroupId) :"
          echo $(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" -XPOST "$GITLAB_API_URL/groups/$_gitlabGroupId/members?user_id=$gitlabUserId&access_level=30")
        fi
      fi
    fi
  fi

done
