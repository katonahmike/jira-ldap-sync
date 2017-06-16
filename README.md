# jira-ldap-sync
Compare JIRA Cloud users to an LDAP or AD directory.

## Overview
JIRA cloud has no facility for enterprises to authenticate users against a central authentication provider with the exception of Google Docs. This poses a problem if an employee in the enterprise leaves that organization, because disabling her enterprise AD or LDAP account won't do anything where JIRA is concerned. Most Enterprises are forced to host JIRA internally for this reason.

## Work-around
This Perl script uses the JIRA API to find users and compare them to your internal AD or LDAP directory. It was designed to take the JIRA email address and compare it to the UserPrincipalName attribute in AD (commonly set to the user's email address for Office365) to locate the account. It then checks if the UserAccountControl property is anything other than 512 (normal account), and if so, disables the user in JIRA by removing her from all JIRA/Confluence groups, effectively disabling the user and freeing up JIRA/Confluence licenses on your subscription.

## Installation
I'm running this successfuly with Perl 5.18. It requires the following libraries:
* JSON
* LWP::UserAgent
* Net::LDAP
* MIME::Base64
* Email::Sender::Simple
* Email::Sender::Transport::SMTP
* Email::Simple::Markdown
* Try::Tiny

## Usage
* Edit jira_sync.json
  * Be sure to keep debug and testmode settings as true until your tests look good
* Test. This may take time to get working. You may need to use an LDAP browser to experiment with ldap search settings until you get the user search working
* When tests look good, you can safely set debug and testmode to false
