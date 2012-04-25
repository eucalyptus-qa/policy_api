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
my $remote = EucaTest->new( { password => "foobar", exit_on_fail=> 0} );
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
### Setup environment for quota testing
my $policy_account = "engr";
my $policy_user1   = "test1";
my $policy_user2   = "test2";
my $policy_group   = "policy-group";
$remote->euare_create_account($policy_account);
$remote->euare_create_user( $policy_user1, $policy_account );
$remote->euare_create_user( $policy_user2, $policy_account );
$remote->euare_create_group( $policy_group, "/", $policy_account );
## Allow all actions for this group so that we can stress the different quota types
$remote->euare_attach_policy_group( $policy_group, "allowall", $ALLOWALLPOLICY, $policy_account );
$remote->euare_group_add_user( $policy_group, $policy_user1, $policy_account );
$remote->euare_group_add_user( $policy_group, $policy_user2, $policy_account );
### GET Credentials for both users
my $test1_cred = $remote->get_cred( "engr", $policy_user1 );
my $test2_cred = $remote->get_cred( "engr", $policy_user2 );
my $test_file = "testfile_10MB";
$remote->generate_random_file($test_file, 10);
$remote->sys( "cp $test_file $test_file" . "0" );
$remote->sys( "cp $test_file $test_file" . "1" );
$remote->sys( "cp $test_file $test_file" . "2" );
$remote->sys( "cp $test_file $test_file" . "3" );
$remote->sys( "cp $test_file $test_file" . "4" );

my %policy_to_test;

$policy_to_test{"bucket-number-3"} = 3;
$policy_to_test{"bucket-object-number-3"} = 1;
$policy_to_test{"bucket-size-25"} = 2;
$policy_to_test{"bucket-total-size-25"} = 2;

foreach my $key (keys %policy_to_test){
	test_policy($key, $policy_to_test{$key});
	$remote->euare_detach_policy_user( $policy_user1, $key, $policy_account);
}


sub test_policy{
	my $policy_in_test = shift;
	my $allowed_buckets = shift;
	
	$remote->test_name("Policy under test is $policy_in_test");
	$remote->euare_attach_policy_user( $policy_user1, $policy_in_test, "policy/" . $policy_in_test . ".policy", $policy_account );
	### Test the 3 bucket policy
	
	$remote->test_name("Bundling a 10MB file filled with randomly");
	
	### SET Creds so that i am acting as $policy_user1
	$remote->set_credpath($test1_cred);
	
	$remote->test_name("Upload the file to $allowed_buckets buckets");
	
	my $bucket_prefix = "$policy_in_test-$time";
	my $bucket_name = $bucket_prefix;
	for ( my $i = 0 ; $i < ($allowed_buckets + 1)  ; $i++ ) {
		## BUNDLE THE IMAGE AND MAKE SURE WE GET THE MANIFEST FILE BACK
		
		if ( !$remote->found( "euca-bundle-image -i $test_file$i", qr/Generating manifest/ ) ) {
			$remote->fail("Unable to bundle image");
		} 
		
		if( $policy_in_test =~ /bucket-number/ || $policy_in_test =~ /bucket-total-size/ ){
			$bucket_name = $bucket_prefix . $i;
		}
		
		if ( $remote->found( "euca-upload-bundle -b $bucket_name -m /tmp/$test_file$i.manifest.xml", qr/Uploaded image/ ) ) {
			if ( $i < $allowed_buckets ) {
				$remote->pass("Properly allowed uploading object #$i");
				
			} else {
				$remote->fail("Failure in blocking $bucket_name from uploading $test_file$i");
			}
		}else{
			if ( $i < $allowed_buckets ) {
				### FAIL when number objects is greater than allowed
				$remote->fail("Did not allow upload of $bucket_name and uploading $test_file$i");
			}else {
				$remote->pass("Properly blocked uploading object #$i");
			}
		}
	}
	## Create 1 bucket with user2
	$remote->set_credpath($test2_cred);
	if ( !$remote->found( "euca-bundle-image -i $test_file", qr/Generating manifest \/tmp\/$test_file.manifest.xml/ ) ) {
		$remote->fail("Unable to bundle image");
	}
	
	if ( !$remote->found( "euca-upload-bundle -b $bucket_prefix" . $allowed_buckets . " -m /tmp/$test_file.manifest.xml", qr/Uploaded image/ ) ) {
		$remote->fail( "Failure in trying to create $bucket_prefix" . $allowed_buckets . " and uploading $test_file" );
	}
	if ( $remote->found( "euca-delete-bundle -b $bucket_prefix" . $allowed_buckets . " --clear", qr/Unable/ ) ) {
			$remote->fail("Error in clearing bucket $bucket_prefix" . $allowed_buckets);
		}
	### DELETE THE CORRECTLY CREATED BUCKETS
	
	for ( my $i = 0 ; $i < $allowed_buckets  ; $i++ ) {
		### IF I AM USING DIFFERENT BUCKETS
		if( $policy_in_test =~ /bucket-number/ || $policy_in_test =~ /bucket-total-size/){
			$bucket_name = $bucket_prefix . $i;
		}else{
				if ( $remote->found( "euca-delete-bundle -b $bucket_name --clear", qr/Unable/ ) ) {
					$remote->fail("Error in clearing bucket $bucket_name");
				}
				last;
		}
		if ( $remote->found( "euca-delete-bundle -b $bucket_name --clear", qr/Unable/ ) ) {
			$remote->fail("Error in clearing bucket $bucket_name");
		}
	}
    $remote->set_credpath($admin_cred);
}

$remote->sys("for cmd in `ls -1 /usr/bin/euca-describe-*`; do echo \$cmd; \$cmd;done");
$remote->sys("for cmd in `ls -1 $remote->{EUCADIR}/usr/sbin/euca-describe-*`; do echo \$cmd; \$cmd;done");

$remote->sys("euare-accountdel -ra engr");
$remote->sys("rm -f $test_file");
$remote->sys("rm -rf eucarc-*");
$remote->do_exit();
