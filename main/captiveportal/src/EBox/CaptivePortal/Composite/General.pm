# Copyright (C) 2011 eBox Technologies S.L.
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

package EBox::CaptivePortal::Composite::General;

use base 'EBox::Model::Composite';

use EBox::Gettext;
use EBox::Global;

# Group: Public methods

# Constructor: new
#
#     Constructor for the Gateway composite.
#
sub new
{
    my ($class, @params) = @_;

    my $self = $class->SUPER::new(@params);
    return $self;
}

# Method: _description
#
# Overrides:
#
#     <EBox::Model::Composite::_description>
#
sub _description
{
    my ($self) = @_;

    my @components;
    push (@components, 'captiveportal/GeneralSettings');

    # show secondary ldap configuration if enabled
    if (EBox::Config::configkey('captive_secondary_ldap')) {
        push (@components, 'captiveportal/SecondaryLDAP');
    }

    push (@components, 'captiveportal/Users');

    my $description = {
        components      => \@components,
        layout          => 'tabbed',
        name            => 'General',
        pageTitle       => __('Captive Portal'),
        headTitle       => undef,
        compositeDomain => 'CaptivePortal',
    };

    return $description;
}

1;
