#!/usr/bin/perl 

# Sync the bookmarks of the given delicious account to the given IBM Connections account

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use File::stat;
use Net::Delicious;
use Log::Dispatch::Screen;
use DateTime;
use File::Path qw(make_path);
use DateTime::Format::Strptime;
use XML::Generator ':pretty';
use LWP::UserAgent;
use Encode;
use Encode::Detect::Detector;

my $DEBUG = 0;

## Parse options and print usage if there is a syntax error,
## or if usage was explicitly requested.
our $opt_server = ''; our $opt_username = ''; our $opt_password = '';
our $opt_delusr = ''; our $opt_help = ''; our $opt_man= ''; our $opt_delpwd = '';
our $opt_delicioustag = '';
GetOptions( "server=s", "username=s", "password=s", "file=s", "delusr=s", "delpwd=s", "delicioustag=s", "help", "man",
			) or pod2usage(2);
pod2usage(1) if $opt_help;
pod2usage(-verbose => 2) if $opt_man;

# Connect to delicious
pod2usage( -verbose => 2, -message => "$0: Please state the Delicious tag to search for!\n")
	if ( $opt_delicioustag eq '' );
my $del = &delicious_connect( $opt_delusr, $opt_delpwd );
die "Connection problem with delicious\n"
	if(not defined($del));

# Connect to Connections
# Create a user object
my $ua = LWP::UserAgent->new;
$ua->agent("SyncDel2Conn/0.1");
my $conn = &connections_connect( $opt_username, $opt_password, $opt_server, $ua);
die "Connection problem with Connections\n"
	if(not defined($conn));

# Find my recent delicious links with tag "ibm"
my $it = $del->recent_posts( {tag => $opt_delicioustag} );
print "Found " . $it->count() . " links on delicious with the tag '$opt_delicioustag'.\n" if($DEBUG);

# Iterate over the found delicious links and add them to Connections
while (my $d = $it->next()) {
	my $xml = createBookmarkAtomEntry($d, $ARGV[2]);
	updateConnections($xml, $ua, $conn);
}

print "DONE!\n" if($DEBUG);

exit;

# Create UserAgent Object, set server certificate for SSL, set realm
sub connections_connect {
	my ($user, $pwd, $srv, $ua) = @_;
	
	pod2usage( -verbose => 2, -message => "$0: Please state the IBM Connections username!\n")
		if ( $opt_username eq '' );
	pod2usage( -verbose => 2, -message => "$0: Please state the IBM Connections password!\n")
		if ( $opt_password eq '' );
	pod2usage( -verbose => 2, -message => "$0: Please state the IBM Connections servername!\n" )
		if ( $opt_server eq '' );

	# To prevent credentials from being sent in the clear, the API (except for the Files and Wikis API)
	# always sends a redirect to HTTPS before issuing the unauthorized challenge.
	# http://www.lotus.com/ldd/lcwiki.nsf/dx/Authenticating_requests_ic301
	my $port = "443";

	# the default realm for Connections is 'lotus-connections'
	$ua->credentials( $srv . ':' . $port, 'lotus-connections', $user, $pwd );
	push @{ $ua->requests_redirectable }, 'POST';
	$ua->ssl_opts( SSL_ca_file => './server.pem' );

	# Create a request
	my $url = 'https://' . $srv . '/dogear/api/app/';
	my $req = HTTP::Request->new( POST => $url );

	return($req);
}

# Connect to delicious, nothing fancy
sub delicious_connect {
	my ($usr, $pwd) = @_;

	pod2usage( -verbose => 2, -message => "$0: Please state the Delicious username!\n")
		if ( $usr eq '' );
	pod2usage( -verbose => 2, -message => "$0: Please state the Delicious password!\n")
		if ( $pwd eq '' );
	
	my $del = Net::Delicious->new({	user => $opt_delusr,
									pswd => $opt_delpwd,
									debug => 0,
								  });
	return $del;
}

# Create the ATOM document to create/update a bookmark entry in IBM Connections
sub createBookmarkAtomEntry {
	my($description, $user) = @_;
	my $text = $description->extended();
	my $title = ($description->description() eq '') ? $text : $description->description();

	# Work around encoding issues with umlauts and delicious/Connections
	# in title and description
	my $encoding_name = Encode::Detect::Detector::detect($title);
	if(defined($encoding_name)) {
		$encoding_name = (uc($encoding_name) eq "EUC-JP") ? "UTF-8" : $encoding_name;
		$title = encode($encoding_name, $title);
	}
	$encoding_name = Encode::Detect::Detector::detect($text);
	if(defined($encoding_name)) {
		$encoding_name = (uc($encoding_name) eq "EUC-JP") ? "UTF-8" : $encoding_name;
		$text = encode($encoding_name, $text);
	}

	print "Working on >>$title<<\n" if($DEBUG);

	# Build XML document
	my $gen =
  		XML::Generator->new( ':pretty',
    		namespace => ["http://www.w3.org/2005/Atom"],
			encoding  => 'utf-8');

	# The XML fragment for the Tags has to be created before we create the actual document XML
	my $tags = &genTags($description);

	my $content = sprintf(
	    $gen->xml(
	        $gen->entry(
	            $gen->author($opt_username),
	            $gen->title($title),
	            $gen->content(
	                { type => 'html' },
					(($text ne '') ? $text : $title)
	            ),
	            $gen->category(
	                {
	                    scheme => "http://www.ibm.com/xmlns/prod/sn/type",
	                    term   => "bookmark"
	                }
	            ),
	            $gen->link( { href => $description->href() } ),
				@{$tags},
	        ),
	    )
	);
	
	return($content);
}

# Parse the delicous tags and add them as Connections Tags
sub genTags {
	my ($d) = @_;
	
	# Create XMl Generator for Tags
	my $taggen = XML::Generator->new( ':pretty', );
	
	# add tags from delicious to connections
	my @tags;
	push(@tags, $taggen->category( { term => 'deliciousimport' } ) );	# add another tag to identify imported tags
	foreach my $dtags ($d->tags()) {
		my @dtags = split(/\s/, $dtags);
		foreach my $tag (@dtags) {
			next if( $tag =~ /(from|twitter|ibm)/i);	# skip a few unnecessary tags
			push(@tags, $taggen->category( { term => $tag } ) );
		}
	}
	return (\@tags);
}

#Send the ATOM document to the server
sub updateConnections {
	my ($xml, $ua, $req) = @_;

	# Set request content
	$req->content_type('application/atom+xml');
	$req->content($xml);

	# Pass request to the user agent and get a response
	my $res = $ua->request($req);

	# Check the outcome of the response
	if ( $res->is_success ) {
    	print "\tBookmark posted.\n" if($DEBUG);
	} else {
    	print "\tError: " . $res->status_line, "\n";
		print $res->decoded_content;
	}
}


__END__

=head1 NAME

syncDelicious2Connections - Copy recent Delicious bookmarks with a given tag to a given IBM Connections implementation

=head1 SYNOPSIS

syncDelicious2Connections.pl [-help|man] -user connections_username -password connections_password 
-server connections_server -delusr delicious_username -delpwd delicious_password -delicioustag delicious_tag_to_search_for

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-user>

The name of the IBM Connections user.

=item B<-password>

The IBM Connections password for the user.

=item B<-server>

The servername (DNS hostname) of the IBM Connections installation.

=item B<-delusr>

The name of the Delicious.com user.

=item B<-delpwd>

The password of the Delicious.com user.

=item B<-delicioustag>

The tag, the script should search for on delicious.com

=back

=head1 DESCRIPTION

B<synDelicious2Connections> will copy all recent Delicious bookmarks with a given tag to an IBM Connections installation.

=head1 EXAMPLE

perl ./syncDelicious2Connections.pl -user 'Connections Demo User' -password '1234' -server connections.example.com -delusr 'Delicious Demo User' -delpwd '1234' -deliciousta example

=head1 NOTABLE INFO

=over 8

=item B<URL generation>

If you are using e.g. http://bookmarks.example.com/ instead of http://www.example.com/dogear as URLs,
you have to ajust the URLs in the code.

=item B<Add vs. Update>

If you try to add an existing bookmark, the existing entry will get upated and no new bookmark will get added.

=item B<Server SSL certificates>

If the code can't connect to the server, it is probably due to the fact, that you are using self-signed certificates for SSL/TLS in your Connections installations. Just download the certificate to the directory the script is residing and name it "server.pem" (or adapt the code ;). SuperUser has a more detailed description on how to download the certificate: http://superuser.com/questions/97201/how-to-save-a-remote-server-ssl-certificate-locally-as-a-file

=back

=head1 Versions

This code has been tested with Connection 3.0.1 and perl 5, version 12, subversion 4 (v5.12.4) built for i686-linux-gnu-thread-multi-64int.

=head1 Licence

Code made available under the Apache 2.0 license. http://www.apache.org/licenses/example-NOTICE.txt

=head1 Authors

Martin Leyrer <leyrer+SyncDelicious2Connections@gmail.com>

=cut

