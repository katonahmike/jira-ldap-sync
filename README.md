# jira-ldap-sync
Perl script to compare JIRA Cloud users to an LDAP or AD directory and disable the JIRA user account if the LDAP entry meets some condition.

## Overview
JIRA cloud has no facility for enterprises to authenticate users against a central authentication provider with the exception of Google Docs. This poses a problem if an employee in the enterprise leaves that organization, because disabling her enterprise AD or LDAP account won't do anything where JIRA is concerned. Most Enterprises are forced to host JIRA internally for this reason.

## Work-around
This Perl script uses the JIRA API to find users and compare them to your internal AD or LDAP directory
