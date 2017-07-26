# LDAP users to Gitlab

This script synchronizes Gitlab users and groups with LDAP :
 * it creates LDAP users into Gitlab ;
 * it creates LDAP groups into Gitlab ;
 * it adds LDAP group members into Gitlab.

 ### Prerequisites
 * use of ldapsearch from ldap-utils package
