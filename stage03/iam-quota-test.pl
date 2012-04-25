#!/usr/bin/perl
#
############################
# EUARE Tests
#   by vic.iglesias@eucalyptus.com
############################
use strict;

open( STDERR, ">&STDOUT" );

######### VIC ADDED #####################
use Cwd qw(abs_path);
use lib abs_path("../share/perl_lib/EucaTest/lib");
use EucaTest;

#### Constants

my $ALLOWALLPOLICY = "./policy/allowall.policy";

my $time= time();
my $remote = EucaTest->new( { password => "foobar" });
$remote->sync_keys();
my $local  = EucaTest->new( { host     => "local" } );

my $admin_cred = $remote->get_credpath();
my @machines   = $remote->get_machines("clc");
my $CLC        = $machines[0];

### S3cmd configuration
$remote->sys("for cmd in `ls -1 /usr/bin/euca-describe-*`; do echo \$cmd; \$cmd;done");
$remote->sys("for cmd in `ls -1 $remote->{EUCADIR}/usr/sbin/euca-describe-*`; do echo \$cmd; \$cmd;done");

### Copy over policies and cert
$local->sys( "scp -o StrictHostKeyChecking=no -r policy root\@" . $CLC->{'ip'} . ":" );
$local->sys( "scp -o StrictHostKeyChecking=no  ../share/testfile* root\@" . $CLC->{'ip'} . ":" );


### Setup environment for quota testing
my $policy_account1 = "engr1";
my $policy_account2 = "engr2";

my $policy_user1   = "test1";
my $policy_user2   = "test2";
my $policy_group   = "policy-group";

$remote->euare_create_account($policy_account1);
$remote->euare_create_account($policy_account2);

#$remote->euare_create_user( $policy_user1, $policy_account1 );
#$remote->euare_create_user( $policy_user2, $policy_account2 );

#$remote->euare_create_group( $policy_group, "/", $policy_account1 );
## Allow all actions for this group so that we can stress the different quota types
#$remote->euare_attach_policy_group( $policy_group, "allowall", $ALLOWALLPOLICY, $policy_account );
### GET Credentials for both users
my $admin1_cred = $remote->get_cred($policy_account1, "admin" );
my $admin2_cred = $remote->get_cred($policy_account2, "admin" );

test_iam_quota("group-number-3", 3);
test_iam_quota("user-number-4", 3);



$remote->set_credpath($admin_cred);
$remote->sys("euare-accountdel -ra $policy_account1");
$remote->sys("euare-accountdel -ra $policy_account2");
$remote->sys("rm -rf eucarc-*");

$remote->sys("for cmd in `ls -1 /usr/bin/euca-describe-*`; do echo \$cmd; \$cmd;done");
$remote->sys("for cmd in `ls -1 $remote->{EUCADIR}/usr/sbin/euca-describe-*`; do echo \$cmd; \$cmd;done");
$remote->do_exit();

sub test_iam_quota{
#################################################################
#### SNAPSHOT NUMBER POLICY     #################################
#################################################################
	my $policy_in_test= shift;
	my $allowed_ops = shift;
	
	$remote->test_name("Policy under test is $policy_in_test");
	$remote->euare_attach_policy_account( $policy_account1, $policy_in_test, "policy/" . $policy_in_test . ".policy");
	
	### SET Creds so that i am acting as $policy_user1
	$remote->set_credpath($admin1_cred);
	my $cmd = "";
	my $regex = qr//;

		
	for ( my $i = 0 ; $i < ($allowed_ops + 1)  ; $i++ ) {
		## CREATE THE SNAPSHOT
		if( $policy_in_test =~ /group/){
			$cmd = "euare-groupcreate -v -g group-policy-$i";
			$regex = qr/group-policy-$i/;
		}
		if( $policy_in_test =~ /user/){
			$cmd = "euare-usercreate -v -u user-policy-$i";
			$regex = qr/user-policy-$i/;
		}
		if( $remote->found($cmd, $regex) ){
			### SNAPSHOT SUCEEDED
			if( $i < $allowed_ops){
				$remote->pass("Properly allowed group creation  under threshold");
			}else{
				$remote->fail("Did not allow a group creation that should have worked");
			}
		}else{
			### SNAPSHOT FAILED
			if( $i < $allowed_ops){
				$remote->fail("Did not allow a group creation that should have worked");
			}else{
				$remote->pass("Properly stopped group creation over threshold");
			}
		}
	}
	
	## REMOVE Groups
	$remote->set_credpath($admin_cred);
	$remote->euare_detach_policy_account( $policy_account1, $policy_in_test);
}
