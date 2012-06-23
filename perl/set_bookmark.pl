#!/usr/bin/perl 

# Add a Bookmark to an IBM Connections Community 
# 

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use XML::Generator ':pretty';
use LWP::UserAgent;

## Parse options and print usage if there is a syntax error,
## or if usage was explicitly requested.
our $opt_server = ''; our $opt_username = ''; our $opt_password = '';
our $opt_help = ''; our $opt_man= '';
GetOptions( "server=s", "username=s", "password=s", "help", "man",
			) or pod2usage(2);
pod2usage(1) if $opt_help;
pod2usage(-verbose => 2) if $opt_man;

# To prevent credentials from being sent in the clear, the API (except for the Files and Wikis API)
# always sends a redirect to HTTPS before issuing the unauthorized challenge.
# http://www.lotus.com/ldd/lcwiki.nsf/dx/Authenticating_requests_ic301
my $port = "443";

my $user   = $opt_username;
my $pw     = $opt_password;
my $server = $opt_server;

die "Please state the IBM Connections username as the first paramter!"
  if ( $user eq '' );
die "Please state the IBM Connections password as the second paramter!"
  if ( $pw eq '' );
die "Please state the IBM Connections servername as the third paramter!"
  if ( $server eq '' );

# Create a user object
my $ua = LWP::UserAgent->new;
$ua->agent("MyBookmark/0.1");

# Make sure, that LWP recognizes the server certificate
$ua->ssl_opts( SSL_ca_file => './server.pem' );

# the default realm for Connections is 'lotus-connections'
$ua->credentials( $server . ':' . $port, 'lotus-connections', $user, $pw );
push @{ $ua->requests_redirectable }, 'POST';

# Create a request
# The URL can change, for example to https://bookmarks.example.com/api...
# TODO Make URL generation more robust
my $url = 'https://' . $server . '/dogear/api/app/';

my $req = HTTP::Request->new( POST => $url );

# Build ATOM bookmark document and store its string in $content
my $gen =
  XML::Generator->new( ':pretty',
    namespace => ["http://www.w3.org/2005/atom"] );
my $content = sprintf(
    $gen->xml(
        $gen->entry(
            $gen->author($user),
            $gen->title("IBM Connections wiki"),
            $gen->content(
                { type => 'html' },
                "IBM Connections Wiki bookmarked from Perl."	# description
            ),
            $gen->category(
                {
                    scheme => "http://www.ibm.com/xmlns/prod/sn/type",
                    term   => "bookmark"
                }
            ),
            $gen->category( { term => "wiki" } ),			# tag
            $gen->category( { term => "Connections" } ),	# tag
            $gen->link( { href => "http://www.lotus.com/ldd/lcwiki.nsf" } ), # the link to add
        ),
    )
);

# Set request content
$req->content_type('application/atom+xml');
$req->content($content);

# Pass request to the user agent and get a response
my $res = $ua->request($req);

# Check the outcome of the response
if ( $res->is_success ) {
    print "Bookmark posted.\n";
}
else {
    print "Error!\n" . $res->status_line, "\n";
}


__END__

=head1 NAME

set_bookmark - Add a Bookmark to an IBM Connections installation

=head1 SYNOPSIS

set_bookmark.pl [-help|man] -user connections_username -password connections_password 
-server connections_server 

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-user>

The name of the connections user for whom the bookmark should be added

=item B<-password>

The IBM Connections password for the user.

=item B<-server>

The servername (DNS hostname) of the IBM Connections installation the bookmark should be added to.

=item B<-file>

The file to be uploaded.

=back

=head1 DESCRIPTION

B<file2Connections> will the bookmark to the public bookmark collection of a given IBM Connections 
installation.

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

Martin Leyrer <leyrer+file2connections@gmail.com>

=cut

