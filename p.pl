#!/usr/bin/perl

use strict;

use FindBin::libs;

use Curses;
use POE qw(Wheel::Curses Wheel::SocketFactory Wheel::ReadWrite Driver::SysRW Filter::Line);
use Switch 'Perl6';

use Player;
use Place;
use Place::Thing;
use UI;

POE::Session->create
  ( inline_states =>
      { _start => \&_start,
        got_keystroke => \&keystroke_handler,
        player_move_rel => \&player_move_rel,
        new_player => \&new_player,
        connect_success => \&connect_success,
        connect_failure => \&connect_failure,
        server_input => \&server_input,
        server_error => \&server_error,
        assign_id => \&assign_id,
      }
  );

POE::Kernel->run();
exit;

sub _start {
    my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

    binmode(STDOUT,':utf8');

    $heap->{console} = POE::Wheel::Curses->new(
        InputEvent => 'got_keystroke'
    );

    $heap->{server} = POE::Wheel::SocketFactory->new(
           RemoteAddress  => '127.0.0.1',
           RemotePort     => 3456,
           SuccessEvent   => 'connect_success',
           FailureEvent   => 'connect_failure'
         );

    $heap->{ui} = UI->new();
    $heap->{place} = Place->new();
    $heap->{place}->load($ARGV[0] || 'maps/map1.txt',$heap->{ui}->place_panel,$heap->{ui});

    $heap->{ui}->place($heap->{place});

    $heap->{ui}->setup();


    $heap->{place}->chart->[3][3]->enter(Place::Thing->new(color=>$heap->{ui}->colors->{'red'}->{'black'},symbol=>'%'));

    $heap->{ui}->redraw();
    ungetch('r');
    $heap->{players} = { };
}

sub assign_id {
    my ($heap, $id) = @_[HEAP, ARG0];
    $heap->{my_id} = $id;
}

sub keystroke_handler {
    my ($kernel, $heap, $keystroke, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

     $heap->{ui}->output_panel->panel_window->addstr("keypress: $keystroke\n");
     $heap->{ui}->refresh();
     given ($keystroke) {
         when [KEY_UP, 'k'] { send_to_socket($heap->{server_socket},'player_move_rel',$heap->{my_id},0,-1) }
         when [KEY_DOWN, 'j'] { send_to_socket($heap->{server_socket},'player_move_rel',$heap->{my_id},0,1) }
         when [KEY_LEFT, 'h'] { send_to_socket($heap->{server_socket},'player_move_rel',$heap->{my_id},-1,0) }
         when [KEY_RIGHT, 'l'] { send_to_socket($heap->{server_socket},'player_move_rel',$heap->{my_id},1,0) }
         when 'n' { send_to_socket($heap->{server_socket},'new_player',$heap->{my_id},'@','blue','black',5,5) };
         when 'r' { $heap->{ui}->redraw() }
         when 'q' { delete $heap->{console}; delete $heap->{server_socket}  } # how to tell POE to kill the session?
     }
}

sub send_to_socket {
    my $socket = shift;
    $socket->put(join ' ', @_);
}

sub player_move_rel {
    my ($kernel, $heap, $player_id, $x, $y) = @_[KERNEL, HEAP, ARG0, ARG1, ARG2];
    $heap->{players}->{$player_id}->move_rel($x,$y);
    $heap->{ui}->output_panel->panel_window->addstr("Player $player_id moving $x,$y\n");
    $heap->{ui}->refresh();
}

sub new_player {
    my ($kernel, $heap, $id,$symbol, $fg, $bg, $y, $x) = @_[KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3, ARG4, ARG5];
    my $player = Player->new(
                        symbol => $symbol,
                        color => $heap->{ui}->colors->{$fg}->{$bg},
                        tile => $heap->{place}->chart->[$y][$x],
                        id => $id,
                        );
    $heap->{players}->{$id} = $player;
    $heap->{ui}->output_panel->panel_window->addstr("New player '$symbol' at $x,$y id $id\n");
    $heap->{ui}->refresh();
}

sub connect_success {
    my ($kernel, $heap, $socket) = @_[KERNEL, HEAP, ARG0];

    $heap->{server_socket} = POE::Wheel::ReadWrite->new(
         'Handle'     => $socket,
         'Driver'     => POE::Driver::SysRW->new,
         'Filter'     => POE::Filter::Line->new,
         'InputEvent' => 'server_input',
         'ErrorEvent' => 'server_error',
    );

}

sub connect_failure {
    die "couldn't connect to server\n";
}

sub server_input {
    my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

    $kernel->yield(split / /, $input);
}

sub server_error {
    die "problem with network stuff I guess\n";
}
