use Curses:from<parrot>;
use CG::UI;

my $ui = CG::UI.new();
$ui.info(q{O HAI!
Welcome to the game!
There will be dancing and food and lulz.
});
sub move($dy, $dx, $obj) {
    return unless $ui.get_tile_rel($obj, $dy, $dx).kunti;
    $ui.draw($obj.leave);
    $obj.x += $dx;
    $obj.y += $dy;
    $ui.insert($obj);
}
my $dude = CG::Actor.new(:y(5), :x(5), :symbol<@>);
$ui.insert($dude);
$ui.draw($dude);
$ui.sync();
loop {
    my $ch = getch();
    given chr($ch) {
        when 'h' | chr(260) {
            move(0,-1,$dude);
        }
        when 'j' | chr(258) {
            move(1,0,$dude);
        }
        when 'k' | chr(259) {
            move(-1,0,$dude);
        }
        when 'l' | chr(261) {
            move(0,1,$dude);
        }
        when 'q' | chr(27) {
            last
        }
    }
    $ui.info($ch ~ "({chr($ch)})");
    $ui.sync();
}
endwin();

# vim: expandtab shiftwidth=4 ft=perl6:
