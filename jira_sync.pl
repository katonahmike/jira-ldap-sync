#!/usr/bin/perl

#This script is free to use. Be certain the associated config file has testMode *on* before running
#Once you are comfortable that only users who should be deactivated are mentioned in testMode, then you can turn it off
#This script comes with no warranty or support. Use at your own risk.

use strict;
use warnings;
use JSON;
use LWP::UserAgent;
use Net::LDAP;
use MIME::Base64;

# Load Configurations and set basic params
my $config=LoadConfig('jira_sync.json');
my $debug=$config->{debug};
my $testMode=$config->{testmode};

# Initialize some strings and bind to LDAP
my $jiraAuthString=GetJiraAuthString();
my $userAgent=InitUserAgent(); #User agent for HTTP requests
my $ldap=InitLdap();

# Get the list of Jira users
my $jiraEmails=GetJiraEmails();

# Sync against your ldap or active directory
SyncToLdap($jiraEmails);

sub GetJiraEmails {
    InfoMsg("Searching JIRA users letter by letter. This may take a few minutes if you have many.");
    my @letters=qw/a b c d e f g h i j k l m n o p q r s t u v w x y z/; #The only way I know to get all JIRA users is to search letter-by-letter
    my $uniqueEmails; #Unique hash to store deduped user emails
    my $userCount=0;
    
    foreach my $letter(@letters){
        my $req = HTTP::Request->new(GET => "$config->{jira}->{host}/rest/api/2/user/search?username=$letter");
        $req->header('Content-Type' => "application/json", "Authorization" => $jiraAuthString);
        my $res = $userAgent->request($req);
        if ($res->is_success) {
           my $obj=decode_json($res->decoded_content);
           foreach my $userFound(@{$obj}){
                my $uniqueEmail=lc($userFound->{emailAddress});
                if(!defined($uniqueEmails->{$uniqueEmail})){
                    $userCount++;
                    $uniqueEmails->{$uniqueEmail}=$userFound->{name};
                    if($userCount % 100 == 0){DebugMsg("$userCount users found")}
                }
           }
        }
        else {
           print "Error searching JIRA by letter $letter: " . $res->status_line . "\n";
        }
    }
    return($uniqueEmails);
}

sub SyncToLdap { #This is where the magic happens. You may need to experiment with LDAP parameters to get search and filters working.
    my $jiraEmails=shift;
    InfoMsg("Comparing JIRA users against LDAP. This may take a while");
    my $userCount=0;
    my $ldapSearchFilterTemplate="$config->{ldap}->{searchfilter}";
    foreach my $key(sort keys %{$jiraEmails}){
        my $filter=$ldapSearchFilterTemplate;
        $filter=~s/REPLACEWITHJIRAEMAIL/$key/;
        my $results = $ldap->search(
            base   => $config->{ldap}->{searchbase},
            filter => $filter,
            scope => $config->{ldap}->{searchscope}
        );
        if ($results->code){
            die "Problem searching ldap: ".$results->error
        }
        foreach my $entry ($results->entries) {
            #The next line is important. You need to know what LDAP user property constitutes a normal active user.
            #If this LDAP property doesn't match the active value from the config file will be deactivated in JIRA when testMode is off
            if($entry->get_value("$config->{ldap}->{activeproperty}") ne "$config->{ldap}->{activevalue}"){
                if($testMode){
                    InfoMsg("Would have removed $jiraEmails->{$key} from all JIRA groups, but testMode is on");
                }else{
                    my $errors=RemoveUserFromAllJiraGroups($jiraEmails->{$key});
                    if($errors ne ''){
                        InfoMsg($errors);
                    }
                }
            }
        }
        $userCount++;
        if($userCount % 100 == 0){DebugMsg("$userCount users compared in ldap")}
    }
}

sub RemoveUserFromAllJiraGroups{
    my($userName)=@_;
    my $user=GetJiraUser($userName);
    my $errors='';
    foreach my $group(@{$user->{groups}->{items}}){
        #print "Removing $user->{name} from $group->{name}\n";
        my $delReq = HTTP::Request->new(DELETE => "$config->{jira}->{host}/rest/api/2/group/user?username=$user->{name}&groupname=$group->{name}");
        $delReq->header('Content-Type' => "application/json", "Authorization" => $jiraAuthString);
        my $delRes = $userAgent->request($delReq);
        if ($delRes->is_success) {
            DebugMsg("Successfully removed $user->{name} from JIRA group $group->{name}");
        }
        else {
           $errors.= "Error: " . $delRes->status_line . "\n";
        }
    }
    return($errors);
}

sub GetJiraUser{
    my $userFound=shift;
    my $req2 = HTTP::Request->new(GET => "$config->{jira}->{host}/rest/api/2/user?username=$userFound&expand=groups");
    $req2->header('Content-Type' => "application/json", "Authorization" => $jiraAuthString);
    my $res2 = $userAgent->request($req2);
    if ($res2->is_success) {
        my $user=decode_json($res2->decoded_content);
        return($user);
    }
    else {
       die("Error getting JIRA user: " . $res2->status_line . "\n");
    }
}

sub InitUserAgent {
    my $ua = LWP::UserAgent->new;
    $ua->agent($config->{jira}->{useragent});
    $ua->cookie_jar({ file => "jira_sync.cookies.txt" });
    return($ua);
}

sub GetJiraAuthString {
    my $authstr=qq!$config->{jira}->{user}:$config->{jira}->{password}!;
    $authstr=encode_base64($authstr);
    $authstr=~s/\s//;
    $authstr="Basic $authstr";
    return($authstr);
}

sub InitLdap {
    my $ldap = Net::LDAP->new($config->{ldap}->{host})
                    or die "Could not connect to ldap:\n$@";

    my $bindResults='default';
    my $attempts=0;
    InfoMsg("Attempting to bind to ldap: ");
    while($bindResults ne '' && $attempts<10){
        print "...";
        my $message=$ldap->bind($config->{ldap}->{bindstring}, password => $config->{ldap}->{password});
        $bindResults=$message->{errorMessage};
        $attempts++;
        if($bindResults eq ''){last};
        sleep(1);
    }
    print "\n";
    if($bindResults ne ''){
        die("failed to bind to ldap after $attempts attempts\n$bindResults\n");
    }else{
        InfoMsg("Successful bind to ldap");
        return($ldap);
    }
}

sub LoadConfig {
    my $file=shift;
    local $/ = undef;
    open FILE, $file or die "Couldn't open config $file: $!";
    binmode FILE;
    my $string = <FILE>;
    close FILE;
    return(decode_json($string));
}

sub DebugMsg {
    my $msg=shift;
    if($debug){
        print "---------------------------------\n$msg\n";
    }
}

sub InfoMsg {
    my $msg=shift;
    print "---------------------------------\n$msg\n";
}