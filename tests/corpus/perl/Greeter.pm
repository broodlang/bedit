#!/usr/bin/perl
# the greeter
# ^^^^^^^^^^^ comment
package App::Greeter;
# ^^^^^ keyword
#       ^^^^^^^^^^^^ special

use strict;
#   ^^^^^^ special
use warnings;
use parent -norequire, 'Base';

our $VERSION = '1.0';
my $MAX = 0x10;
# <- keyword
#         ^^^^ number
my @names = ( 'a', 'b' );
#             ^^^ string
my %ages = (
    alice => 30,
    # ^^^ constant
    bob   => 1.5,
    #        ^^^ number
);

sub new {
    # ^ definition
    my ( $class, %args ) = @_;
    my $self = { name => $args{name} };
    return bless $self, $class;
}

sub greet {
    # ^^^ definition
    my ( $self, $who ) = @_;
    if ( !defined $who ) {
        return;
    }
    elsif ( $who eq 'b' ) {
        print uc("hi $who and @names\n");
        #        ^^^^ string
        #            ^^^^ plain
        #                ^^^^^ string
    }
    else {
        $self->shout( $who, 1.5 );
        # ^^^ plain
        #      ^^^^^ function
    }
    foreach my $each (@names) {
        next unless $each;
        App::Greeter::log($each);
        # ^^^^^^^^^^^^^^^ function
    }
    my @doubled = map { $_ * 2 } grep { $_ > 1 } ( 1, 2, 3 );
    while ( my $line = <STDIN> ) {
        chomp $line;
        last if $line =~ m/^quit$/;
        #                ^^^^^^^^^ string
    }
    my $callback = sub {
        my ($value) = @_;
        return $value;
    };
    return undef;
}

1;

__END__
=head1 NAME
# ^^^^^^^^^ comment