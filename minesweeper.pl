#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use Encode;
use Mojolicious::Lite;

my $clients = {};
my $game;

sub new_game {
    my $cols  = 60;
    my $rows  = 32;
    my $mines = 350;
    my @seed;
    my @mines;
    for my $i ( 0 .. $cols - 1 ) {
        for my $j ( 0 .. $rows - 1 ) {
            push @seed, [ $i, $j ];
        }
    }
    for ( 0 .. $mines - 1 ) {
        my $idx  = int( rand( scalar @seed ) );
        push @mines, splice( @seed, $idx, 1 );
    }
    return {
        cols  => $cols,
        rows  => $rows,
        mines => \@mines,
        log   => [],
    };
}
$game = new_game();
my $total_users = 0;

sub broadcast {
    my ( $cmd, $data ) = @_;
    my $json = JSON::encode_json({ type => $cmd, ( $data ? ( data => $data ) : () ) });
    $json = Encode::decode_utf8($json);
    foreach my $cid (keys %$clients) {
        $clients->{$cid}{controller}->send_message($json);
    }
}

sub broadcast_userlist {
    my @users = map { $_->{nickname} } values %$clients;
    broadcast( users => \@users );
}

websocket '/' => sub {
    my $self = shift;

    # Client id
    my $cid = "$self";

    # Regist controller
    my $user = $clients->{$cid} = {
        controller => $self,
        nickname   => 'User ' . ++$total_users,
    };
    broadcast_userlist();

    # Receive message
    $self->on_message(sub {
        my ($self, $msg_string) = @_;
        my $msg = JSON::decode_json(Encode::encode_utf8($msg_string));
        my $cmd = $msg->{type};
        my $data = $msg->{data};
        if ( $cmd eq 'newgame' ) {
            $game = new_game();
            broadcast( game => $game );
        }
        elsif ( $cmd eq 'game' ) {
            $self->send_message( JSON::encode_json({ type => 'game', data => $game }) );
        }
        elsif ( $cmd eq 'open' ) {
            push @{$game->{log}}, $msg;
            broadcast( $cmd => $data );
        }
        elsif ( $cmd eq 'flag' ) {
            push @{$game->{log}}, $msg;
            broadcast( $cmd => $data );
        }
        elsif ( $cmd eq 'unflag' ) {
            push @{$game->{log}}, $msg;
            broadcast( $cmd => $data );
        }
        elsif ( $cmd eq 'dead' ) {
            broadcast( sbc => { msg => $user->{nickname} . ' is dead!' } );
        }
        elsif ( $cmd eq 'bc' ) {
            my ($special, $value) = $data->{msg} =~ /^\/(\w+)\s*?(.*)?$/;
            if ( !$special ) {
                # Send message to all clients
                broadcast( bc => {%$data, nick => $user->{nickname}} );
            }
            elsif ( $special eq 'nick' && $value) {
                my $old = $user->{nickname};
                $user->{nickname} = $value;
                broadcast( sbc => { msg => "$old is now knonw as $value" });
                broadcast_userlist();
            }
        }
    });

    # Finish
    $self->on_finish(sub {
        # Remove client
        delete $clients->{$cid};
    });
    broadcast_userlist();
};

get '/' => 'index';

app->start;

1;
