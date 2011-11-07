# Copyright (C) 2008-2011 eBox Technologies S.L.
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

package EBox::LdapModule;

use strict;
use warnings;

use EBox::Gettext;
use EBox::Global;
use EBox::Exceptions::NotImplemented;
use EBox::Ldap;

use Error qw(:try);

use constant ROOT_CONFIG_DN => 'cn=admin,cn=config';

sub new
{
	my $class = shift;
	my $self = {};
	bless($self, $class);
	return $self;
}

# Method: _ldapModImplementation
#
#	All modules using any of the functions in LdapUserBase.pm
#	should override this method to return the implementation
#	of that interface.
#
# Returns:
#
#	An object implementing EBox::LdapUserBase
sub _ldapModImplementation
{
	throw EBox::Exceptions::NotImplemented();
}

# Method: ldap
#
#   Provides an EBox::Ldap object with the proper configuration for the
#   LDAP setup of this ebox
sub ldap
{
    my ($self) = @_;

    my $users = EBox::Global->modInstance('users');

    unless(defined($self->{ldap})) {
        $self->{ldap} = EBox::Ldap->instance();
    }
    return $self->{ldap};
}

sub masterLdap
{
    my ($self) = @_;

    my $users = EBox::Global->modInstance('users');
    my $ldap;
    unless ($users->mode() eq 'slave') {
        $self->ldap->ldapCon();
        $ldap = $self->ldap->{ldap};
    } else {
        my $remote = $users->remoteLdap();
        my $password = $users->remotePassword();
        $ldap = EBox::Ldap::safeConnect("ldap://$remote");
        EBox::Ldap::safeBind($ldap, $self->ldap->rootDn(), $password);
    }
    return $ldap;
}

# Method: _loadSchema
#
#      loads an LDAP schema from an LDIF file
#
# Parameters:
#          file - LDIF file
#
sub _loadSchema
{
    my ($self, $ldiffile) = @_;

    my $users = EBox::Global->modInstance('users');

    my $mode = $users->mode();
    if ($mode eq 'master' or $mode eq 'ad-slave') {
        $self->ldap->ldapCon();
        my $ldap = $self->ldap->{ldap};
        $self->_loadSchemaDirectory($ldap, $ldiffile);
    } elsif ($mode eq 'slave') {
        my $password = $self->ldap->getPassword();
        my $ldap;
        my @ports = (389, 1389, 1390);
        for my $port (@ports) {
            $ldap = EBox::Ldap::safeConnect("127.0.0.1:$port");
            EBox::Ldap::safeBind($ldap, ROOT_CONFIG_DN, $password);
            $self->_loadSchemaDirectory($ldap, $ldiffile);
        }
    } else {
         throw EBox::Exceptions::Internal(
            "Trying to load schema with unknown LDAP mode: $mode");
    }
}

sub _loadSchemaDirectory
{
    my ($self, $ldap, $ldiffile) = @_;
    my $ldif = Net::LDAP::LDIF->new($ldiffile, "r", onerror => 'undef' );
    defined($ldif) or throw EBox::Exceptions::Internal(
            "Can't load LDIF file: " . $ldiffile);

    while(not $ldif->eof()) {
        my $entry = $ldif->read_entry();
        if ($ldif->error()) {
            throw EBox::Exceptions::Internal(
                "Can't load LDIF file: " . $ldiffile);
        }
        my $dn = $entry->dn();
        $dn =~ m/^cn=(.*?),cn=schema,cn=config$/;
        my $schemaname = $1;
        my %args = (
            'base' => 'cn=schema,cn=config',
            'scope' => 'subtree',
            'filter' => "(cn={*}$schemaname)",
            'attrs' => ['objectClass']
        );
        my $result = $ldap->search(%args);
        if ($result->entries() == 0) {
            $result = $ldap->add($entry);
            if ($result->is_error()) {
                EBox::error($result->error());
            }
        }
    }
    $ldif->done();
}

#   Method: _loadACL
#
#      loads an ACL
#
# Parameters:
#          acl - string with the ACL (it has to start with 'to')
#
sub _loadACL
{
    my ($self, $acl) = @_;

    my $users = EBox::Global->modInstance('users');
    my $mode = $users->mode();

    if ($mode eq 'master' or $mode eq 'ad-slave') {
        $self->ldap->ldapCon();
        my $ldap = $self->ldap->{ldap};
        $self->_loadACLDirectory($ldap, $acl);
    } elsif ($mode eq 'slave') {
        my $password = $self->ldap->getPassword();
        my $ldap;
        my @ports = (389, 1389, 1390);
        for my $port (@ports) {
            $ldap = EBox::Ldap::safeConnect("127.0.0.1:$port");
            EBox::Ldap::safeBind($ldap, ROOT_CONFIG_DN, $password);
            $self->_loadACLDirectory($ldap, $acl);
        }
    } else {
        throw EBox::Exceptions::Internal(
            "Loading ACL with unknown LDAP mode: $mode");
    }
}

sub _loadACLDirectory
{
    my ($self, $ldap, $acl) = @_;

    my $dn = 'olcDatabase={1}hdb,cn=config';
    my %args = (
            'base' => $dn,
            'scope' => 'base',
            'filter' => "(objectClass=*)",
            'attrs' => ['olcAccess']
    );
    my $result = $ldap->search(%args);
    my $entry = ($result->entries)[0];
    my $attr = ($entry->attributes)[0];
    my $found = undef;
    my @rules = $entry->get_value($attr);
    for my $access (@rules) {
        if($access =~ m/^{\d+}\Q$acl\E$/) {
            $found = 1;
            last;
        }
    }
    if(not $found) {
        # place the new rule *before* the last 'catch-all' one
        my $last = pop(@rules);
        $last =~ s/^{\d+}//;
        push(@rules, $acl);
        push(@rules, $last);
        my %args = (
            'replace' => [ 'olcAccess' => \@rules ]
        );
        try {
            $ldap->modify($dn, %args);
        } otherwise {
            throw EBox::Exceptions::Internal("Invalid ACL: $acl");
        };
    }
}

#   Method: _addTranslucentLocalAttribute
#
#      adds an attribute as local in the translucent LDAP
#
# Parameters:
#          attribute - string with the attribute name
#
sub _addTranslucentLocalAttribute
{
    my ($self, $attribute) = @_;

    EBox::Sudo::root("sed -i -e 's/^olcTranslucentLocal: \\(.*\\)/olcTranslucentLocal: $attribute,\\1/' /etc/ldap/slapd-translucent.d/cn=config/olcDatabase={1}hdb/olcOverlay={0}translucent.ldif");
}


#   Method: _addIndex
#
#       Create indexes in LDAP for an attribute
#
# Parameters:
#          attribute - string with the attribute to be indexed in LDAP
#
sub _addIndex
{
    my ($self, $attribute) = @_;

    my $users = EBox::Global->modInstance('users');
    my $mode = $users->mode();

    if ($mode eq 'master' or $mode eq 'ad-slave') {
        $self->ldap->ldapCon();
        my $ldap = $self->ldap->{ldap};
        $self->_addIndexDirectory($ldap, $attribute);
    } elsif ($mode eq 'slave') {
        my $password = $self->ldap->getPassword();
        my $ldap;
        my @ports = (389, 1389, 1390);
        for my $port (@ports) {
            $ldap = EBox::Ldap::safeConnect("127.0.0.1:$port");
            EBox::Ldap::safeBind($ldap, ROOT_CONFIG_DN, $password);
            $self->_addIndexDirectory($ldap, $attribute);
        }
    } else {
        throw EBox::Exceptions::Internal(
            "Creating index with unknown LDAP mode: $mode");
    }
}


sub _addIndexDirectory
{
    my ($self, $ldap, $attribute) = @_;

    my $index = "$attribute eq";

    my $dn = 'olcDatabase={1}hdb,cn=config';
    my %args = (
            'base' => $dn,
            'scope' => 'base',
            'filter' => "(objectClass=*)",
            'attrs' => ['olcDbIndex']
    );
    my $result = $ldap->search(%args);
    my $entry = ($result->entries)[0];
    my $attr = ($entry->attributes)[0];
    my $found = undef;
    my @indexes = $entry->get_value($attr);
    for my $dbindex (@indexes) {
        if($dbindex eq $index) {
            $found = 1;
            last;
        }
    }
    if(not $found) {
        push(@indexes, $index);
        my %args = (
            'replace' => [ 'olcDbIndex' => \@indexes ]
        );
        try {
            $ldap->modify($dn, %args);
        } otherwise {
            throw EBox::Exceptions::Internal("Invalid index: $index");
        };
    }
}


#   Method: performLDAPActions
#
#      adds the schemas, acls and local attributes specified in the
#      LdapUserImplementation
#
# Parameters:
#          attribute - string with the attribute name
#
sub performLDAPActions
{
    my ($self) = @_;

    my $users = EBox::Global->modInstance('users');
    my $slave = $users->mode() eq 'slave';
    if ($slave) {
        $users->startIfRequired();
    }
    my $ldapuser = $self->_ldapModImplementation();
    my @schemas = @{ $ldapuser->schemas() };
    for my $schema (@schemas) {
        $self->_loadSchema($schema);
    }
    my @acls = @{ $ldapuser->acls() };
    for my $acl (@acls) {
        $self->_loadACL($acl);
    }
    my @indexes = @{ $ldapuser->indexes() };
    for my $index (@indexes) {
        $self->_addIndex($index);
    }
    if ($slave) {
        $users->stopIfRequired();
        my @attrs = @{ $ldapuser->localAttributes() };
        for my $attr (@attrs) {
            $self->_addTranslucentLocalAttribute($attr);
        }
    }
    $users->restoreState();
}

1;
