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

package EBox::LdapUserBase;

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

# Method: _addUser
#
#    When a new user is created this method is called
#
# Parameters:
#
#   user - created user
sub _addUser
{

}

# Method: _delUser
#
#    When a user is deleted this method is called
#
# Parameters:
#
#   user - deleted user
sub _delUser
{

}

# Method: _modifyUser
#
#     When a user is modified this method is called
#
# Parameters:
#
#   user - modified user
sub _modifyUser
{

}

# Method: _delUserWarning
#
#   When a user is to be deleted, modules should warn the sort of  data
#   (if any) is going to be removed
#
# Parameters:
#
#   user - user
#
# Returns:
#
#   array - Each element must be a string describing the sort of data
#   is going to be removed if the user is deleted. If nothing is going to
#   removed you must not return anything
sub _delUserWarning
{

}

# Method: _addGroup
#
#   When a new user is created this method is called
#
# Parameters:
#
#   user - created group
sub _addGroup
{

}

# Method: _modifyGroup
#
#     When a group is modified this method is called
#
# Parameters:
#
#   group - modified group
sub _modifyGroup
{

}

# Method: _delGroup
#
#   When a group is deleted this method is called
#
# Parameters:
#
#   group - deleted group

sub _delGroup
{

}

# Method: _delGroupWarning
#
#   When a group is to be deleted, modules should warn the sort of  data
#   (if any) is going to be removed
#
# Parameters:
#
#   group - group
#
# Returns:
#
#   array  - Each element must be a string describing the sort of data
#   is going to be removed if the group is deleted. If nothing is going to
#   removed you must not return anything
sub _delGroupWarning
{

}

# Method: _userAddOns
#
#    When a user is to be edited, this method is called to get customized
#    mason components from modules depending on users stored in LDAP.
#    Thus, these components will be showed below the basic user data
#    The method has to return a hash ref containing:
#    'path'   => MASON_COMPONENT_PATH_TO_BE_ADDED
#    'params' => PARAMETERS_FOR_MASON_COMPONENT
#
#    The method can also return undef to sigmnal there is not add on for the
#    module
#
# Parameters:
#
#   user - user
#
# Returns:
#
#   A hash ref containing:
#
#   path - mason component which is going to be added
#   params - parameters for the mason component
#
#   - or -
#
#   undef if there is not component to add
sub _userAddOns
{

}

# Method: _groupAddOns
#
#     When a group is to be edited, this method is called to get customized
#     mason components from modules depending on groups stored in LDAP.
#     Thus, these components will be showed below the basic group data
#     The method has to return a hash ref containing:
#     'path'   => MASON_COMPONENT_PATH_TO_BE_ADDED
#     'params' => PARAMETERS_FOR_MASON_COMPONENT
#
# Parameters:
#
#       group - group to be edited
#
# Returns:
#
#       A hash ref containing:
#
#       path - mason component which is going to be added
#       params - parameters for the mason component
#
sub _groupAddOns
{

}

# Method: schemas
#
#    Returns the paths for the LDIF schemas that need to be loaded
#
# Returns:
#
#    array ref - Each element must be a string with a path to an LDIF schema
#
sub schemas
{
    return [];
}

# Method: acls
#
#    Returns the ACLs that need to be loaded into the LDAP configuration
#
# Returns:
#
#    array ref - Each element must be a string with an ACL
#
sub acls
{
    return [];
}

# Method: indexes
#
#    Returns the attributes that need to be indexed in a translucent LDAP
#
# Returns:
#
#    array ref - Each element must be a string with an attribute name to inex
#
sub indexes
{
    return [];
}


# Method: defaultUserModel
#
#   Returns the name of model that is used to compose a default template for
#   new user
#
# Returns:
#
#   string - model name
#
sub defaultUserModel
{
    return undef;
}


# Method: multipleOUSupport
#
#   Returns 1 if this module supports users in multiple OU's,
#   0 otherwise
#
sub multipleOUSupport
{
    return 0;
}

1;
