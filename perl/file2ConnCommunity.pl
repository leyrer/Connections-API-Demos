#!/usr/bin/perl

# Uploads a file into a IBM Connections community

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
use HTML::Parser;
use XML::XPath;
use Data::Dumper;

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


my $remoteApps = &retrieveRemoteApplicationsList($connectionsUA, $opt_server, $opt_community);

print "Remote App: " .  $remoteApps . "\n";

my $updatefeed = &retrieveCommunityFilesAtomFeed($connectionsUA, $opt_server, $remoteApps);

print "UpdateFeed: " . $updatefeed . "\n";

my $atom = &createAtomFileEntryDocument($opt_file);

print "Content:\n" . $atom . "\n\n";

&uploadFile($connectionsUA, $updatefeed, $atom);

exit;

sub uploadFile {
	my ($ua, $updatefeed, $atom) = @_;

	# Create POST request
	# my $req = HTTP::Request->new( POST => $updatefeed);	
	my $req = POST $updatefeed, Content_Type => 'application/atom+xml', Content => $atom;

	# Pass request to the user agent and get a response
	my $res = $ua->request( GET $updatefeed, Content_Type => 'application/atom+xml', Content => $atom );

	# Check the outcome of the response
	if ( $res->is_success ) {
	    print "File posted.\n";
	}
	else {
	    print "Error!\n" . $res->status_line, "\n";
	}
	print "Response:\n";
	print $res->content;
	print "\n";
	print Dumper($req);

	print "\n";
	print "\n";


}


sub createAtomFileEntryDocument {
	my ($fn) = @_;

	# Build XML document
	my $gen =
	  XML::Generator->new( ':pretty',
	    namespace => ["http://www.w3.org/2005/atom", ] );

	my $content = sprintf(
	    $gen->xml(
	        $gen->entry(
	            $gen->title("Demo Dokument"),
        	    $gen->category(
            	    {
	                    scheme => 'tag:ibm.com,2006:td/type',
	                    term   => "document",
						label  => 'document'
	                }
	            ),
	        ),
	    )
	);

	return $content;
}

# From the entry in the Communities remote application feed that contains the following category:
# <category term="Files" scheme="http://www.ibm.com/xmlns/prod/sn/type" /> , find the value of the
# href attribute in the <link> element that has the following rel attribute value:
# rel="http://www.ibm.com/xmlns/prod/sn/remote-application/publish".
# http://www-10.lotus.com/ldd/lcwiki.nsf/dx/Creating_community_files_ic301
sub retrieveCommunityFilesAtomFeed {
	my($ua, $srv, $rafeed) = @_;
	my $filespublink = 'http://www.ibm.com/xmlns/prod/sn/remote-application/publish';

	my $req = HTTP::Request->new( GET => $rafeed);
	my $res = $ua->request($req);

	# Check the outcome of the response
	if( not $res->is_success ) {
    	die "Error getting Community Files Atom Feed" . $res->status_line, "\n";
	} 
	
	print "URL: $rafeed\n";
	print "remote application feed:\n" . $res->content . "\n";
	print "-"x80 . "\n\n";
	# print $res->content;
	my $xp = XML::XPath->new( xml => $res->content);
	my @cfuploadurl= $xp->findnodes( "/feed/entry[category[\@term='Files']]/link[\@rel='$filespublink']" );
	if ($#cfuploadurl == 0 and $cfuploadurl[0]->getAttribute('href') ne '') {
		return $cfuploadurl[0]->getAttribute('href');
	} else {
		die "Could not retrieve the 'remote applications feed' from URL '$rafeed'.\n";
	}
}


# To retrieve a list of remote applications associated with a community, use the remote applications
# link in the community entry Atom document.
# http://www.lotus.com/ldd/lcwiki.nsf/dx/Retrieving_a_remote_applications_list_ic301
sub retrieveRemoteApplicationsList{
	my($ua, $srv, $commname) = @_;
	my $ralink = 'http://www.ibm.com/xmlns/prod/sn/remote-applications';

	# The URL can change, for example to https://files.example.com/basic/api...
	# TODO Make URL generation more robust
	my $url = 'https://' . $srv . '/communities/service/atom/communities/all?title=' . $commname;
	
	my $req = HTTP::Request->new( GET => $url );
	my $res = $ua->request($req);

	# Check the outcome of the response
	if( not $res->is_success ) {
    	die "Error getting Communities service document: " . $res->status_line, "\n";
	} 
	
	print "URL: $url \n";
	print "list of remote applications:\n" . $res->content . "\n";
	print "-"x80 . "\n\n";
	
	my $xp = XML::XPath->new( xml => $res->content);
	my @applist= $xp->findnodes( "/feed/entry[title='$commname']/link[\@rel='$ralink']" );
	if ($#applist == 0 and $applist[0]->getAttribute('href') ne '') {
		return $applist[0]->getAttribute('href');
	} else {
		die "Could not retrieve the 'Remote Applikations' link for Community '$commname'.\n";
	}
}

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

file2ConnCommunity - Upload a local file into a IBM Connections Community

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

Martin Leyrer <leyrer+file2ConnCommunity@gmail.com>

=cut

