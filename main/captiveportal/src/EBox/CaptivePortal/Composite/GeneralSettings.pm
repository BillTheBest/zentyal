# Copyright (C) 2011-2012 eBox Technologies S.L.
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

package EBox::CaptivePortal::Composite::GeneralSettings;

use base 'EBox::Model::Composite';

use strict;
use warnings;

use EBox::Global;
use EBox::Gettext;

sub new
{
    my ($class) = @_;
    my $self = $class->SUPER::new();

    return $self;
}


# Method: _description
#
# Overrides:
#
#       <EBox::Model::Composite::_description>
#
sub _description
{
    my $description =
    {
        components      => [
                               'captiveportal/Settings',
                               'captiveportal/BWSettings',
                               'captiveportal/Interfaces',
                           ],
        layout          => 'top-bottom',
        name            => 'GeneralSettings',
        printableName   => __('Settings'),
        compositeDomain => 'CaptivePortal',
    };

    return $description;
}


1;
