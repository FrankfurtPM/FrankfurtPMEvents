#!/usr/bin/perl

use v5.10;

use strict;
use warnings;

use experimental 'signatures';
no warnings 'experimental::signatures';

use Time::Piece;
use Mojo::File qw(path);
use Mojo::JSON qw(encode_json);
use Mojo::IOLoop;
use Mojo::UserAgent;

my $base_url = 'http://www.perlmongers.de/?action=edit&page_id=Kalender-';
my $start    = '2004-02-03';
my $d        = Time::Piece->strptime( $start, '%Y-%m-%d' );
my $ua       = Mojo::UserAgent->new;

my %dates;
my @urls;

while ( $d->ymd ne '2016-02-10' ) {
    my $url = $base_url . $d->ymd;
    push @urls, {
        date => $d->ymd,
        year => $d->year,
        url  => $url,
    };

    $d += 86_400;
}

say "requesting " . scalar( @urls ) . " urls";

request_calendars( $ua, \@urls, \%dates );
write_data( \%dates );

sub request_calendars ( $ua, $queue, $dates ) {

    say "do request calendar";

    state $idle  = 10;
    state $delay = Mojo::IOLoop->delay( sub {
        say @{$queue || [] } ? 'Loop ended before queue is empty' : 'Finished';
    });

    $queue ||= [];

    while ( $idle and my $item = shift @{ $queue } ) {

        $idle--;

        my $year = $item->{year};
        my $date = $item->{date};

        my $end = $delay->begin;

        # Non-blocking request
        say "get calendar for $date";
        $ua->get( $item->{url} => sub {
            my ($ua, $tx) = @_;

            $idle++;
            say "Got ", $item->{url}, ", idle: $idle";

            my $text = $tx->res->dom->at('textarea[name="wiki_text"]')->text;
            
            if ( $text =~ m{Frankfurt} ) {
                my ($line) = grep{ m{Frankfurt} }(split /\n/, $text);
                $line      =~ s{\A\*\s+}{};

                if ( $line =~ m{MonthlyMeeting|\[Frankfurt\.pm} ) {
                    $line = 'Monatliches Treffen';
                }
                else {
                    $line =~ s{\[(.*)http.*}{$1};
                }

                $dates->{$year}->{$date} = $line;
            }

            request_calendars( $ua, $queue, $dates );

            $end->();
        });
    }

    $delay->wait unless $delay->ioloop->is_running;
}

sub write_data ( $data ) {
    my %dates = %{ $data || {} };

    for my $year ( sort keys %dates ) {
        my $path = path(
            path( __FILE__ )->dirname,
            '..',
            'data',
            'perlmongers_de',
            $year . '.json',
        );

        $path->spurt( encode_json $dates{$year} );
    }
}
