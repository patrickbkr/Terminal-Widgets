# ABSTRACT: A text widget that has clickable lines / a selected line.

use Text::MiscUtils::Layout;

use Terminal::Widgets::Events;
use Terminal::Widgets::SpanStyle;
use Terminal::Widgets::SpanBuffer;
use Terminal::Widgets::Focusable;

#| Simple auto-scrolling log viewer
class Terminal::Widgets::RichText
 does Terminal::Widgets::SpanBuffer
 does Terminal::Widgets::Focusable {
    has @.lines;
    #| For each line, in which display line does it start?
    has @!l-dl;
    #| For each diplay line, which line is there?
    has @!dl-l;
    has $.wrap = False;
    has $!widest;
    has $!first-display-line = 0;
    has &.process-click;
    has $.selected-line = 0;
    has $.selected-line-style is built = 'bold white on_blue';
    has Bool $.show-cursor = False;
    has $.cursor-pos = 0;

    submethod TWEAK() {
        self.init-focusable;
    }

    method set-wrap($wrap) {
        $!wrap = $wrap;
        self.my-refresh;
    }

    method set-show-cursor($show-cursor) {
        $!show-cursor = $show-cursor;
        self.full-refresh;
    }

    method my-refresh($from = 0) {
        my $first-line = 0;
        my $sub-line = 0;
        if @!dl-l {
            $first-line = @!dl-l[$!first-display-line];
            $sub-line = $!first-display-line - @!l-dl[$first-line];
        }
        if !$!wrap {
            self.set-x-max($!widest) if $!widest > $.x-max;
        }
        else {
            self.set-x-max(self.content-width);
            self.set-x-scroll(0);
        }
        self!calc-indexes($from);
        self.set-y-max(@!dl-l.end);
        my $new-first-line-start = @!l-dl[$first-line];
        my $new-first-line-height = self!height-of-line(@!lines[$first-line]);
        self.set-y-scroll($new-first-line-start + min($sub-line, $new-first-line-height));
        self.full-refresh;
        self.refresh-for-scroll;
    }

    method !calc-indexes($from = 0) {
        my $dpos = @!l-dl[$from] // 0;
        loop (my $pos = $from; $pos < @!lines.elems; $pos++) {
            my $l = @!lines[$pos];
            @!l-dl[$pos] = $dpos;
            my $line-height = self!height-of-line($l);
            @!dl-l[$dpos++] = $pos for ^$line-height;
        }
        @!l-dl.splice: @!lines.elems;
        @!dl-l.splice: $dpos;
    }

    method !calc-widest() {
        $!widest = @!lines.map(*.map(*.width).sum).max;
    }

    #| Add content for a single entry (in styled spans or a plain string) to the log
    method set-text(SpanContent $content) {
        my $as-tree = $content ~~ Terminal::Widgets::SpanStyle::SpanTree
                        ?? $content
                        !! span-tree('', $content);
        @!lines = $as-tree.lines.eager;
        self!calc-widest;
        self.my-refresh;
    }

    method splice-lines($from, $count, $replacement) {
        my $as-tree = $replacement ~~ Terminal::Widgets::SpanStyle::SpanTree
                        ?? $replacement
                        !! span-tree('', $replacement);
        my @repl-lines = $as-tree.lines.eager;
        @!lines.splice: $from, $count, @repl-lines;

        self!calc-widest;
        self.my-refresh($from);
    }

    method !wrap-line(@line) {
        if $!wrap {
            my $width = self.content-width;
            my @wrapped;
            my @next;
            my $len = 0;
            for @line -> $span is copy {
                loop {
                    if $len + $span.width < $width {
                        $len += $span.width;
                        @next.push: $span;
                        last;
                    }
                    elsif $len + $span.width == $width {
                        @next.push: $span;
                        @wrapped.push: @next;
                        @next := [];
                        $len = 0;
                        last;
                    }
                    else {
                        my $remaining-space = $width - $len;
                        my $first = $span.text.substr(0,
                                    self!count-fitting-in-width($span.text, $remaining-space));
                        my $second = $span.text.substr($first.chars);
                        @next.push: span($span.color, $first);
                        @wrapped.push: @next;
                        @next := [];
                        $len = 0;
                        $span = span($span.color, $second);
                    }
                }
            }
            @wrapped.push: @next if @next;
            @wrapped
        }
        else {
            [@line,]
        }
    }

    method !display-pos-to-line-pos(@line, $x, $y) {
        my $width = self.content-width;
        my $lx = 0;
        my $rx = 0;
        my $ry = 0;
        for @line -> $span is copy {
            loop {
                if $ry < $y {
                    if $rx + $span.width < $width {
                        $rx += $span.width;
                        last;
                    }
                    elsif $rx + $span.width == $width {
                        $lx += $rx + $span.width;
                        $rx = 0;
                        $ry++;
                        last;
                    }
                    else {
                        my $remaining-space = $width - $rx;
                        my $fitting = self!count-fitting-in-width($span.text, $remaining-space);
                        $span = span($span.color, $span.text.substr($fitting));
                        $lx += $rx + $fitting;
                        $rx = 0;
                        $ry++;
                    }
                }
                else {
                    if $rx + $span.width < $x {
                        $rx += $span.width;
                        last;
                    }
                    elsif $rx + $span.width == $x {
                        return ($lx + $rx + $span.width, 0);
                    }
                    else {
                        my $remaining-space = $x - $rx;
                        return ($lx + $rx + self!count-fitting-in-width($span.text, $remaining-space), 0);
                    }
                }
            }
        }
    }

    method !count-fitting-in-width($text, $width --> Int) {
        my $count = $width;
        while duospace-width($text.substr(0, $count)) > $width {
            $count--;
        }
        $count
    }

    method !height-of-line(@line) {
        self!wrap-line(@line).elems
    }

    method !chars-in-line(@line) {
        log "chars-in-line";
        log @line.raku;
        @line.map(*.text.chars).sum
    }

    method !width-up-to-pos(@line, $pos is copy) {
        $pos = min $pos, self!chars-in-line(@line) - 1;
        my $width = 0;
        my $x = 0;
        for @line -> $span is copy {
            my $chars = $span.text.chars;
            if $pos <= $x + $chars {
                return ($width + span($span.color, $span.text.substr(0, $pos - $x)).width, span($span.color, $span.text.substr($pos - $x, 1)).width);
            }
            else {
                $x += $chars;
                $width += $span.width;
            }
        }
    }
    
    sub log($t) {
        "o".IO.spurt: $t ~ "\n", :append;
    }

    method !add-cursor(@line, $pos is copy) {
        $pos = min $pos, self!chars-in-line(@line);
        my @new-line;
        my $x = 0;
        for @line -> $span is copy {
            my $chars = $span.text.chars;
            log "span: $x, $pos, $chars";
            if $x <= $pos < $x + $chars {
                log "hit";
                if $pos - $x > 0 {
                    @new-line.push: span($span.color, $span.text.substr(0, $pos - $x));
                }
                log "$x: " ~ $span.text.substr($pos - $x, 1);
                @new-line.push: span-tree(
                    self.current-color(%( |self.current-color-states, :cursor)),
                    span($span.color, $span.text.substr($pos - $x, 1))).lines.eager[0][0];
                if $pos - $x + 1 < $chars {
                    @new-line.push: span($span.color, $span.text.substr($pos - $x + 1));
                }
            }
            else {
                log "other";
                $x += $chars;
                @new-line.push: $span;
            }
        }
        @new-line
    }

    #| Grab a chunk of laid-out span lines to feed to SpanBuffer.draw-frame
    method span-line-chunk(UInt:D $start, UInt:D $wanted) {
        sub line($i) {
            if $i == $!selected-line {
                my @line = span-tree(self.current-color(%( |self.current-color-states, :prompt )), @!lines[$i]).lines.eager[0];
                if $!show-cursor {
                    @line = self!add-cursor: @line, $!cursor-pos;
                }
                log @line.raku;
                @line
            }
            else {
                @!lines[$i]
            }
        }
        $!first-display-line = $start;
        my $pos = 0;
        my $line-index = @!dl-l[$start];
        my $line-display-line = @!l-dl[$line-index];

        my $start-offset = $start - $line-display-line;
        my @result = self!wrap-line(line($line-index++))[$start-offset..*];

        while @result.elems < $wanted && $line-index < @!lines.elems {
            @result.append(self!wrap-line(line($line-index++)));
        }

        log @result.raku;
        @result
    }

    multi method handle-event(Terminal::Widgets::Events::KeyboardEvent:D
                              $event where *.key.defined, AtTarget) {
        my constant %keymap =
            CursorDown  => 'select-next-line',
            CursorUp    => 'select-prev-line',
            CursorLeft  => 'select-prev-char',
            CursorRight => 'select-next-char',
            Ctrl-I      => 'next-input',    # Tab
            ShiftTab    => 'prev-input',    # Shift-Tab is weird and special
            ;

        my $keyname = $event.keyname;
        with %keymap{$keyname} {
            when 'select-next-line' { self.select-line($!selected-line + 1) }
            when 'select-prev-line' { self.select-line($!selected-line - 1) }
            when 'select-next-char' { self.select-char($!cursor-pos + 1) }
            when 'select-prev-char' { self.select-char($!cursor-pos - 1) }
            when 'next-input'  { self.focus-next-input }
            when 'prev-input'  { self.focus-prev-input }
        }
    }

    method select-line($no is copy) {
        $no = max($no, 0);
        $no = min($no, @!lines.end);
        $!selected-line = $no;
        self.ensure-y-span-visible(@!l-dl[$!selected-line], @!l-dl[$!selected-line] + self!height-of-line(@!lines[$no]) - 1);
        self.full-refresh;
    }

    method select-char($no is copy) {
        $no = max($no, 0);
        my $chars = self!chars-in-line(@!lines[$!selected-line]);
        if $!cursor-pos >= $chars {
            $no = $!cursor-pos;
        }
        else {
            $no = min($no, $chars - 1);
        }
        $!cursor-pos = $no;
        if !$!wrap {
            my ($upto, $cursor) = self!width-up-to-pos(@!lines[$!selected-line], $!cursor-pos);
            log "ensure $!cursor-pos $upto $cursor";
            self.ensure-x-span-visible($upto, $upto);
        }
        self.full-refresh;
    }

    multi method handle-event(Terminal::Widgets::Events::MouseEvent:D
                              $event where !*.mouse.pressed, AtTarget) {
        self.toplevel.focus-on(self);

        my ($x, $y) = $event.relative-to(self);
        my $clicked-display-line = $!first-display-line + $y;
        my $line-index = @!dl-l[min($clicked-display-line, @!dl-l.end)];
        if $!selected-line != $line-index {
            $!selected-line = $line-index;
            self.full-refresh;
        }
        my $rel-y = $y - @!l-dl[$line-index];
        ($x, $y) = self!display-pos-to-line-pos(@!lines[$line-index], self.x-scroll + $x, $rel-y);
        &!process-click($line-index, $x, $y) with &!process-click;
    }
}
