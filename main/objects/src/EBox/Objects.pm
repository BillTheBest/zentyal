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
package EBox::Objects;

use strict;
use warnings;

use base qw(EBox::GConfModule EBox::Model::ModelProvider);

use Net::IP;
use EBox::Validate qw( :all );
use EBox::Global;
use EBox::Objects::Model::ObjectTable;
use EBox::Objects::Model::MemberTable;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::MissingArgument;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataMissing;
use EBox::Exceptions::DataNotFound;
use EBox::Gettext;

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'objects',
                                      printableName => __n('Objects'),
                                      @_);

    $self->{'actions'} = {};
    $self->{'actions'}->{'addObject'} = __n('Added object {object}');
        $self->{'actions'}->{'addToObject'} =
            __n('Added {nname} ({ip}/{mask} [{mac}]) to object {object}');
    $self->{'actions'}->{'removeObject'} = __n('Removed object {object}');
    $self->{'actions'}->{'removeObjectForce'} =
        __n('Forcefully removed object {object}');
    $self->{'actions'}->{'removeFromObject'} =
        __n('Removed {nname} from object {object}');

    $self->{'objectModel'} = new EBox::Objects::Model::ObjectTable(
                                                    'gconfmodule' => $self,
                                                    'directory' => 'objectTable',
                                                                  );
    $self->{'memberModel'} = new EBox::Objects::Model::MemberTable(
                                                                   'gconfmodule' => $self,
                                                                   'directory' => 'memberTable');

    bless($self, $class);
    return $self;
}

## api functions

# Method: models
#
#      Overrides <EBox::Model::ModelProvider::models>
#
sub models {
       my ($self) = @_;

       return [$self->{'objectModel'}, $self->{'memberModel'}];
}

# Method: _exposedMethods
#
# Overrides:
#
#      <EBox::Model::ModelProvider::_exposedMethods>
#
sub _exposedMethods
{
    my ($self) = @_;

    my %exposedMethods =
        (
         'objectDescription1' => { action   => 'get',
                                   path     => [ 'ObjectTable' ],
                                   indexes  => [ 'id' ],
                                   selector => [ 'name' ],
                                 },
         'addObject1' => { action => 'add',
                           path   => [ 'ObjectTable' ],
                         },
         'setMemberIP' => { action   => 'set',
                            path     => [ 'ObjectTable', 'members' ],
                            indexes  => [ 'name', 'name' ],
                            selector => [ 'ipaddr' ]
                          },
         'addMember' => { action  => 'add',
                          path    => [ 'ObjectTable', 'members' ],
                          indexes => [ 'name' ],
                        },
         'removeMember' => { action  => 'del',
                             path    => [ 'ObjectTable', 'members' ],
                             indexes => [ 'name', 'name' ],
                           },
         'getMember'    => { action   => 'get',
                             path     => [ 'ObjectTable', 'members' ],
                             indexes  => [ 'name', 'name' ],
                           },
         'removeObject' => { action  => 'del',
                             path    => ['ObjectTable' ],
                             indexes => [ 'name' ],
                           },
         );

    return \%exposedMethods;
}

# Method: objects
#
#       Return all object names
#
# Returns:
#
#       Array ref. Each element is a hash ref containing:
#
#       id - object's id
#       name - object's name
sub objects
{
    my ($self) = @_;

    my @objects;
    for my $id (@{$self->{objectModel}->ids()}) {
	my $object = $self->{objectModel}->row($id);
        push (@objects, {
                            id => $id,
                            name => $object->valueByName('name')
                         });
    }

    return \@objects;
}

# Method: objectIds
#
#       Return all object ids
#
# Returns:
#
#       Array ref - containing ids
sub objectIds # (object)
{
    my ($self) = @_;

    my @ids = map { $_->{'id'} }  @{$self->objects()};
    return  \@ids;
}

# objectMembers
#
#       Return the members belonging to an object
#
# Parameters:
#
#       (POSITIONAL)
#
#       id - object's id
#
# Returns:
#
#       array ref - each element contains a hash with the member keys 'name'
#       (member's name), 'ipaddr' (ip's member), 'mask' (network mask's member),
#       'macaddr', (mac address' member)
#
# Exceptions:
#
#       <EBox::Exceptions::MissingArgument>
sub objectMembers # (object)
{
    my ($self, $id) = @_;

    unless (defined($id)) {
        throw EBox::Exceptions::MissingArgument("id");
    }

    my $object = $self->{'objectModel'}->row($id);
    return undef unless defined($object);

    return $object->subModel('members')->members();
}

# getMembersToObjectTable($id)

# objectAddresses
#
#       Return the network addresses of a object
#
# Parameters:
#
#       id - object's id
#       mask - return alse addresses' mask (named optional, default false)
#
# Returns:
#
#       array ref - containing an ip, empty array if
#       there are no addresses in the object
#       In case mask is wanted the elements of the array would be  [ip, mask]
#
sub objectAddresses
{
    my ($self, $id, @params) = @_;

    unless (defined($id)) {
        throw EBox::Exceptions::MissingArgument("id");
    }

    my $object = $self->{'objectModel'}->row($id);
    return undef unless defined($object);

    return $object->subModel('members')->addresses(@params);

}

# getMembersToObjectTable($id, [ 'ipaddr' ])

# Method: objectDescription
#
#       Return the description of an Object
#
# Parameters:
#
#       id - object's id
#
# Returns:
#
#       string - description of the Object
#
# Exceptions:
#
#       DataNotFound - if the Object does not exist
sub objectDescription  # (object)
{
    my ( $self, $id ) = @_;

    unless (defined($id)) {
        throw EBox::Exceptions::MissingArgument("id");
    }

    my $object = $self->{'objectModel'}->row($id);
    unless (defined($object)) {
        throw EBox::Exceptions::DataNotFound('data' => __('Object'),
                'value' => $object);
    }
    return $object->valueByName('name');
}

# get ( $id, ['name'])

# Method: objectInUse
#
#       Asks all installed modules if they are currently using an Object.
#
# Parameters:
#
#       object - the name of an Object
#
# Returns:
#
#       boolean - true if there is a module which uses the Object, otherwise
#       false
sub objectInUse # (object)
{
    my ($self, $object ) = @_;

    unless (defined($object)) {
        throw EBox::Exceptions::MissingArgument("id");
    }

    my $global = EBox::Global->getInstance();
    my @mods = @{$global->modInstancesOfType('EBox::ObjectsObserver')};
    foreach my $mod (@mods) {
        if ($mod->usesObject($object)) {
            return 1;
        }
    }

    return undef;
}

# Method: objectExists
#
#       Checks if a given object exists
#
# Parameters:
#
#       id - object's id
#
# Returns:
#
#       boolean - true if the Object exists, otherwise false
sub objectExists
{
    my ($self, $id) = @_;

    unless (defined($id)) {
        throw EBox::Exceptions::MissingArgument("id");
    }

    return defined($self->{'objectModel'}->row($id));
}



# Method: removeObjectForce
#
#       Forces an object to be deleted
#
# Parameters:
#
#       object - object description
#
sub removeObjectForce # (object)
{
    #action: removeObjectForce

    my ($self, $object)  = @_;
    my $global = EBox::Global->getInstance();
    my @mods = @{$global->modInstancesOfType('EBox::ObjectsObserver')};
    foreach my $mod (@mods) {
        $mod->freeObject($object);
    }
}

# Method: addObject
#
#   Add object to the objects table. Note this method must exist
#   because we must provide an easy way to migrate old objects module
#   to this new one.
#
# Parameters:
#
#   (NAMED)
#
#   id         - object's id *(optional*). It will be generated automatically
#                if none is passed
#
#   name       - object's name
#
#   members    - array ref containing the following hash ref in each value:
#
#                name        - member's name
#                ipaddr_ip   - member's ipaddr
#                ipaddr_mask - member's mask
#                macaddr     - member's mac address *(optional)*
#
# Example:
#
#       name => 'administration',
#       members => [
#                   { 'name'         => 'accounting',
#                     'ipaddr_ip'    => '192.168.1.3',
#                     'ipaddr_mask'  => '32',
#                     'macaddr'      => '00:00:00:FA:BA:DA'
#                   }
#                  ]
sub addObject
{
    my ($self, %params) = @_;

    $self->{'objectModel'}->addObject(%params);
}

# add( name => 'administration',
#      members => [
#                  { name    => 'accounting',
#                    ipaddr  => '192.168.1.3/32',
#                    macaddr => '00:00:00:FA:BA:DA'
#                  },
#                 ]

# Method: menu
#
#       Overrides EBox::Module method.
#
#
sub menu
{
    my ($self, $root) = @_;

    my $folder = new EBox::Menu::Folder('name' => 'Network',
                                        'text' => __('Network'),
                                        'separator' => 'Core',
                                        'order' => 40);

    my $item = new EBox::Menu::Item('url' => 'Network/Objects',
                                    'text' => __($self->title),
                                    'order' => 40);
    $folder->add($item);
    $root->add($folder);
}

1;
