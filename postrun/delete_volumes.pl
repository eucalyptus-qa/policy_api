#!/usr/bin/perl
#============================================================#
#Parts of this file contain code that is licensed under      #
#the following license.					     #
#						             #
#							     #
# Copyright 2005 Network Appliance, Inc. All rights          #
# reserved. Specifications subject to change without notice. #
#                                                            #
# This SDK sample code is provided AS IS, with no support or #
# warranties of any kind, including but not limited to       #
# warranties of merchantability or fitness of any kind,      #
# expressed or implied.  This code is subject to the license #
# agreement that accompanies the SDK.                        #
#                                                            #
#============================================================#

require 5.6.1;
use lib "NetApp";
use NaServer;   
use NaElement;

# Variable declaration

my $args = $#ARGV + 1;
my $filer = "192.168.5.191";
my $user = "root";
my $pw = "zoomzoom";
my $volume_file = shift;

#Invoke routine to retrieve & print volume information
get_volume_info();
#print `rm $volume_file`;
#Retrieve & print volume information : vol name, total size, used size
sub get_volume_info(){

	my $out;

	# check for valid number of parameters
	if ($args < 1)
	{
		print_usage();
	}

	my $s = NaServer->new ($filer, 1, 3);
	my $response = $s->set_style(LOGIN);
	if (ref ($response) eq "NaElement" && $response->results_errno != 0) 
	{
		my $r = $response->results_reason();
		print "Unable to set authentication style $r\n";
		exit 2;
	}
	$s->set_admin_user($user, $pw);
	$s->set_transport_type(HTTP);
	if (ref ($response) eq "NaElement" && $response->results_errno != 0) 
	{
		my $r = $response->results_reason();
		print "Unable to set HTTP transport $r\n";
		exit 2;
	}

	if($args == 1)
	{
#		$out = $s->invoke( "volume-list-info");
		delete_volumes($s);		
	}
}

sub print_usage()
{
	print "Usage: \n";
	print "perl delete_volumes.pl <file-with-newline-separated-list-of-volumes>\n";
	exit (1);
}

sub delete_volumes()
{
	my $conn = shift;
	my $out;
	open(FILE, "$volume_file");
	while(<FILE>) {
		#destroy lun, offline vol and delete it
		chomp;
		my $vol = $_;
		### VIC ADDED THIS SO THAT TESTS LIBS CAN SIMPLY WRITE THE VOL/SNAP ID to the file without doing any other manipulation
		$vol =~ s/-/_/g;
		$out = $conn->invoke("lun-destroy", "path" , "/vol/" . $vol . "/lun1");
	        if ($out->results_status() eq "failed"){
			print($out->results_reason() ."\n");
        	}
		$out = $conn->invoke("volume-offline", "name" , $vol);
	        if ($out->results_status() eq "failed"){
        		print($out->results_reason() ."\n");
			next;
        	}
		$out = $conn->invoke("volume-destroy", "name" , $vol);
	        if ($out->results_status() eq "failed"){
        		print($out->results_reason() ."\n");
        	} else {
			print("Deleted " . $vol . " successfully\n");
		}
	}
	close(FILE);
}
