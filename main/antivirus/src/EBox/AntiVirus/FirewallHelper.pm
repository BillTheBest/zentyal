# Copyright (C) 2009-2011 eBox Technologies S.L.
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

package EBox::AntiVirus::FirewallHelper;
#
use strict;
use warnings;

use base 'EBox::FirewallHelper';

sub new
{
    my ($class, %params) = @_;
    my $self = $class->SUPER::new(%params);

    bless($self, $class);
    return $self;
}

sub output
{
    my ($self) = @_;
    my @rules;

    # freshclam update service
    push (@rules, '--protocol tcp --dport 80 -j ACCEPT');

    return \@rules;
}

1;
