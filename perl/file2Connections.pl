#!/usr/bin/perl

# Uploads a file into the Files application of IBM Connections using multipart POST
# http://www.lotus.com/ldd/lcwiki.nsf/dx/Adding_a_file_using_a_multipart_POST_ic301

use strict;
use warnings;
use XML::Generator ':pretty';
use LWP::UserAgent;
use XML::RSS::Feed;
use MIME::Lite;
use HTTP::Request::Common;
use File::stat;
use Getopt::Long;
use Pod::Usage;
use JSON;
use HTML::Parser ();


## Parse options and print usage if there is a syntax error,
## or if usage was explicitly requested.
our $opt_server = ''; our $opt_username = ''; our $opt_password = '';
our $opt_file = ''; our $opt_help = ''; our $opt_man= '';
GetOptions( "server=s", "username=s", "password=s", "file=s", "help", "man",
			) or pod2usage(2);
pod2usage(1) if $opt_help;
pod2usage(-verbose => 2) if $opt_man;


# Initiate connection to the Connections server
my $connectionsUA = connect2Connection($opt_username, $opt_password, $opt_server);

# The URL can change, for example to https://files.example.com/basic/api...
# TODO Make URL generation more robust
my $filesurl = 'https://' . $opt_server . '/files/basic/api/myuserlibrary/feed';

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
	   	print "File '$opt_file' uploaded successfully.\n";
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

# Create Data structure with file and metadata for multipart/form-data upload
sub createUploadContent {
	my ($file) = @_;

	die "Given file '$file' not found!"
		if(not -f $file);

	$file =~ /([^\\\/]+)$/;
	my $filename = $1;
	my $title = $filename;
	my $content = {
		label	=> $title,									# Give the upload a nice name here
		title	=> $filename,
		visibility => 'private',							# Optional, but let's keep it private for now
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
	# Give me a break
	$x =~ /\<meta name=\"(status)\" content=\"(\d+)\"/sm;
	$response{'status'} = (not defined $2) ? '' : $2;
	$x =~ s/^(.*?)\<body (.*?)\>//sm;
	$x =~ s/\<\/body.*$//sm;
	$x =~ s/\&quot\;/\"/gsm;	# why are the json quotes encoded ???
	my $resp = decode_json $x;	# convert json to hash
	$response{'code'} = $resp;
	return(\%response);
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

file2Connections - Upload a local to to the IBM Connections Files application

=head1 SYNOPSIS

file2Connections.pl [-help|man] -user connections_username -password connections_password 
-server connections_server -file filename

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

=back

=head1 DESCRIPTION

B<file2Connections> will send the given file to the personal "Files" applications 
store of the given IBM Connections installation.

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

=back

=head1 Licence

Code made available under the Apache 2.0 license. http://www.apache.org/licenses/example-NOTICE.txt

=head1 Authors

Martin Leyrer <leyrer+file2connections@gmail.com>

=cut

