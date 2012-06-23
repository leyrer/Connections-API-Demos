#!/usr/bin/perl

# Uploads a file into the Files application of an BM Connections Community using multipart POST
# Similar to http://www.lotus.com/ldd/lcwiki.nsf/dx/Adding_a_file_using_a_multipart_POST_ic301

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use LWP::UserAgent;
use HTTP::Request::Common;
use XML::XPath;
use JSON;


## Parse options and print usage if there is a syntax error,
## or if usage was explicitly requested.
our $opt_server = ''; our $opt_username = ''; our $opt_password = '';
our $opt_file = ''; our $opt_help = ''; our $opt_man= ''; our $opt_community = '';
GetOptions( "server=s", "username=s", "password=s", "file=s", "community=s", "help", "man",
			) or pod2usage(2);
pod2usage(1) if $opt_help;
pod2usage(-verbose => 2) if $opt_man;


# Initiate connection to the Connections server
my $connectionsUA = connect2Connection($opt_username, $opt_password, $opt_server);

# Fetch the ID for the Communty with the given name
my $communityID = retrieveCommunityID($connectionsUA, $opt_server, $opt_community);

# Generate the URL to the Community library we want to POST the file to
# The URL can change, for example to https://files.example.com/basic/api...
# TODO Make URL generation more robust
my $filesurl = 'https://' . $opt_server . "/files/basic/api/communitylibrary/$communityID/feed";

# Create Data for Connections upload
my $c = createUploadContent($opt_file);

# Create POST request via HTTP::Request::Common
my $r = POST $filesurl, Content_Type => 'form-data', Content => $c;

# Send request and save response
my $res = $connectionsUA->request($r);

# Check the outcome of the response
if ( $res->is_success ) {
	my $resp = parseResponse($res->decoded_content);
	if( $resp->{'status'} eq '' or $resp->{'status'} eq '200' ) {	
		# yes, if there is no statuscode in  the metadata of the response html file, all went well
	   	print "File '$opt_file' uploaded successfully to Community '$opt_community'.\n";
		print "\tPublished: " . $resp->{'code'}->{'published'} . "\n";
		print "\tID: " . $resp->{'code'}->{'id'} . "\n";
	} else {	# and yes, they are sending http response 200 even if there was an error
		print "Error " . $resp->{'status'} . " - '" . $resp->{'code'}->{'errorCode'} . "' while uploading.\n";
		print "Detailed errormessage: " . $resp->{'code'}->{'errorMessage'} . "\n";
		exit $resp->{'status'};
	}
} else {
   	print "\tError while talking to the server: " . $res->status_line, "\n";
	print $res->decoded_content;
	print "\n";
}

exit;


# Create UserAgent Object, get nounce, set server certificate for SSL, set realm
sub connect2Connection {
	my($usr, $pwd, $srv) = @_;
	my $port = "443";

	if ( $usr eq '' ) {
		pod2usage( -verbose => 2, -message => "$0: Please state the IBM Connections username!\n");
		exit;
	}
	if ( $pwd eq '' ) {
		pod2usage( -verbose => 2, -message => "$0: Please state the IBM Connections password!\n");
		exit;
	}
	if ( $srv eq '' ) { 
		pod2usage( -verbose => 2, -message => "$0: Please state the IBM Connections servername!\n" );
		exit;
	}

	my $ua = LWP::UserAgent->new (
			agent => "file2Connections",
	);

	# the default realm for Connections is 'lotus-connections'
	$ua->credentials( $srv . ':' . $port, 'lotus-connections', $usr, $pwd );
	push @{ $ua->requests_redirectable }, 'POST';
	# Make sure, that LWP recognizes the server certificate
	$ua->ssl_opts( SSL_ca_file => './server.pem' );

	# get nonce and set the corresponding http header with it's value
	my $nonce = getNonce($ua, $srv);
	$ua->default_header('X-Update-Nonce' => $nonce);

	return $ua;
}

# Create Data structure with the file to upload and corresponding metadata for multipart/form-data upload
sub createUploadContent {
	my ($file) = @_;

	die "Given file '$file' not found!"
		if(not -f $file);

	$file =~ /([^\\\/]+)$/;
	my $filename = $1;

	my $content = {
		label		=> $filename,
		description	=> 'Always add a nice description.',	# optional
		file 		=> [ $file ],
		tag			=> 'automated_update',					# Currently, only one tag can be set with perl
# 		Adding multiple tags via a Array reference is not working, as all array references are apparently interpreted as file uploads
# 		http://search.cpan.org/~gaas/HTTP-Message-6.03/lib/HTTP/Request/Common.pm
# 		tag			=> ['perl_demo', 'automated_update'],	
	};
	return $content;
}

# Response from IBM Connections is a HTML page with embedded meta tags and json.
# Parse this into a useful hash
sub parseResponse {
	my ($x) = @_;
	my %response;

	# No, at this time I do not want to get HTML::Parser in to properly parse the HTML.
	# Give me a break!
	$x =~ /\<meta name=\"(status)\" content=\"(\d+)\"/sm;
	$response{'status'} = (not defined $2) ? '' : $2;
	$x =~ s/^(.*?)\<body (.*?)\>//sm;
	$x =~ s/\<\/body.*$//sm;
	$x =~ s/\&quot\;/\"/gsm;	# why are the json quotes encoded ???
	my $resp = decode_json $x;	# convert json to hash
	$response{'code'} = $resp;
	return(\%response);
}

# Retrieve the Community ID from the community entry Atom document.
# Similar to http://www.lotus.com/ldd/lcwiki.nsf/dx/Retrieving_a_remote_applications_list_ic301
sub retrieveCommunityID{
	my($ua, $srv, $commname) = @_;
	my $ralink = 'http://www.ibm.com/xmlns/prod/sn/remote-applications';

	# The URL can change, for example to https://files.example.com/basic/api...
	# TODO Make URL generation more robust
	my $url = 'https://' . $srv . '/communities/service/atom/communities/all?search=' . $commname;

	my $req = HTTP::Request->new( GET => $url );
	my $res = $ua->request($req);

	# Check the outcome of the response
	if( not $res->is_success ) {
		die "Error " . $res->{'status'} . " getting the Comunities service document. Error: '" . $res->{'code'}->{'errorCode'} . "\n";
	} 
	
	# Search the ATOM feed for the ID tag inside the Community entry we are looking for.
	# In case the Connections Search found several entries, we are now specifically looking 
	# inside the XML stream for an entry with the given Community name
	my $xp = XML::XPath->new( xml => $res->content);
	my @applist= $xp->findnodes( "/feed/entry[title='$commname']/id" );

	# Did we find exactly one Community with a valid ID?
	if ($#applist == 0 and $applist[0]->string_value ne '') {
		$applist[0]->string_value =~ /communityUuid=(.*?)$/,
		return $1;
	} else {
		die "Could not retrieve the ID for Community '$commname'.\n";
	}
}


# Get the nonce, which ensures the request is secure. 
# http://www.lotus.com/ldd/lcwiki.nsf/dx/Getting_a_cryptographic_key_ic301
# The Nonce represents a unique data string generated by the server 
# upon request that you can provide to secure the request.
sub getNonce {
	my($ua, $srv) = @_;

	# The URL can change, for example to https://files.example.com/basic/api...
	# TODO Make URL generation more robust
	my $url = 'https://' . $srv . '/files/basic/api/nonce';
	my $req = HTTP::Request->new( GET => $url );
	my $res = $ua->request($req);

	# Check the outcome of the response
	if( not $res->is_success ) {
    	print "Couldn't get nounce. Request/Response info:\n";
		print "~"x80 . "\n";
		print $req->as_string . "\n";
		print "-"x80 . "\n";
		# TODO parse the returned json, if there is any
		print $res->decoded_content;	# just dump the response
		print "\n";
    	die "Error getting nounce: " . $res->status_line, "\n";
	} 
	return($res->decoded_content);
}


__END__

=head1 NAME

file2ConnCommunity - Upload a local file into the file store of an IBM Connections Community

=head1 SYNOPSIS

file2ConnCommunity.pl [-help|man] -user connections_username -password connections_password 
-server connections_server -file filename -community connections_community

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-user>

The name of the connections user for whom the files should be uploaded.

=item B<-password>

The IBM Connections password for the user.

=item B<-server>

The servername (DNS hostname) ot the IBM Connections installation the file should be uploaded to.

=item B<-file>

The file to be uploaded.

=item B<-community>

The name of the IBM Connections Community to upload the file to

=back

=head1 DESCRIPTION

B<file2ConnCommunity> will send the given file to the given Community inside the given IBM 
Connections installation.

=head1 EXAMPLE

perl ./file2ConnCommunity.pl -user 'Demo User' -password '1234' -server connections.example.com -file ./demo.pdf  -community 'Demo-Community"

=head1 NOTABLE INFO

=over 8

=item B<URL generation>

If you are using e.g. http://files.example.com/ instead of http://www.example.com/files as URLs,
you have to ajust the URLs in the code.

=item B<Error responses>

Note that IBM Connections is currently returning the HTTP status code 200 if there was an error, 
contradicting the documentation at 
http://www.lotus.com/ldd/lcwiki.nsf/dx/Adding_a_file_using_a_multipart_POST_ic301

=item B<nonce>

You have to get a nonce for every upload before you can upload a file. See code for more details.
http://www.lotus.com/ldd/lcwiki.nsf/dx/Getting_a_cryptographic_key_ic301

=item B<Add vs. Update>

You can not update a file entry by uploading it several time, like it is possible with bookmarks.
If you add a file (POST), the label is not allowed exist before.

=item B<Server SSL certificates>

If the code can't connect to the server, it is probably due to the fact, that you are using self-signed certificates for SSL/TLS in your Connections installations. Just download the certificate to the directory the script is residing and name it "server.pem" (or adapt the code ;). SuperUser has a more detailed description on how to download the certificate: http://superuser.com/questions/97201/how-to-save-a-remote-server-ssl-certificate-locally-as-a-file

=back

=head1 Versions

This code has been tested with Connection 3.0.1 and perl 5, version 12, subversion 4 (v5.12.4) built for i686-linux-gnu-thread-multi-64int.

=head1 Licence

Code made available under the Apache 2.0 license. http://www.apache.org/licenses/example-NOTICE.txt

=head1 Authors

Martin Leyrer <leyrer+file2ConnCommunity@gmail.com>

=cut


