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

$remote->sys("for cmd in `ls -1 /usr/bin/euca-describe-*`; do echo \$cmd; \$cmd;done");
$remote->sys("for cmd in `ls -1 $remote->{EUCADIR}/usr/sbin/euca-describe-*`; do echo \$cmd; \$cmd;done");

### Copy over policies and cert
$local->sys( "scp -o StrictHostKeyChecking=no -r policy root\@" . $CLC->{'ip'} . ":" );

### Setup environment for resource quota testing
my $policy_account1 = "engr1";
my $policy_user1   = "test1";
my $policy_user2   = "test2";
my $policy_group   = "policy-group";

$remote->euare_create_account($policy_account1);

### GET Credentials for both users
my $admin1_cred = $remote->get_cred($policy_account1, "admin" );
$remote->euare_create_user( $policy_user1, $policy_account1 );
$remote->euare_create_user( $policy_user2, $policy_account1 );
$remote->euare_create_group( $policy_group, "/", $policy_account1 );

my $user1_cred = $remote->get_cred($policy_account1, $policy_user1 );
my $user2_cred = $remote->get_cred($policy_account1, $policy_user2 );
## Allow all actions for this group so that we can stress the different quota types
$remote->euare_attach_policy_group( $policy_group, "allowall", $ALLOWALLPOLICY, $policy_account1 );
$remote->euare_group_add_user( $policy_group, $policy_user1, $policy_account1 );
$remote->euare_group_add_user( $policy_group, $policy_user2, $policy_account1 );

$remote->set_credpath($admin1_cred);
my @partition_response = $remote->sys("euca-describe-availability-zones | head -1  | awk '{print \$2}'");
my $partition = $partition_response[0];
chomp($partition);
my $volume = $remote->create_volume($partition, {size=>1});
my $snapshot = $remote->create_snapshot($volume);
sleep(40);
test_resource_policy("snapshot",$snapshot);
test_resource_policy("volume",$volume);
test_resource_policy("vmtype", "m1.large");
my $emi = $remote->get_emi();
test_resource_policy("image", $emi);
my $group = "resource-policy-group";
$remote->add_group($group);
test_resource_policy("securitygroup", $group);
my $keypair = "resource-policy-keypair";
$remote->add_keypair($keypair);
test_resource_policy("keypair", $keypair);
my $instance = $remote->run_instance();
test_resource_policy("instance", $instance->{'id'});
test_resource_policy("availabilityzone", $partition);
$remote->set_credpath($admin_cred);
$remote->sys("euare-accountdel -ra $policy_account1");

$remote->sys("for cmd in `ls -1 /usr/bin/euca-describe-*`; do echo \$cmd; \$cmd;done");
$remote->sys("for cmd in `ls -1 $remote->{EUCADIR}/usr/sbin/euca-describe-*`; do echo \$cmd; \$cmd;done");

$remote->do_exit();

sub test_resource_policy{
#################################################################
#### SNAPSHOT NUMBER POLICY     #################################
#################################################################
    $remote->set_credpath($admin_cred);
	my $resource_in_test = shift;
	my $id = shift;
	my $policy_name = $resource_in_test . "-" . $id;
	my $resource_policy = << "POLICY";
{
  "Statement": [
    {
      "Action": [
        "ec2:*"
      ],
      "Effect": "Deny",
      "Resource": "arn:aws:ec2:::<resource>/<id>"
    }
  ]
}
POLICY
    $resource_policy =~ s/<resource>/$resource_in_test/g;
    $resource_policy =~ s/<id>/$id/g;
	$remote->test_name("Resource policy under test is $resource_in_test");
	$remote->euare_attach_policy_user( $policy_user1, $policy_name, $resource_policy, $policy_account1);
	if($resource_in_test =~ /volume/){
		
		$remote->set_credpath($user1_cred);
		#my @del_response = $remote->sys("euca-delete-volume $id");
		
		if( $remote->found("euca-delete-volume $id", qr/Not authorized to delete volume/)){
			$remote->pass("Properly blocked user1 from using $resource_in_test $id");
		}else{
			$remote->fail("Deleting of volume was either allowed or failed in an unexpected way");
		}
	   $remote->set_credpath($user2_cred);
	   $remote->delete_volume($id);		
	}
	if($resource_in_test =~ /snapshot/){
        
        $remote->set_credpath($user1_cred);
        
        
        if( !$remote->found("euca-delete-snapshot $id",qr/SNAPSHOT.*$id/)){
            $remote->pass("Properly blocked user1 from using $resource_in_test $id");
        }else{
            $remote->fail("Deleting of snapshot was either allowed or failed in an unexpected way");
        }
       $remote->set_credpath($user2_cred);
       $remote->delete_snapshot($id);     
    }
	if($resource_in_test =~ /vmtype/){
		$remote->set_credpath($user1_cred);
		my $emi = $remote->get_emi();
        my @instance_response = $remote->sys("euca-run-instances $emi -t $id");
        if( $instance_response[1] =~ /INSTANCE/){
            $remote->fail("Was able to use $resource_in_test $id or another error occured");
        }else{
            $remote->pass("Properly blocked user1 from using $resource_in_test $id");
        }
       $remote->sys("for img in `euca-describe-instances | awk '{print \$2}'`; do euca-terminate-instances \$img; done");
       $remote->set_credpath($user2_cred);
       @instance_response = $remote->sys("euca-run-instances $emi -t $id");
       if( $instance_response[1] =~ /$id/){
       	    $remote->pass("Properly allowed $policy_user2 to user $resource_in_test $id");
       }else{
       	    $remote->fail("Did not allow $policy_user2 to use $resource_in_test $id");
       }     
	}
	if($resource_in_test =~ /image/){
        $remote->set_credpath($user1_cred);
        my @instance_response = $remote->sys("euca-run-instances $id");
        if( $instance_response[1] =~ /INSTANCE.*$id/){
            $remote->fail("Was able to use $resource_in_test $id or another error occured");
        }else{
            $remote->pass("Properly blocked user1 from using $resource_in_test $id");
        }
       
       $remote->set_credpath($user2_cred);
       @instance_response = $remote->sys("euca-run-instances $id");
       if( $instance_response[1] =~ /$id/){
            $remote->pass("Properly allowed $policy_user2 to user $resource_in_test $id");
       }else{
            $remote->fail("Did not allow $policy_user2 to use $resource_in_test $id");
       }
       $remote->sys("for img in `euca-describe-instances | awk '{print \$2}'`; do euca-terminate-instances \$img; done");     
       sleep 60;
    }
    if($resource_in_test =~ /securitygroup/){
        $remote->set_credpath($user1_cred);
        $remote->test_name("Terminating all existing instances");
        $remote->sys("for img in `euca-describe-instances | awk '{print \$2}'`; do euca-terminate-instances \$img; done");
        sleep 60;    
        my $emi = $remote->get_emi();
        my @instance_response = $remote->sys("euca-run-instances $emi -g $id");
        if( $instance_response[1] =~ /INSTANCE.*$id/){
            $remote->fail("Was able to use $resource_in_test $id or another error occured");
        }else{
            $remote->pass("Properly blocked user1 from using $resource_in_test $id");
        }
        $remote->sys("euca-describe-groups");
       
       $remote->set_credpath($user2_cred);
       @instance_response = $remote->sys("euca-run-instances $emi -g $id");
       if( $instance_response[1] =~ /INSTANCE/){
            $remote->pass("Properly allowed $policy_user2 to user $resource_in_test $id");
       }else{
            $remote->fail("Did not allow $policy_user2 to use $resource_in_test $id");
       }
       $remote->sys("for img in `euca-describe-instances | awk '{print \$2}'`; do euca-terminate-instances \$img; done");     
    }
    if($resource_in_test =~ /keypair/){
        $remote->set_credpath($user1_cred);
        my $emi = $remote->get_emi();
        my @instance_response = $remote->sys("euca-run-instances $emi -k $id");
        if( $instance_response[1] =~ /INSTANCE.*$id/){
            $remote->fail("Was able to use $resource_in_test $id or another error occured");
        }else{
            $remote->pass("Properly blocked user1 from using $resource_in_test $id");
        }
        $remote->sys("euca-describe-keypairs");
       
       $remote->set_credpath($user2_cred);
       @instance_response = $remote->sys("euca-run-instances $emi -k $id");
       if( $instance_response[1] =~ /INSTANCE/){
            $remote->pass("Properly allowed $policy_user2 to user $resource_in_test $id");
       }else{
            $remote->fail("Did not allow $policy_user2 to use $resource_in_test $id");
       }
       $remote->sys("for img in `euca-describe-instances | awk '{print \$2}'`; do euca-terminate-instances \$img; done");     
    }
    if($resource_in_test =~ /instance/){
        $remote->set_credpath($user1_cred);
        my @instance_response = $remote->sys("euca-terminate-instances $id");
        if( $instance_response[0] =~ /INSTANCE.*$id/){
            $remote->fail("Was able to terminate $resource_in_test $id or another error occured");
        }else{
            $remote->pass("Properly blocked user1 from terminating $resource_in_test $id");
        }      
       $remote->set_credpath($user2_cred);
       @instance_response = $remote->sys("euca-terminate-instances $id");
       if( $instance_response[0] =~ /INSTANCE/){
            $remote->pass("Properly allowed $policy_user2 to terminate $resource_in_test $id");
       }else{
            $remote->fail("Did not allow $policy_user2 to use $resource_in_test $id");
       }
       $remote->sys("for img in `euca-describe-instances | awk '{print \$2}'`; do euca-terminate-instances \$img; done");     
    }
    if($resource_in_test =~ /availabilityzone/){
        $remote->set_credpath($user1_cred);
        my $emi = $remote->get_emi();
        my @instance_response = $remote->sys("euca-run-instances $emi -z $id");
        if( $instance_response[1] =~ /INSTANCE.*$id/){
            $remote->fail("Was able to use $resource_in_test $id or another error occured");
        }else{
            $remote->pass("Properly blocked user1 from using $resource_in_test $id");
        }
        $remote->sys("euca-describe-availability-zones verbose");
       
       $remote->set_credpath($user2_cred);
       @instance_response = $remote->sys("euca-run-instances $emi -z $id");
       if( $instance_response[1] =~ /INSTANCE/){
            $remote->pass("Properly allowed $policy_user2 to user $resource_in_test $id");
       }else{
            $remote->fail("Did not allow $policy_user2 to use $resource_in_test $id");
       }
       $remote->sys("for img in `euca-describe-instances | awk '{print \$2}'`; do euca-terminate-instances \$img; done");     
    }
	### SET Creds so that i am acting as admin
	$remote->set_credpath($admin1_cred);
	$remote->euare_detach_policy_user( $policy_user1, $policy_name);
}
