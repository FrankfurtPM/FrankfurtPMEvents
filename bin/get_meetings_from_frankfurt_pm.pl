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

my $base_url = 'http://frankfurt.pm/';
my $ua       = Mojo::UserAgent->new;

my %dates;

my @archives = get_archives( $ua, $base_url );
request_archives( $ua, \@archives, \%dates );
write_data( \%dates );

sub get_archives ( $ua, $base ) {
    my $response = $ua->get( $base_url . 'archives.html' );

    my @months = $response->dom->at();

    return @months;
}

sub request_archives ( $ua, $queue, $dates ) {

    say "do request archive";

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
                $line      =~ s{:}{ };

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
            'frankfurt_pm',
            $year . '.json',
        );

        $path->spurt( encode_json $dates{$year} );
    }
}
