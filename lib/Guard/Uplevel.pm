use strict;
use warnings;

package Guard::Uplevel;

our $VERSION = '0.01';

use Sub::Exporter -setup => {
    exports => ['scope_guard'],
    groups  => { default => ['scope_guard'] },
};

use XSLoader;

XSLoader::load(__PACKAGE__, $VERSION);

1;
