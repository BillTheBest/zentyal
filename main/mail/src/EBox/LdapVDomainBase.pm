# Copyright (C) 2008-2012 eBox Technologies S.L.
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

package EBox::LdapVDomainBase;

use strict;
use warnings;

use EBox::Gettext;

sub new
{
	my $class = shift;
	my $self = {};
	bless($self, $class);
	return $self;
}

# Method: _addVdomain
#
# 	When a new virtual domain is created this method is called
#
# Parameters:
#
#   	vdomain - virtual domain name to be created
sub _addVDomain($$) # (vdomain)
{

}

# Method: _delVDomain
#
# 	When a virtual domain is deleted this method is called
#
# Parameters:
#
#   	vdomain - virtual domain name to be deleted
sub _delVDomain($$) # (vdomain)
{

}

# Method: _modifyVDomain
#
#	 When a virtual domain is modified this method is called
#
# Parameters:
#
#   	vdomain - vdomain name to be modified
sub _modifyVDomain($$) # (vdomain)
{

}

# Method: _delVDomainWarning
#
# 	When a virtual domain is to be deleted, modules should warn the sort of data
# 	(if any) is going to be removed
#
# Parameters:
#
#   	vdomain - virtual domain name
#
# Returns:
#
#   	array ref - Each element must be a string describing the sort of data
#   	is going to be removed if the virtual domain is deleted. If nothing is
#   	going to removed you must not return anything
sub _delVDomainWarning($$) # (vdomain)
{

}


1;
