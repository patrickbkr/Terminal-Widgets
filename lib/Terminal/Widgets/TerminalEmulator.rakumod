# ABSTRACT: A terminal emulator widget

use Terminal::Widgets::Widget;
use Terminal::Widgets::Events;
use Terminal::Widgets::Focusable;
use Anolis::Interface;
use Anolis;

sub dump($text) {
    "o".IO.spurt: $text ~ "\n", :append;
}

class Terminal::Widgets::TerminalEmulator
is Terminal::Widgets::Widget
does Terminal::Widgets::Focusable
does Anolis::Interface {
    has &.process-log;
    has $!interface;
    has $!anolis;

    submethod TWEAK(:$proc-async) {
        self.set-proc-async($_) with $proc-async;
        self.init-focusable;
    }

    method set-proc-async($proc-async) {
        die "Cannot reconnect terminal." with $!anolis;
        $!anolis = Anolis.new: :$proc-async, :interface(self);
    }

    method full-refresh(Bool:D :$print = True) {
        self.clear-frame;
        self.draw-frame;
#dump("Widget: W:$.w, H:$.h");
#dump("Grid: W:{self.grid.w}, H:{self.grid.h}");
#dump("In print" ~ self.grid.grid[17].raku);
#dump(self.debug-grid);
        self.composite(:$print);
    }

    method draw-frame() {
        self.draw-framing;

        for $!anolis.screen.grid.kv -> $y, $rows {
            last if $y >= $.grid.h;
            next unless $rows;
            for @$rows.kv -> $x, $cell {
                last if $x >= $.grid.w;
                next unless $cell;
                if $cell.sgr {
                    $.grid.set-span-sgr($x, $y, $cell.char, "\e[{$cell.sgr}m");
                }
                else {
                    $.grid.set-span-sgr($x, $y, $cell.char, '');
                }
            }
        }
    }

    multi method handle-event(Terminal::Widgets::Events::KeyboardEvent:D
                              $event where *.key.defined, AtTarget) {
        my constant %keymap =
            Ctrl-I      => 'next-input',    # Tab
            ShiftTab    => 'prev-input',    # Shift-Tab is weird and special
            ;

        my $keyname = $event.keyname;
        with %keymap{$keyname} {
            when 'next-input'  { self.focus-next-input }
            when 'prev-input'  { self.focus-prev-input }
        }
        else {
            if $event.key ~~ Str {
                $!anolis.send-text($event.key);
            }
            elsif $event.key ~~ Pair {
                $!anolis.send-text($event.key.value);
            }
            else {
                dump("Unknown Event thing: " ~ $event);
            }
        }
    }

    multi method handle-event(Terminal::Widgets::Events::MouseEvent:D
                              $event where !*.mouse.pressed, AtTarget) {
        self.toplevel.focus-on(self);
    }

    # Anolis::Interface ===========================================

    method heading-changed(Str $heading) {
    }
    method grid-changed(@areas) {
        sub set($x, $y, $text, $sgr) {
            return;
#dump "$x,$y: $text";
            if $sgr {
                $.grid.set-span-sgr($x, $y, $text, "\e[{$sgr}m");
            }
            else {
                $.grid.set-span-sgr($x, $y, $text, '');
            }
        }
        for @areas -> $area {
            my $sgr = $area.cells[0].sgr;
            my $different = $area.cells.first: *.sgr ne $sgr;
            if $different {
                for $area.cells.kv -> $i, $cell {
                    if $area.from-x + $i < $.w && $area.y < $.h {
                        set($area.from-x + $i, $area.y, $cell.char, $cell.sgr);
                    }
                }
            }
            else {
                my $text = [~] $area.cells.map( *.char );
                if $area.y < $.h {
                    my $max-len = $.w - $area.from-x;
                    $text .= substr: 0, $max-len;
                    set($area.from-x, $area.y, $text, $sgr);
                }
            }
        }
#dump("After set" ~ self.grid.grid[17].raku);
        self.full-refresh;
    }
    method log(Str $text) {
        $_($text) with &!process-log;
    }
}
