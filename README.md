# LDAP users to Gitlab

This script gets all users from LDAP. For each user :
 * if his group does not exist in Gitlab, it creates it ;
 * if the user does not exist in Gitlab, it creates it ;
 * if the user is not a member of his group in Gitlab, it adds it.

 ### Prerequisites
 * use of ldapsearch from ldap-utils package
