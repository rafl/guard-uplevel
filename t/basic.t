use strict;
use warnings;
use Test::More;

use Guard::Uplevel;

our $i = 0;

sub foo {
    scope_guard 1, sub {
        $i++;
        warn 42;
    };
    return 23;
}

sub bar {
    is foo(), 23;
    is $i, 0;
}

bar();
is $i, 1;

done_testing;
