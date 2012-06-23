#!/usr/bin/perl 

# Sync the bookmarks of the given delicious account to the given IBM Connections account

use strict;
use warnings;
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

die "Please enter your delicious user as the 1st parameter of the programm!\n"
	if( not defined($ARGV[1]) or $ARGV[1] eq '');
die "Please enter your delicious password as the 2nd parameter of the programm!\n"
	if( not defined($ARGV[1]) or $ARGV[1] eq '');


# Connect to delicious
my $del = Net::Delicious->new({	user => $ARGV[0] ,
								pswd => $ARGV[1] ,
								debug => $DEBUG,
							  });
die "Connection problem with delicious\n"
	if(not defined($del));

# Connect to Connections
# Create a user object
my $ua = LWP::UserAgent->new;
$ua->agent("SyncDel2Conn/0.1");
my $conn = &connections_connect( $ARGV[2], $ARGV[3], $ARGV[4], $ua);
die "Connection problem with Connections\n"
	if(not defined($conn));

# Find my recent delicious links with tag "ibm"
my $it = $del->recent_posts( {tag => 'ibm'} );
print "Found " . $it->count() . " links on delicious with the tag 'ibm'.\n";
while (my $d = $it->next()) {
	my $xml = createBookmarkAtomEntry($d, $ARGV[2]);
	updateConnections($xml, $ua, $conn);
}

print "DONE!\n";

exit;

sub connections_connect {
	my ($user, $pwd, $srv, $ua) = @_;
	
	die "Please state the IBM Connections username!"
		if ( $user eq '' );
	die "Please state the IBM Connections password!"
		if ( $pwd eq '' );
	die "Please state the IBM Connections servername!"
		if ( $srv eq '' );

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

sub createBookmarkAtomEntry {
	my($d, $user) = @_;
	my $t = $d->extended();
	my $title = ($d->description() eq '') ? $t : $d->description();

	# Work around encoding issues with umlauts and delicious/Connections
	# in title and description
	my $encoding_name = Encode::Detect::Detector::detect($title);
	if(defined($encoding_name)) {
		$title = encode($encoding_name, $title);
	}
	$encoding_name = Encode::Detect::Detector::detect($t);
	if(defined($encoding_name)) {
		$t = encode($encoding_name, $t);
	}

	print "Working on >>$title<<\n" if($DEBUG);

	# Build XML document
	my $gen =
  		XML::Generator->new( ':pretty',
    		namespace => ["http://www.w3.org/2005/Atom"],
			encoding  => 'utf-8');

	my $tags = &genTags($d);

	my $content = sprintf(
	    $gen->xml(
	        $gen->entry(
	            $gen->author($user),
	            $gen->title($title),
	            $gen->content(
	                { type => 'html' },
					(($t ne '') ? $t : $title)
	            ),
	            $gen->category(
	                {
	                    scheme => "http://www.ibm.com/xmlns/prod/sn/type",
	                    term   => "bookmark"
	                }
	            ),
	            $gen->link( { href => $d->href() } ),
				@{$tags},
	        ),
	    )
	);
	
	return($content);
}

sub genTags {
	my ($d) = @_;
	
	# Create XMl Generator for Tags
	my $taggen =
  		XML::Generator->new( ':pretty',
			);
	
	# add tags from delicious to connections
	my @tags;
	push(@tags, $taggen->category( { term => 'deliciousimport' } ) );
	foreach my $dtags ($d->tags()) {
		my @dtags = split(/\s/, $dtags);
		foreach my $tag (@dtags) {
			print "tag: $tag|\n" if($DEBUG);
			next if( $tag =~ /(from|twitter|ibm)/i);
			push(@tags, $taggen->category( { term => $tag } ) );
		}
	}
	return (\@tags);
}

sub updateConnections {
	my ($xml, $ua, $req) = @_;

	# Set request content
	$req->content_type('application/atom+xml');
	$req->content($xml);

	# Pass request to the user agent and get a response
	my $res = $ua->request($req);

	# Check the outcome of the response
	if ( $res->is_success ) {
    	print "\tBookmark posted.\n";
	} else {
    	print "\tError: " . $res->status_line, "\n";
		print "XML:\n$xml\n";
		print "-"x80 . "\n";
		print $res->decoded_content;
		open (ERROR, ">error.xml") or die "$!\n";
		print ERROR $xml;
		close(ERROR);
	}
}

