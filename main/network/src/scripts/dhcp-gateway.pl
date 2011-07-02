#!/usr/bin/perl

# Copyright (C) 2008-2010 eBox Technologies S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use warnings;

use EBox;
use EBox::Global;
use Error qw(:try);

EBox::init();

my $network = EBox::Global->modInstance('network');

my ($iface, $router) = @ARGV;

EBox::debug('Called dhcp-gateway.pl with the following values:');

$iface or exit;
EBox::debug("iface: $iface");

$router or exit;
EBox::debug("router: $router");

try {
    $network->setDHCPGateway($iface, $router);

    # Do not call regenGateways if we are restarting changes, they
    # are already going to be regenerated and also this way we
    # avoid nested lock problems
    unless (-f '/var/lib/zentyal/tmp/ifup.lock') {
        $network->regenGateways();
    }
} finally {
    exit;
};
