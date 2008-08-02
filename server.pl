#!/usr/bin/perl

use strict;

use FindBin::libs;

use POE qw(Wheel::SocketFactory);
use Switch 'Perl6';
use Perl6::Subs;

#===============================================================================
package CuteGirls::Server;

use FindBin::libs;

use POE qw(Wheel::SocketFactory Wheel::ReadWrite
                    Driver::SysRW Filter::Reference);
use Data::Dumper;

use Player;
use Place;

use Perl6::Slurp;

my $default_port = 3456;

my $server_session;

my $map;

my $place;

sub new ($self,$mapfile,?$port) {
    $default_port ||= $port;
    $map = slurp '<:utf8', $mapfile;
    $place = Place->new();
    $place->load($map);
    $server_session = POE::Session->create(
        inline_states=> {
            _start => \&poe_start,
            accepted => \&poe_accepted,
            error    => \&poe_error,
            broadcast => \&server_broadcast,
        },
    );
    $server_session;
}

sub poe_start {
    my ($heap) = @_[HEAP,];
    $heap->{listener} = POE::Wheel::SocketFactory->new
        ( SuccessEvent => 'accepted',
          FailureEvent => 'error',
          BindPort     => $default_port,
          Reuse        => 'yes',
        );
    $heap->{connections} = [];
}

# Start a session to handle successfully connected clients.
sub poe_accepted {
    my ($heap, $socket, $addr, $port) = @_[HEAP,ARG0,ARG1,ARG2];
    push @{$heap->{connections}},   POE::Session->create(
                                        inline_states=> {
                                            _start => \&connection_start,
                                            input  => \&connection_input,
                                            error  => \&connection_error,
                                            broadcast => \&connection_broadcast,
                                        },
                                        args => [ $socket, $addr, $port],
                                    );
}

# Upon error, log the error and stop the server.  Client sessions may
# still be running, and the process will continue until they
# gracefully exit.
sub poe_error {
  warn "CuteGirls::Server encountered $_[ARG0] error $_[ARG1]: $_[ARG2]\n";
  delete $_[HEAP]->{listener};
}


sub server_broadcast {
   my ($kernel, $session, $heap, $message) = @_[KERNEL, SESSION, HEAP, ARG0];

   for my $conn (@{$heap->{connections}}) {
       $kernel->post($conn,'broadcast',$message);
   }
}

sub connection_start {
    my ($kernel, $session, $heap, $handle, $peer_addr, $peer_port) =
     @_[KERNEL, SESSION, HEAP, ARG0, ARG1, ARG2];
 
    print STDERR "Session ", $session->ID, " - received connection\n";
 
                                         # start reading and writing
    $heap->{wheel} = POE::Wheel::ReadWrite->new(
         'Handle'     => $handle,
         'Driver'     => POE::Driver::SysRW->new,
         'Filter'     => POE::Filter::Reference->new,
         'InputEvent' => 'input',
         'ErrorEvent' => 'error',
    );
    # hello, world!\n
    #$heap->{wheel}->put('Connected to server', '', '');
    $heap->{wheel}->put(['new_map', $place]);
    $heap->{wheel}->put(['assign_id', $session->ID]);
}

sub connection_input {
    my ($kernel, $session, $heap, $input) = @_[KERNEL, SESSION, HEAP, ARG0];
    #print Dumper($input);

    my ($command, @args) = @$input;
    if ($command eq 'add_player') {
        my ($id, $username, $symbol, $fg, $bg, $y, $x) = @args;
        print "Adding a new player: $id $symbol $fg $bg $y $x\n";
        $heap->{id} = $id;
        $place->players->{$id} = Player->new(
                id       => $id,
                username => $username,
                symbol   => $symbol,
                fg       => $fg,
                bg       => $bg,
                tile     => $place->chart->[$y][$x],
            );
        $place->players->{$id}->{tile}->vasru(1);
        $kernel->post($server_session, 'broadcast', $input);
    }
    elsif ($command eq 'player_move_rel') {
        my ($id, $x, $y) = @args;
        my $player = $place->players->{$id};
        my $dest = $player->tile;
        my $xdir = ($x < 0)? 'left' : 'right';
        my $ydir = ($y < 0)? 'up' : 'down';

        $x = abs $x;
        $y = abs $y;

        while ($x-- > 0) {
            $dest = $dest->$xdir || return;
        }

        while ($y-- > 0) {
            $dest = $dest->$ydir || return;
        }

        return unless $dest->vasru;
        $player->tile->leave($player);
        $dest->enter($player);
        $player->tile($dest);

        $kernel->post($server_session, 'broadcast', $input);
    }
    elsif ($command eq 'remove_player') {
        my ($id) = @args;
        $place->players->{$id}->tile->leave($place->players->{$id});
        delete $place->players->{$id};
        $kernel->post($server_session, 'broadcast', $input);
    }
    else {
        $kernel->post($server_session, 'broadcast', $input);
    }
}

sub connection_error {
   my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
   return unless defined($place->players->{$heap->{id}});
   $kernel->post($server_session, 'broadcast', ['remove_player', $heap->{id}]);
   $place->players->{$heap->{id}}->tile->leave($place->players->{$heap->{id}});
   delete $place->players->{$heap->{id}};
}

sub connection_broadcast {
   my ($kernel, $session, $heap, $message) = @_[KERNEL, SESSION, HEAP, ARG0];

   $heap->{wheel}->put($message);
}

#===============================================================================
package main;

print STDERR "Starting server...\n";

my $server = CuteGirls::Server->new($ARGV[0] || 'maps/map2.txt');
POE::Kernel->run();

exit;
