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
my $remote = EucaTest->new( { password => "foobar"} );
$remote->sync_keys();
my $local  = EucaTest->new( { host     => "local" } );

my $admin_cred = $remote->get_credpath();
my @machines   = $remote->get_machines("clc");
my $CLC        = $machines[0];

### S3cmd configuration

### Copy over policies and cert
$local->sys( "scp -o StrictHostKeyChecking=no -r policy root\@" . $CLC->{'ip'} . ":" );
### Setup environment for quota testing
my $policy_account = "engr3";
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
my $test1_cred = $remote->get_cred( $policy_account, $policy_user1 );
my $test2_cred = $remote->get_cred( $policy_account, $policy_user2 );

$remote->sys("for cmd in `ls -1 /usr/bin/euca-describe-*`; do echo \$cmd; \$cmd;done");
$remote->sys("for cmd in `ls -1 $remote->{EUCADIR}/usr/sbin/euca-describe-*`; do echo \$cmd; \$cmd;done");

test_image();
test_snap();
test_volume_number();
test_volume_size();
test_instance();

$remote->sys("for cmd in `ls -1 /usr/bin/euca-describe-*`; do echo \$cmd; \$cmd;done");
$remote->sys("for cmd in `ls -1 $remote->{EUCADIR}/usr/sbin/euca-describe-*`; do echo \$cmd; \$cmd;done");

$remote->set_credpath($admin_cred);
$remote->sys("euare-accountdel -ra " . $policy_account);
$remote->sys("rm -rf eucarc-*");
$remote->do_exit();

sub test_image{
	#################################################################
	#### IMAGE NUMBER POLICY     ####################################
	#################################################################
	my $policy_in_test = "image-number-2";
	my $allowed_ops = 2;
	$remote->test_name("Policy under test is $policy_in_test");
	$remote->euare_attach_policy_user( $policy_user1, $policy_in_test, "policy/" . $policy_in_test . ".policy", $policy_account );

	### SET Creds so that i am acting as $policy_user1
	$remote->set_credpath($test1_cred);
	
	my $bucket_prefix = "$policy_in_test-$time";
	my $bucket_name = $bucket_prefix;
	my $test_file = "testfile_1MB";
	$remote->generate_random_file($test_file, 1);
	$remote->sys( "cp $test_file $test_file" . "0" );
	$remote->sys( "cp $test_file $test_file" . "1" );
	$remote->sys( "cp $test_file $test_file" . "2" );
	$remote->sys("euca-describe-images");
	for ( my $i = 0 ; $i < ($allowed_ops + 1)  ; $i++ ) {
		#$remote->test_name("Upload the file to $allowed_ops buckets");
		## BUNDLE THE IMAGE
		if ( !$remote->found( "euca-bundle-image -i $test_file$i", qr/Generating manifest/ ) ) {
				$remote->fail("Unable to bundle image");
		} 
		
		## UPLOAD THE BUNDLE
		if ( $remote->found( "euca-upload-bundle -b $bucket_name -m /tmp/$test_file$i.manifest.xml", qr/Uploaded image/ ) ) {
			### UPLOAD WAS A SUCCESS
			if( $remote->found("euca-register $bucket_name/$test_file$i.manifest.xml", qr/emi-/) ){
				### REGISTER SUCEEDED
				if( $i < $allowed_ops){
					$remote->pass("Properly allowed register of image under threshold");
				}else{
					$remote->fail("Did not allow a registration that should have worked");
				}
			}else{
				### REGISTER FAILED
				if( $i < $allowed_ops){
					$remote->fail("Did not allow a registration that should have worked");
				}else{
					$remote->pass("Properly stopped register of image over threshold");
				}
			}
	
		}else { 
			$remote->fail("Unable to upload image");
		}
	
	}
	
	### CLEANUP IMAGES
	$remote->sys("for img in `euca-describe-images | grep testfile | awk '{print \$2}'`; do euca-deregister \$img; done");
	$remote->sys("for img in `euca-describe-images | grep testfile | awk '{print \$2}'`; do euca-deregister \$img; done");
	
	### CLEAR BUCKET
	if ( $remote->found( "euca-delete-bundle -b $bucket_name --clear", qr/Unable/ ) ) {
					$remote->fail("Error in clearing bucket $bucket_name");
				}
	
$remote->sys("rm -f $test_file");
$remote->set_credpath($admin_cred);
$remote->euare_detach_policy_user( $policy_user1, $policy_in_test, $policy_account);
}

sub test_snap{
#################################################################
#### SNAPSHOT NUMBER POLICY     #################################
#################################################################
	my $policy_in_test = "snapshot-number-3";
	my $allowed_ops = 3;
	$remote->test_name("Policy under test is $policy_in_test");
	$remote->euare_attach_policy_user( $policy_user1, $policy_in_test, "policy/" . $policy_in_test . ".policy", $policy_account );

	### SET Creds so that i am acting as $policy_user1
	$remote->set_credpath($test1_cred);
	my @partition_response = $remote->sys("euca-describe-availability-zones | head -1  | awk '{print \$2}'");
	my $partition = $partition_response[0];
	chomp($partition);
	my $vol_id = $remote->create_volume($partition, {size=> 1} );
	$remote->sys("euca-describe-snapshots");	
	for ( my $i = 0 ; $i < ($allowed_ops + 1)  ; $i++ ) {
		#$remote->test_name("Upload the file to $allowed_ops buckets");
		## BUNDLE THE IMAGE
		if( ! defined $vol_id){
			$remote->fail("Volume did not create properly");
			last;
		}
		## CREATE THE SNAPSHOT
		if( $remote->found("euca-create-snapshot $vol_id", qr/pending/) ){
			### SNAPSHOT SUCEEDED
			if( $i < $allowed_ops){
				$remote->pass("Properly allowed snapshot  under threshold");
			}else{
				$remote->fail("Did not allow a snapshot that should have worked");
			}
		}else{
			### SNAPSHOT FAILED
			if( $i < $allowed_ops){
				$remote->fail("Did not allow a snapshot that should have worked");
			}else{
				$remote->pass("Properly stopped snapshot over threshold");
			}
		}
	}
	
	## REMOVE SNAPS
	$remote->sys("euca-describe-snapshots");
	my @snaps = $remote->sys("euca-describe-snapshots | awk '{print \$2}'");
	
	while ($remote->found("euca-describe-snapshots",qr/pending/)){
		sleep(30);
	}
	foreach my $snap (@snaps){
		chomp($snap) ;
        $local->sys("echo $snap >> ../etc/vols.lst");
        $remote->delete_snapshot($snap);
    }
	$remote->delete_volume($vol_id);
	$remote->set_credpath($admin_cred);
	$remote->euare_detach_policy_user( $policy_user1, $policy_in_test, $policy_account);
}

sub test_instance{
#################################################################
#### SNAPSHOT NUMBER POLICY     #################################
#################################################################
	my $policy_in_test = "instance-number-3";
	my $allowed_ops = 3;
	$remote->test_name("Policy under test is $policy_in_test");
	$remote->euare_attach_policy_user( $policy_user1, $policy_in_test, "policy/" . $policy_in_test . ".policy", $policy_account );
	
	### SET Creds so that i am acting as $policy_user1
	$remote->set_credpath($test1_cred);
	my $group_name = "quota-$time";
	$remote->add_group($group_name);
	my $emi = $remote->get_emi();	
	$remote->sys("euca-describe-instances");
	$remote->sys("euca-describe-availability-zones verbose");
	my @instances = ();
	for ( my $i = 0 ; $i < ($allowed_ops + 1)  ; $i++ ) {
		#$remote->test_name("Upload the file to $allowed_ops buckets");
		## RUN THE INSTANCE
		my @instance = $remote->sys("euca-run-instances $emi -g $group_name | grep -v RESERVATION");
		if( $instance[0] =~ "pending" ){
			### INSTANCE SUCEEDED
			my @instance_fields = split( /\s+/, $instance[0]);
			push(@instances, $instance_fields[1]);
			if( $i < $allowed_ops){
				$remote->pass("Properly allowed instance  under threshold");
			}else{
				$remote->fail("Did not allow a instance that should have worked");
			}
		}else{
			### INSTANCE FAILED
			if( $i < $allowed_ops){
				$remote->fail("Did not allow a instance that should have worked");
			}else{
				$remote->pass("Properly stopped instance over threshold");
			}
		}
	}
	
	sleep 10;
	## TERMINATE INSTANCES
    foreach my $instance (@instances){
    	$remote->terminate_instance($instance)
    }
	$remote->delete_group($group_name);
	$remote->set_credpath($admin_cred);
	$remote->euare_detach_policy_user( $policy_user1, $policy_in_test, $policy_account);
}


sub test_volume_number{
#################################################################
#### SNAPSHOT NUMBER POLICY     #################################
#################################################################
	my $policy_in_test = "volume-number-4";
	my $allowed_ops = 4;
	$remote->test_name("Policy under test is $policy_in_test");
	$remote->test_name("Deleting existing volumes");
	$remote->sys("for vol in `euca-describe-volumes | awk '{print \$2}'`; do euca-delete-volume \$vol; done");
	$remote->euare_attach_policy_user( $policy_user1, $policy_in_test, "policy/" . $policy_in_test . ".policy", $policy_account );

	### SET Creds so that i am acting as $policy_user1
	$remote->set_credpath($test1_cred);
	$remote->sys("euca-describe-volumes");
	
	for ( my $i = 0 ; $i < ($allowed_ops + 1)  ; $i++ ) {
		## CREATE THE VOLUME
		my @partition_response = $remote->sys("euca-describe-availability-zones | head -1  | awk '{print \$2}'");
        my $partition = $partition_response[0];
        chomp($partition);
		if( $remote->found("euca-create-volume -z $partition -s 1", qr/creating/) ){
			### VOLUME SUCEEDED
			if( $i < $allowed_ops){
				$remote->pass("Properly allowed volume  under threshold");
			}else{
				$remote->fail("Did not allow a volume that should have worked");
			}
			$remote->sys("euca-describe-volumes");
		}else{
			### VOLUME FAILED
			if( $i < $allowed_ops){
				$remote->fail("Did not allow a volume that should have worked");
			}else{
				$remote->pass("Properly stopped volume over threshold");
			}
			$remote->sys("euca-describe-volumes");
		}
	}
	
	## REMOVE Volumes
	my @vols = $remote->sys("euca-describe-volumes | awk '{print \$2}'");
    sleep(30);
    foreach my $vol (@vols){
        print `echo $vol >> ../etc/vols.lst`;
        $remote->delete_volume($vol);
    }
	$remote->set_credpath($admin_cred);
	$remote->euare_detach_policy_user( $policy_user1, $policy_in_test, $policy_account);
}

sub test_volume_size{
#################################################################
#### SNAPSHOT NUMBER POLICY     #################################
#################################################################
	my $policy_in_test = "volume-total-size-25";
	my $allowed_ops = 2;
	$remote->test_name("Policy under test is $policy_in_test");
	$remote->euare_attach_policy_user( $policy_user1, $policy_in_test, "policy/" . $policy_in_test . ".policy", $policy_account );

	### SET Creds so that i am acting as $policy_user1
	$remote->set_credpath($test1_cred);
	$remote->sys("euca-describe-volumes");
	my @partition_response = $remote->sys("euca-describe-availability-zones | head -1  | awk '{print \$2}'");
    my $partition = $partition_response[0];
    chomp($partition);
	#my $vol_id = $remote->create_volume("PARTI00", {size=> 1} );
	for ( my $i = 0 ; $i < ($allowed_ops + 1)  ; $i++ ) {
		## CREATE THE VOLUME
		if( $remote->found("euca-create-volume -z $partition -s 10", qr/creating/) ){
			### VOLUME SUCEEDED
			if( $i < $allowed_ops){
				$remote->pass("Properly allowed volume under threshold");
			}else{
				$remote->fail("Did not block a volume that should have worked");
			}
		}else{
			### VOLUME FAILED
			if( $i < $allowed_ops){
				$remote->fail("Did not allow a volume that should have worked");
			}else{
				$remote->pass("Properly stopped volume over threshold");
			}
		}
	}
	
	## REMOVE VOLS
	my @vols = $remote->sys("euca-describe-volumes | awk '{print \$2}'");
    sleep(30);
    foreach my $vol (@vols){
        print `echo $vol >> ../etc/vols.lst`;
        $remote->delete_volume($vol);
    }
	
	$remote->set_credpath($admin_cred);
	$remote->euare_detach_policy_user( $policy_user1, $policy_in_test, $policy_account);
}