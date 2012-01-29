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

package EBox::DHCP;

use strict;
use warnings;

use base qw(EBox::Module::Service
            EBox::NetworkObserver
            EBox::LogObserver
            EBox::Model::ModelProvider
            EBox::Model::CompositeProvider);

use EBox::Config;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataNotFound;
use EBox::Gettext;
use EBox::Global;
use EBox::Menu::Item;
use EBox::Menu::Folder;
use EBox::Objects;
use EBox::Validate qw(:all);

use EBox::Model::ModelManager;
use EBox::Model::CompositeManager;

use EBox::Sudo;
use EBox::NetWrappers qw(:all);
use EBox::Service;
use EBox::DHCPLogHelper;

use EBox::Dashboard::Section;
use EBox::Dashboard::List;

# Models & Composites
use EBox::Common::Model::EnableForm;
use EBox::DHCP::Composite::AdvancedOptions;
use EBox::DHCP::Composite::InterfaceConfiguration;
use EBox::DHCP::Composite::General;
use EBox::DHCP::Composite::Interfaces;
use EBox::DHCP::Composite::OptionsTab;
use EBox::DHCP::Model::DynamicDNS;
use EBox::DHCP::Model::FixedAddressTable;
use EBox::DHCP::Model::LeaseTimes;
use EBox::DHCP::Model::Options;
use EBox::DHCP::Model::RangeInfo;
use EBox::DHCP::Model::RangeTable;
use EBox::DHCP::Model::ThinClientOptions;
use Net::IP;
use Error qw(:try);
use Perl6::Junction qw(any);
use Text::DHCPLeases;

# Module local conf stuff
# FIXME: extract this from somewhere to support multi-distro?
#use constant DHCPCONFFILE => "@DHCPDCONF@";
#use constant LEASEFILE => "@DHCPDLEASES@";
#use constant PIDFILE => "@DHCPDPID@";
#use constant DHCP_SERVICE => "@DHCPD_SERVICE@";
use constant DHCPCONFFILE => "/etc/dhcp/dhcpd.conf";
use constant LEASEFILE => "/var/lib/dhcp/dhcpd.leases";
use constant PIDFILE => "/var/run/dhcp-server/dhcpd.pid";
use constant DHCP_SERVICE => "zentyal.dhcpd";

use constant TFTP_SERVICE => "tftpd-hpa";

use constant CONF_DIR => EBox::Config::conf() . 'dhcp/';
use constant PLUGIN_CONF_SUBDIR => 'plugins/';
use constant TFTPD_CONF_DIR => '/var/lib/tftpboot/';
use constant INCLUDE_DIR => EBox::Config::etc() . 'dhcp/';
use constant APPARMOR_DHCPD => '/etc/apparmor.d/local/usr.sbin.dhcpd';

# Group: Public and protected methods

# Constructor: _create
#
#    Create the zentyal-dhcp module
#
# Overrides:
#
#    <EBox::Module::Service::_create>
#
sub _create
{
    my $class = shift;
    my $self  = $class->SUPER::_create(name => 'dhcp',
                                       printableName => 'DHCP',
                                       @_);
    bless ($self, $class);

    return $self;
}

# Method: usedFiles
#
#   Override EBox::Module::Service::usedFiles
#
sub usedFiles
{
    return [
            {
             'file' => DHCPCONFFILE,
             'module' => 'dhcp',
             'reason' => __x('{server} configuration file', server => 'dhcpd'),
            },
            {
             'file'   => APPARMOR_DHCPD,
             'module' => 'dhcp',
             'reason' => __x('AppArmor profile for {server} daemon', server => 'dhcpd'),
            },
           ];
}

# Method: initialSetup
#
# Overrides:
#   EBox::Module::Base::initialSetup
#
sub initialSetup
{
    my ($self, $version) = @_;

    # Create default services, rules and conf dir
    # only if installing the first time
    unless ($version) {
        my $firewall = EBox::Global->modInstance('firewall');

        $firewall->addInternalService(
                'name' => 'tftp',
                'description' => __d('Trivial File Transfer Protocol'),
                'protocol' => 'udp',
                'sourcePort' => 'any',
                'destinationPort' => 69,
                );

        $firewall->addInternalService(
                'name' => 'dhcp',
                'description' => __d('Dynamic Host Configuration Protocol'),
                'protocol' => 'udp',
                'sourcePort' => 'any',
                'destinationPort' => 67,
                );

        $firewall->saveConfigRecursive();

        mkdir (CONF_DIR, 0755);
    }
}

# Method: appArmorProfiles
#
#   Overrides to set the own AppArmor profile to allow Dynamic DNS to
#   work and LSTP configuration using /etc/zentyal/dhcp/...
#
# Overrides:
#
#    <EBox::Module::Base::appArmorProfiles>
#
sub appArmorProfiles
{
    my ($self) = @_;

    my @params = ( 'keysFile' => $self->_keysFile(),
                   'confDir'  => $self->IncludeDir() );

    return [
        { 'binary' => 'usr.sbin.dhcpd',
          'local'  => 1,
          'file'   => 'dhcp/apparmor-dhcpd.local.mas',
          'params' => \@params }
       ];
}

# Method: actions
#
#   Override EBox::Module::Service::actions
#
sub actions
{
    return [
        {
            'action' => __x('Disable {server} init script', server => 'dhcpd'),
            'reason' => __('Zentyal will take care of start and stop ' .
                'the service'),
            'module' => 'dhcp',
        }
    ];
}

# Method: _daemons
#
# Overrides:
#
#   <EBox::Module::Service::daemons>
#
sub _daemons
{
    return [ { 'name' => DHCP_SERVICE } ];
}

# Method: _setConf
#
#      Writes the configuration files
#
# Overrides:
#
#      <EBox::Module::Base::_setConf>
#
sub _setConf
{
    my ($self) = @_;
    $self->_setDHCPConf();
    $self->_setTFTPDConf();
}

# Method: menu
#
# Overrides:
#
#     <EBox::Module::menu>
#
#
sub menu
{
        my ($self, $root) = @_;
        $root->add(new EBox::Menu::Item('url' => 'DHCP/Composite/General',
                                        'text' => $self->printableName(),
                                        'separator' => 'Infrastructure',
                                        'order' => 410));
}

# Method: depends
#
#     DHCP depends on DNS configuration only if the Dynamic DNS
#     feature is done.
#
# Overrides:
#
#     <EBox::Module::Base::depends>
#
sub depends
{
    my ($self) = @_;

    my $dependsList = $self->SUPER::depends();
    if ( $self->_dynamicDNSEnabled() ) {
        push(@{$dependsList}, 'dns');
    }

    return $dependsList;

}

# Method: models
#
# Overrides:
#
#     <EBox::Model::ModelProvider::models>
#
sub models
{

    my ($self) = @_;

    my @models;
    my $net = EBox::Global->modInstance('network');
    foreach my $iface (@{$net->allIfaces()}) {
        if ( $net->ifaceMethod($iface) eq 'static' ) {
            # Create models
            $self->{rangeModel}->{$iface} =
              new EBox::DHCP::Model::RangeTable(
                                                gconfmodule => $self,
                                                directory   => "RangeTable/$iface",
                                                interface   => $iface
                                               );
            push ( @models, $self->{rangeModel}->{$iface} );
            $self->{fixedAddrModel}->{$iface} =
              new EBox::DHCP::Model::FixedAddressTable(
                                                       gconfmodule => $self,
                                                       directory   => "FixedAddressTable/$iface",
                                                       interface   => $iface);
            push ( @models, $self->{fixedAddrModel}->{$iface} );
            $self->{optionsModel}->{$iface} =
              new EBox::DHCP::Model::Options(
                                             gconfmodule => $self,
                                             directory   => "Options/$iface",
                                             interface   => $iface);
            push ( @models, $self->{optionsModel}->{$iface} );
            $self->{leaseTimesModel}->{$iface} =
              new EBox::DHCP::Model::LeaseTimes(
                                                gconfmodule => $self,
                                                directory   => "LeaseTimes/$iface",
                                                interface   => $iface);
            push ( @models, $self->{leaseTimesModel}->{$iface} );
            $self->{thinClientModel}->{$iface} =
              new EBox::DHCP::Model::ThinClientOptions(
                                                       gconfmodule => $self,
                                                       directory   => "ThinClientOptions/$iface",
                                                       interface   => $iface);
            push ( @models, $self->{thinClientModel}->{$iface} );
            $self->{dynamicDNSModel}->{$iface} =
              new EBox::DHCP::Model::DynamicDNS(
                                                gconfmodule => $self,
                                                directory   => "DynamicDNS/$iface",
                                                interface   => $iface);
            push ( @models, $self->{dynamicDNSModel}->{$iface} );
            $self->{rangeInfoModel}->{$iface} =
              new EBox::DHCP::Model::RangeInfo(
                                               gconfmodule => $self,
                                               directory   => "RangeInfo/$iface",
                                               interface   => $iface);
            push ( @models, $self->{rangeInfoModel}->{$iface});
        }
    }

    return \@models;
}

# Method: _exposedMethods
#
# Overrides:
#
#     <EBox::Model::ModelProvider::_exposedMethods>
#
sub _exposedMethods
{
    my ($self) = @_;

    my %methods =
      ( 'setOption' => { action   => 'set',
                         path     => [ 'Options' ],
                         indexes  => [ 'id' ],
                       },
        'setDefaultGateway' => { action   => 'set',
                                 path     => [ 'Options' ],
                                 indexes  => [ 'id' ],
                                 selector => [ 'default_gateway' ],
                               },
        'addRange'          => { action   => 'add',
                                 path     => [ 'RangeTable' ],
                               },
        'removeRange'       => { action   => 'del',
                                 path     => [ 'RangeTable' ],
                                 indexes  => [ 'name' ],
                               },
        'setRange'          => { action   => 'set',
                                 path     => [ 'RangeTable' ],
                                 indexes  => [ 'name' ],
                               },
        'addFixedAddress'   => { action   => 'add',
                                 path     => [ 'FixedAddressTable' ],
                               },
        'setFixedAddress'   => { action   => 'set',
                                 path     => [ 'FixedAddressTable' ],
                                 indexes  => [ 'object' ],
                               },
        'removeFixedAddress' => { action   => 'del',
                                  path     => [ 'FixedAddressTable' ],
                                  indexes  => [ 'object' ],
                                },
        'setLeases'          => { action  => 'set',
                                  path    => [ 'LeaseTimes' ],
                                  indexes => [ 'id' ],
                                },
        'dynamicDNSDomains'  => { action  => 'get',
                                  path    => [ 'DynamicDNS' ],
                                  indexes => [ 'id' ],
                              },
        );
    return \%methods;

}

# Examples:
#  $dhcp->setFixedAddress('eth0', 'object-name', description => 'new desc');
#  $dhcp->addFixedAddress('eth0', object => 'objName', description => 'new desc');

# Method: composites
#
# Overrides:
#
#     <EBox::Model::CompositeProvider::composites>
#
sub composites
{
    my ($self) = @_;

    my @composites;
    my $net = EBox::Global->modInstance('network');
    foreach my $iface (@{$net->allIfaces()}) {
        if ( $net->ifaceMethod($iface) eq 'static' ) {
            # Create models
            push ( @composites,
                   new EBox::DHCP::Composite::InterfaceConfiguration(interface => $iface));
            push ( @composites,
                   new EBox::DHCP::Composite::OptionsTab(interface => $iface));
            push ( @composites,
                   new EBox::DHCP::Composite::AdvancedOptions(interface => $iface));
        }
    }
    push ( @composites,
           new EBox::DHCP::Composite::Interfaces());
    push ( @composites,
           new EBox::DHCP::Composite::General());

    return \@composites;
}

# Method: initRange
#
#   Return the initial host address range for a given interface
#
# Parameters:
#
#   iface - String interface name
#
# Returns:
#
#   String - containing the initial range
#
sub initRange # (interface)
{
    my ($self, $iface) = @_;

    my $net = EBox::Global->modInstance('network');
    my $address = $net->ifaceAddress($iface);
    my $netmask = $net->ifaceNetmask($iface);

    my $network = ip_network($address, $netmask);
    my ($first, $last) = $network =~ /(.*)\.(\d+)$/;
    my $init_range = $first . "." . ($last+1);
    return $init_range;
}

# Method: endRange
#
#   Return the final host address range for a given interface
#
# Parameters:
#
#   iface - String interface name
#
# Returns:
#
#   string - containing the final range
#
sub endRange # (interface)
{
    my ($self, $iface) = @_;

    my $net = EBox::Global->modInstance('network');
    my $address = $net->ifaceAddress($iface);
    my $netmask = $net->ifaceNetmask($iface);

    my $broadcast = ip_broadcast($address, $netmask);
    my ($first, $last) = $broadcast =~ /(.*)\.(\d+)$/;
    my $end_range = $first . "." . ($last-1);
    return $end_range;
}

# Method: defaultGateway
#
#   Get the default gateway that will be sent to DHCP clients for a
#   given interface
#
# Parameters:
#
#       iface - interface name
#
# Returns:
#
#       string - the default gateway in a IP address form
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the interface is not
#       static or the given type is none of the suggested ones
#
#       <EBox::Exceptions::DataNotFound> - thrown if the interface is
#       not found
#
sub defaultGateway # (iface)
{
    my ($self, $iface) = @_;

    my $network = EBox::Global->modInstance('network');

    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                value => $iface);
    }

    #if iface is not static, throw exception
    if($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
            iface => $iface));
    }

    return $self->_getModel('optionsModel', $iface)->defaultGateway();
}

# Method: searchDomain
#
#   Get the search domain that will be sent to DHCP clients for a
#   given interface
#
# Parameters:
#
#       iface - String interface name
#
# Returns:
#
#   String - the search domain
#
#       undef  - if the none search domain has been set
#
sub searchDomain # (iface)
{
    my ($self, $iface) = @_;

    my $network = EBox::Global->modInstance('network');

    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                value => $iface);
    }

    #if iface is not static, throw exception
    if($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
            iface => $iface));
    }

#   $self->get_string("$iface/search");
    return $self->_getModel('optionsModel', $iface)->searchDomain();
}

# Method: nameserver
#
#   Get the nameserver that will be sent to DHCP clients for a
#   given interface
#
# Parameters:
#
#       iface - String interface name
#       number - Int nameserver number (1 or 2)
#
#   Returns:
#
#       string - the nameserver or undef if there is no
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the interface is not
#       static or the given type is none of the suggested ones
#
#       <EBox::Exceptions::DataNotFound> - thrown if the interface is
#       not found
#
#       <EBox::Exceptions::MissingArgument> - thrown if any compulsory
#       argument is missing
#
sub nameserver # (iface,number)
{
    my ($self, $iface, $number) = @_;

    if ( not defined ( $number )) {
        throw EBox::Exceptions::MissingArgument('number');
    }
    my $network = EBox::Global->modInstance('network');

    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                value => $iface);
    }

    #if iface is not static, throw exception
    if($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
            iface => $iface));
    }

#   $self->get_string("$iface/nameserver$number");
    return $self->_getModel('optionsModel', $iface)->nameserver($number);
}

# Method: ntpServer
#
#       Get the NTP server that will be sent to DHCP clients for a
#       given interface
#
# Parameters:
#
#       iface - String the interface name
#
# Returns:
#
#       String - the IP address for the NTP server, undef if no
#                NTP server has been configured
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the interface is not
#       static or the given type is none of the suggested ones
#
#       <EBox::Exceptions::DataNotFound> - thrown if the interface is
#       not found
#
#       <EBox::Exceptions::MissingArgument> - thrown if any compulsory
#       argument is missing
#
sub ntpServer # (iface)
{
    my ($self, $iface) = @_;

    my $network = EBox::Global->modInstance('network');
    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                                             value => $iface);
    }

    #if iface is not static, throw exception
    if($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
                                             iface => $iface));
    }

    return $self->_getModel('optionsModel', $iface)->ntpServer();
}

# Method: winsServer
#
#       Get the WINS server that will be sent to DHCP clients for a
#       given interface
#
# Parameters:
#
#       iface - String the interface name
#
# Returns:
#
#       String - the IP address for the WINS server, undef if no
#                WINS server has been configured
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the interface is not
#       static or the given type is none of the suggested ones
#
#       <EBox::Exceptions::DataNotFound> - thrown if the interface is
#       not found
#
#       <EBox::Exceptions::MissingArgument> - thrown if any compulsory
#       argument is missing
#
sub winsServer # (iface)
{
    my ($self, $iface) = @_;

    my $network = EBox::Global->modInstance('network');
    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                                             value => $iface);
    }

    #if iface is not static, throw exception
    if($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
                                             iface => $iface));
    }

    return $self->_getModel('optionsModel', $iface)->winsServer();
}

# Method: staticRoutes
#
#   Get the static routes. It polls the Zentyal modules which
#   implements <EBox::DHCP::StaticRouteProvider>
#
# Returns:
#
#   hash ref - contating the static toutes in hash references. The
#   key is the subnet in CIDR notation that denotes where is
#   appliable the new route.  The values are hash reference with
#   the keys 'destination', 'netmask' and 'gw'
#
sub staticRoutes
{
    my ($self) = @_;
    my %staticRoutes = ();

    my @modules = @{ EBox::Global->modInstancesOfType('EBox::DHCP::StaticRouteProvider') };
    foreach  my $mod (@modules) {
        my @modStaticRoutes = @{ $mod->staticRoutes() };
        while (@modStaticRoutes) {
            my $net   = shift @modStaticRoutes;
            my $route = shift @modStaticRoutes;
            if (exists $staticRoutes{$net}) {
                push  @{$staticRoutes{$net}}, $route;
            }
            else {
                $staticRoutes{$net} = [$route];
            }
        }
    }

    return \%staticRoutes;
}

sub notifyStaticRoutesChange
{
    my ($self) = @_;
    $self->setAsChanged();
}


# Method: rangeAction
#
#   Set/add a range for a given interface
#
# Parameters:
#
#   iface - String Interface name
#       action - String to perform (add/set/del)
#
#       indexValue - String index to use to set a new value, it can be a
#       name, a from IP addr or a to IP addr.
#
#       indexField - String the field name to use as index
#
#   name - String the range name
#   from - String start of range, an ip address
#   to - String end of range, an ip address
#
#       - Named parameters
#
# Exceptions:
#
#    <EBox::Exceptions::DataNotFound> - Interface does not exist
#    <EBox::Exceptions::External> - interface is not static
#    <EBox::Exceptions::External - invalid range
#    <EBox::Exceptions::External - range overlap
#
sub rangeAction # (iface, name, from, to)
{
    my ($self, %args) = @_;

    my $iface = delete ($args{iface});
    my $action = delete ($args{action});
    unless ( $action eq any(qw(add set del))) {
        throw EBox::Exceptions::External(__('Not a valid action: add, set and del '
                    . 'are available'));
    }

    my $network = EBox::Global->modInstance('network');

    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                value => $iface);
    }

    #if iface is not static, throw exception
    if($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
                    iface => $iface));
    }

    my $rangeModel = $self->_getModel('rangeModel', $iface);
    if ( $action eq 'add' ) {
        $rangeModel->add( name => $args{name},
                from => $args{from},
                to   => $args{to});
    } elsif ( $action eq 'set' ) {
        my $index = delete ( $args{indexValue} );
        my $indexField = delete ( $args{indexField} );
        my @args = map { $_ => $args{$_} } keys (%args);
        $rangeModel->setIndexField($indexField);
        $rangeModel->set( $index, @args );
    } elsif ( $action eq 'del' ) {
        my $index = delete ( $args{indexValue} );
        my $indexField = delete ( $args{indexField} );
        $rangeModel->setIndexField($indexField);
        $rangeModel->del( $index );
    }
}

# Method: ranges
#
#   Return all the set ranges for a given interface
#
# Parameters:
#
#   iface - String interface name
#
# Returns:
#
#   array ref - contating the ranges in hash references. Each hash holds
#   the keys 'name', 'from' and 'to'
#
# Exceptions:
#
#       <EBox::Exceptions::DataNotFound> - Interface does not exist
#
sub ranges # (iface)
{
    my ($self, $iface) = @_;

    my $global = EBox::Global->getInstance();
    my $network = EBox::Global->modInstance('network');

    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound('data' => __('Interface'),
                                             'value' => $iface);
    }

    my $model = $self->_getModel('rangeModel', $iface);
    my @ranges;
    for my $id (@{$model->ids()}) {
        my $row = $model->row($id);
        push (@ranges,
              { name    => $row->valueByName('name'),
                from    => $row->valueByName('from'),
                to      => $row->valueByName('to'),
                options => $self->_thinClientOptions($iface, $row->valueByName('name'))
               });
    }

    return \@ranges;
}

# Method: fixedAddresses
#
#   Return the list of fixed addreses
#
# Parameters:
#
#   iface - String interface name
#
#       readonly - Boolean indicate to get the information from
#                  readonly backend or current one
#                  *(Optional)* Default value: False
#
# Returns:
#
#   array ref - contating the fixed addresses in hash refereces.
#   Each hash holds the keys 'mac', 'ip' and 'name'
#
#       hash ref - if you set readOnly parameter, then it returns
#           two keys:
#              options - hash ref containing the PXE options

#              members - array ref containing the members of this
#                        objects as it does if readOnly is set to false
#
# Exceptions:
#
#   <EBox::Exceptions::DataNotFound> - Interface does not exist
#
#       <EBox::Exceptions::External> - Interface is not static
#
sub fixedAddresses # (interface, readOnly)
{
    my ($self,$iface, $readOnly) = @_;

    $readOnly = 0 unless ($readOnly);

    my $global  = EBox::Global->getInstance($readOnly);
    my $network = $global->modInstance('network');

    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                                             value => $iface);
    }

    #if iface is not static, throw exception
    if ($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
                                             iface => $iface));
    }

    my $model = $self->_getModel('fixedAddrModel', $iface);
    my %addrs;
    my $objMod = $global->modInstance('objects');
    for my $id (@{$model->ids()}) {
        my $row   = $model->row($id);
        my $objId = $row->valueByName('object');
        my $mbs   = $objMod->objectMembers($objId);
        $addrs{$objId} = { options => $self->_thinClientOptions($iface, $objId),
                           members => [] };

        foreach my $member (@{$mbs}) {
            # use only IP address member type
            if ($member->{type} ne 'ipaddr') {
                next;
            }

            # Filter out the ones which does not have a MAC address
            # and a mask of 32, it does not belong to the given
            # interface and member name is unique within the fixed
            # addresses realm
            if ( $self->_allowedMemberInFixedAddress($iface, $member, $objId, $readOnly) ) {
                push (@{$addrs{$objId}->{members}}, {
                    name => $member->{name},
                    ip   => $member->{ip},
                    mac  => $member->{macaddr},
                });
            }
        }
    }

    if ( $readOnly ) {
        # The returned value is grouped by object id
        return \%addrs;
    } else {
        my @mbs = ();
        foreach my $obj (values %addrs) {
            push(@mbs, @{$obj->{members}});
        }
        return \@mbs;
    }
}

# Group: Static or class methods

# Method: ConfDir
#
#      Get the DHCP configuration directory where to store the user
#      defined configuration files
#
# Parameters:
#
#      iface - String the interface which the user configuration file
#      is within
#
# Returns:
#
#      String - the configuration path
#
sub ConfDir
{
    my ($class, $iface) = @_;

    # Create directory unless it already exists
    unless ( -d CONF_DIR . $iface ) {
        mkdir ( CONF_DIR . $iface, 0755 );
    }
    my $pluginDir = CONF_DIR . $iface . '/' . PLUGIN_CONF_SUBDIR;
    unless ( -d $pluginDir ) {
        mkdir ( $pluginDir, 0755 );
    }
    return CONF_DIR . "$iface/";
}

# Method: TftpdRootDir
#
#      Get the default Tftpd root directory to store the firmwares
#      uploaded by our users
#
# Returns:
#
#      String - the tftpd root directory path
#
sub TftpdRootDir
{
    my ($class) = @_;

    # Create directory unless it already exists
    unless ( -d TFTPD_CONF_DIR ) {
        mkdir ( TFTPD_CONF_DIR, 0755 );
    }
    return TFTPD_CONF_DIR;
}

# Method: PluginConfDir
#
#      Get the DHCP plugin configuration directory where to store the user
#      defined configuration files
#
# Parameters:
#
#      iface - String the interface which the user configuration file
#      is within
#
# Returns:
#
#      String - the configuration path
#
sub PluginConfDir
{
    my ($class, $iface) = @_;

    my $pluginDir = CONF_DIR . $iface . '/' . PLUGIN_CONF_SUBDIR;
    unless ( -d $pluginDir ) {
        mkdir ( $pluginDir, 0755 );
    }
    return $pluginDir;
}

# Method:  userConfDir
#
#  Returns:
#  path to the user configuration dir
sub userConfDir
{
  return CONF_DIR;
}

# Method: IncludeDir
#
#    Path to the directory to include custom configuration
#
# Returns:
#
#    String - the path to the directory
#
sub IncludeDir
{
    return INCLUDE_DIR;
}

# Group: Network observer implementations

# Method: ifaceMethodChanged
#
# Implements:
#
#    <EBox::NetworkObserver::ifaceMethodChanged>
#
# Returns:
#
#     true - if the old method is 'static' and there are configured
#     ranges or fixed addresses attached to this interface
#     false - otherwise
#
sub ifaceMethodChanged # (iface, old_method, new_method)
{
    my ($self, $iface, $old_method, $new_method) = @_;

    # Mark managers as changed every time we attempt to change the
    # iface method from/to static
    if ($old_method eq 'static' or $new_method eq 'static') {
        my $manager = EBox::Model::ModelManager->instance();
        $manager->markAsChanged();
        $manager = EBox::Model::CompositeManager->Instance();
        $manager->markAsChanged();
    }

    if ($old_method eq 'static'
          and $new_method ne 'static') {
        my $rangeModel = $self->_getModel('rangeModel', $iface);
        if ( defined ( $rangeModel )) {
            return 1 if ( $rangeModel->size() > 0);
        }
        my $fixedAddrModel = $self->_getModel('fixedAddrModel', $iface);
        if ( defined ( $fixedAddrModel )) {
            return 1 if ( $fixedAddrModel->size() > 0);
        }
    }
    return 0;
}

# Method: vifaceAdded
#
#
# Implements:
#
#   <EBox::NetworkObserver::vifaceAdded>
#
# Exceptions:
#
#  <EBox::Exceptions::External> - thrown *if*:
#
#   - New Virtual interface IP overlaps any configured range
#   - New Virtual interface IP is a fixed IP address
#
sub vifaceAdded # (iface, viface, address, netmask)
{
    my ( $self, $iface, $viface, $address, $netmask) = @_;

    my $net = EBox::Global->modInstance('network');
    my $ip = new Net::IP($address);

    my $manager = EBox::Model::ModelManager->instance();

    my @rangeModels = @{$manager->model('/dhcp/RangeTable/*')};
    # Check that the new IP for the virtual interface isn't in any range
    foreach my $rangeModel (@rangeModels) {
        foreach my $id (@{$rangeModel->ids()}) {
            my $rangeRow = $rangeModel->row($id);
            my $from = $rangeRow->valueByName('from');
            my $to   = $rangeRow->valueByName('to');
            my $range = new Net::IP($from . ' - ' . $to);
            unless ( $ip->overlaps($range) == $IP_NO_OVERLAP ) {
                throw EBox::Exceptions::External(
                __x('The IP address of the virtual interface '
                        . 'you are trying to add is already used by the '
                        . "DHCP range '{range}' in the interface "
                        . "'{iface}'. Please, remove it before trying "
                        . 'to add a virtual interface using it.',
                        range => $rangeRow->valueByName('name'),
                        iface => $rangeModel->index()));
            }
        }

        my @fixedAddrModels = @{$manager->model('/dhcp/FixedAddressTable/*')};
        # Check the new IP for the virtual interface is not a fixed address
        foreach my $model (@fixedAddrModels) {
            next unless ($model->size() > 0);
            my $iface = $model->index();
            foreach my $fixedAddr ( @{$self->fixedAddresses($iface, 0)} ) {
                my $fixedIP = new Net::IP($fixedAddr->{'ip'});
                unless ( $ip->overlaps($fixedIP) == $IP_NO_OVERLAP ) {
                    throw EBox::Exceptions::External(
                           __x('The IP address of the virtual interface '
                               . 'you are trying to add is already used by a '
                               . "DHCP fixed address from object member "
                               . "'{fixed}' in the "
                               . "interface '{iface}'. Please, remove it "
                               . 'before trying to add a virtual interface '
                               . 'using it.',
                               fixed => $fixedAddr->{'name'},
                               iface => $iface));

                }
            }
        }
    }
    # Mark managers as changed
    $manager->markAsChanged();
    my $compManager = EBox::Model::CompositeManager->Instance();
    $compManager->markAsChanged();
}

# Method:  vifaceDelete
#
# Implements:
#
#    <EBox::NetworkObserver::vifaceDelete>
#
# Returns:
#
#    true - if there are any configured range or fixed address for
#    this interface
#    false - otherwise
#
sub vifaceDelete # (iface, viface)
{
    my ($self, $iface, $viface) = @_;

    my $manager = EBox::Model::ModelManager->instance();

    foreach my $modelName (qw(RangeTable FixedAddressTable Options)) {
        my $model = $manager->model("/dhcp/$modelName/$iface:$viface");
        my $nr = $model->size();
        if ( $nr > 0 ) {
            return 1;
        }
    }

    return 0;
}

# Method: staticIfaceAddressChanged
#
#       Return true *unless*:
#
#       - all ranges are still in the network
#       - new IP is not in any range
#       - all fixed addresses are still in the network
#       - new IP is not any fixed IP address
#
# Implements:
#
#       <EBox::NetworkObserver::staticIfaceAddressChanged>
#
sub staticIfaceAddressChanged # (iface, old_addr, old_mask, new_addr, new_mask)
{
    my ( $self, $iface, $old_addr, $old_mask, $new_addr, $new_mask) = @_;
#   my $nr = @{$self->ranges($iface)};
#   my $nf = @{$self->fixedAddresses($iface)};
#   if(($nr == 0) and ($nf == 0)){
#       return 0;
#   }

    my $ip = new Net::IP($new_addr);

    my $network = ip_network($new_addr, $new_mask);
    my $bits = bits_from_mask($new_mask);
    my $netIP = new Net::IP("$network/$bits");

        # Check ranges
        my $manager = EBox::Model::ModelManager->instance();
        my $rangeModel = $manager->model("/dhcp/RangeTable/$iface");
        foreach my $id (@{$rangeModel->ids()}) {
            my $rangeRow = $rangeModel->row($id);
            my $range = new Net::IP($rangeRow->valueByName('from')
                                    . ' - ' .
                                    $rangeRow->valueByName('to'));
            # Check the range is still in the network
            unless ($range->overlaps($netIP) == $IP_A_IN_B_OVERLAP){
                return 1;
            }
            # Check the new IP isn't in any range
            unless($ip->overlaps($range) == $IP_NO_OVERLAP ){
                return 1;
            }
        }
        my $fixedAddrs = $self->fixedAddresses($iface, 0);
        foreach my $fixedAddr (@{$fixedAddrs}) {
            my $fixedIP = new Net::IP( $fixedAddr->{'ip'} );
            # Check the fixed address is still in the network
            unless($fixedIP->overlaps($netIP) == $IP_A_IN_B_OVERLAP){
                return 1;
            }
            # Check the new IP isn't in any fixed address
            unless( $ip->overlaps($fixedIP) == $IP_NO_OVERLAP){
                return 1;
            }
        }

    return 0;
}

# Function: freeIface
#
#    Delete every single row from the models attached to this
#    interface
#
# Implements:
#
#    <EBox::NetworkObserver::freeIface>
#
#
sub freeIface #( self, iface )
{
    my ( $self, $iface ) = @_;
#   $self->delete_dir("$iface");
        $self->_removeDataModelsAttached($iface);

        my $manager = EBox::Model::ModelManager->instance();
        $manager->markAsChanged();
        $manager = EBox::Model::CompositeManager->Instance();
        $manager->markAsChanged();

    my $net = EBox::Global->modInstance('network');
    if ($net->ifaceMethod($iface) eq 'static') {
      $self->_checkStaticIfaces(-1);
    }
}

# Method: freeViface
#
#    Delete every single row from the models attached to this virtual
#    interface
#
# Implements:
#
#    <EBox::NetworkObserver::freeViface>
#
#
sub freeViface #( self, iface, viface )
{
    my ( $self, $iface, $viface ) = @_;
#   $self->delete_dir("$iface:$viface");
        $self->_removeDataModelsAttached("$iface:$viface");

        my $manager = EBox::Model::ModelManager->instance();
        $manager->markAsChanged();
        $manager = EBox::Model::CompositeManager->Instance();
        $manager->markAsChanged();

#   my $net = EBox::Global->modInstance('network');
#   if ($net->ifaceMethod($viface) eq 'static') {
      $self->_checkStaticIfaces(-1);
#   }
}

# Group: Private methods


# Impelment LogHelper interface
sub tableInfo
{
    my ($self) = @_;

    my $titles = { 'timestamp' => __('Date'),
        'interface' => __('Interface'),
        'mac' => __('MAC address'),
        'ip' => __('IP'),
        'event' => __('Event')
    };
    my @order = ('timestamp', 'ip', 'mac', 'interface', 'event');
    my $events = {'leased' => __('Leased'), 'released' => __('Released') };

    return [{
        'name' => __('DHCP'),
        'tablename' => 'leases',
        'titles' => $titles,
        'order' => \@order,
        'timecol' => 'timestamp',
        'filter' => ['interface', 'mac', 'ip'],
        'types' => { 'ip' => 'IPAddr', 'mac' => 'MACAddr' },
        'events' => $events,
        'eventcol' => 'event',
    }];
}

sub logHelper
{
    my $self = shift;

    return (new EBox::DHCPLogHelper);
}

sub _leaseIDFromIP
{
    my ($ip) = @_;
    my $id = 'a';
    #force every byte to use 3 digits to make sorting trivial
    my @bytes = split('\.', $ip);
    for my $byte (@bytes) {
        $id .= sprintf("%03d", $byte);
    }
    return $id;
}

sub _dhcpLeases
{
    my ($self) = @_;

    my @stats = stat LEASEFILE;
    @stats or
           return {};
    my $mtime = $stats[9];
    my $refresh = 0;
    if (defined $self->{leases} and (defined $self->{leasesMTime})) {
        $refresh = $mtime ne $self->{leasesMTime};
    } else {
        $refresh = 1;
    }

    if ($refresh) {
        my $leases = Text::DHCPLeases->new(file => LEASEFILE);

        $self->{'leases'} = {};
        foreach my $lease ($leases->get_objects()) {
            my $id = _leaseIDFromIP($lease->ip_address());
            $self->{'leases'}->{$id} = $lease;
        }
        $self->{leasesMTime} = $mtime;
    }
    return $self->{'leases'};
}

sub _leaseFromIP
{
    my ($self, $ip) = @_;

    my $leases = $self->_dhcpLeases();
    my $id = _leaseIDFromIP($ip);
    return $leases->{$id};
}

sub dhcpLeasesWidget
{
    my ($self, $widget) = @_;
    my $section = new EBox::Dashboard::Section('dhcpleases');
    $widget->add($section);
    my $titles = [__('IP address'),__('MAC address'), __('Host name')];

    my $leases = $self->_dhcpLeases();

    my $ids = [];
    my $rows = {};
    foreach my $id (sort keys (%{$leases})) {
        my $lease = $leases->{$id};
        if($lease->binding_state() eq 'active') {
            my $hostname = $lease->client_hostname();
            $hostname =~ s/"//g;
            push(@{$ids}, $id);
            $rows->{$id} = [$lease->ip_address(),$lease->mac_address(),
                            $hostname];
        }
    }

    $section->add(new EBox::Dashboard::List(undef, $titles, $ids, $rows));
}

### Method: widgets
#
#   Overrides <EBox::Module::Base::widgets>
#
sub widgets
{
    return {
        'dhcpleases' => {
            'title' => __("DHCP leases"),
            'widget' => \&dhcpLeasesWidget,
            'order' => 5,
            'default' => 1
        }
    };
}

# Group: Private methods

# Method: _setDHCPConf
#
#     Updates the dhcpd.conf file
#
sub _setDHCPConf
{
    my ($self) = @_;

    # Write general configuration
    my $net = EBox::Global->modInstance('network');
    my $staticRoutes_r =  $self->staticRoutes();

    my $ifacesInfo = $self->_ifacesInfo($staticRoutes_r);
    my @params = ();
    push @params, ('dnsone' => $net->nameserverOne());
    push @params, ('dnstwo' => $net->nameserverTwo());
    push @params, ('thinClientOption' =>
                   $self->_areThereThinClientOptions($ifacesInfo));
    push @params, ('ifaces' => $ifacesInfo);
    push @params, ('real_ifaces' => $self->_realIfaces());
    my $dynamicDNSEnabled = $self->_dynamicDNSEnabled($ifacesInfo);
    if ( $dynamicDNSEnabled ) {
        push @params, ('dynamicDNSEnabled' => $dynamicDNSEnabled);
        push @params, ('keysFile' => $self->_keysFile());
    }
    push(@params, ('pidFile' => PIDFILE));

    $self->writeConfFile(DHCPCONFFILE, "dhcp/dhcpd.conf.mas", \@params);

}

# Method: _setTFTPDConf
#
#     Set the proper files on the TFTPD root dir
#
sub _setTFTPDConf
{
}

# Method: _ifacesInfo
#
#      Return a well structure to configure dhcp3-server using the
#      data installed in the module as well as the static routes
#      provided by <EBox::DHCP::StaticRouteProvider> modules
#
# Parameters:
#
#      staticRouters - hash ref containing those static routes to add
#      to a network which acts as key and the routes as value.
#
# Returns:
#
#      hash ref - an structure storing the required information for
#      dhcpd configuration
#
sub _ifacesInfo
{
    my ($self, $staticRoutes_r) = @_;

    my $roGlobal = EBox::Global->getInstance('readonly');
    my $net = $roGlobal->modInstance('network');
    my $ifaces = $net->allIfaces();

    my %iflist;
    foreach my $iface (@{$ifaces}) {
        if ($net->ifaceMethod($iface) eq 'static') {
            my $address = $net->ifaceAddress($iface);
            my $netmask = $net->ifaceNetmask($iface);
            my $network = ip_network($address, $netmask);

            $iflist{$iface}->{'net'} = $network;
            $iflist{$iface}->{'address'} = $address;
            $iflist{$iface}->{'netmask'} = $netmask;
            $iflist{$iface}->{'ranges'} = $self->ranges($iface);
            $iflist{$iface}->{'fixed'} = $self->fixedAddresses($iface, 'readonly');

            # look if we have static routes for this network
            my $netWithMask = EBox::NetWrappers::to_network_with_mask($network, $netmask);
            if (exists $staticRoutes_r->{$netWithMask}) {
                $iflist{$iface}->{'staticRoutes'} =
                    $staticRoutes_r->{$netWithMask};
            }

            my $gateway = $self->defaultGateway($iface);
            if (defined ($gateway)) {
                if ($gateway) {
                    $iflist{$iface}->{'gateway'} = $gateway;
                }
            } else {
                $iflist{$iface}->{'gateway'} = $address;
            }
            my $search = $self->searchDomain($iface);
            $iflist{$iface}->{'search'} = $search;
            my $nameserver1 = $self->nameserver($iface,1);
            if (defined($nameserver1) and $nameserver1 ne "") {
                $iflist{$iface}->{'nameserver1'} = $nameserver1;
            }
            my $nameserver2 = $self->nameserver($iface,2);
            if (defined($nameserver2) and $nameserver2 ne "") {
                $iflist{$iface}->{'nameserver2'} = $nameserver2;
            }
            # NTP option
            my $ntpServer = $self->ntpServer($iface);
            if ( defined($ntpServer) and $ntpServer ne "") {
                $iflist{$iface}->{'ntpServer'} = $ntpServer;
            }
            # WINS/Netbios server option
            my $winsServer = $self->winsServer($iface);
            if ( defined($winsServer) and $winsServer ne "") {
                $iflist{$iface}->{'winsServer'} = $winsServer;
            }
            # Leased times
            my $defaultLeasedTime = $self->_leasedTime('default', $iface);
            if (defined($defaultLeasedTime)) {
                $iflist{$iface}->{'defaultLeasedTime'} = $defaultLeasedTime;
            }
            my $maxLeasedTime = $self->_leasedTime('max', $iface);
            if (defined($maxLeasedTime)) {
                $iflist{$iface}->{'maxLeasedTime'} = $maxLeasedTime;
            }

            # Dynamic DNS options
            my $dynamicDomain = $self->_dynamicDNS('dynamic', $iface);
            if (defined($dynamicDomain)) {
                $iflist{$iface}->{'dynamicDomain'} = $dynamicDomain;
                $iflist{$iface}->{'staticDomain'}  = $self->_dynamicDNS('static', $iface);
                $iflist{$iface}->{'reverseZones'}  = $self->_reverseZones($iface);
            }
        }
    }

    return \%iflist;
}

# Method: _realIfaces
#
#    Get those interfaces which are real static ones containing the
#    virtual interfaces names which contain the real static interface
#
# Returns:
#
#    hash ref - containing interface name as key and an array ref
#    containing the virtual interface names as value
#
sub _realIfaces
{
    my ($self) = @_;
    my $net = EBox::Global->modInstance('network');

    my $real_ifaces = $net->ifaces();
    my %realifs;
    foreach my $iface (@{$real_ifaces}) {
        if ($net->ifaceMethod($iface) eq 'static') {
            $realifs{$iface} = $net->vifaceNames($iface);
        }

    }

    return \%realifs;
}

# Method: _areThereThinClientOptions
#
#    Check if there are thin client options in order to allow DHCP
#    server acting as a boot server by setting these options on the
#    configuration file
#
# Parameters:
#
#    ifacesInfo - hash ref every static interface is the key and the
#    value contains every single parameter required to be written on
#    the configuration file
#
# Returns:
#
#    Boolean - true if there are thin client options in at least one
#    iface, false otherwise
#
sub _areThereThinClientOptions
{
    my ($self, $ifacesInfo) = @_;

    foreach my $ifaceInfo (values %{$ifacesInfo}) {
        foreach my $range (@{$ifaceInfo->{ranges}}) {
            if ( values %{$range->{options}} > 0 ) {
                return 1;
            }
        }
        foreach my $objFixed (values %{$ifaceInfo->{fixed}}) {
            if ( values %{$objFixed->{options}} > 0 ) {
                return 1;
            }
        }
    }
    return 0;
}

# Method: _leasedTime
#
#    Get the leased time (default or maximum) in seconds if any
#
sub _leasedTime # (which, iface)
{
    my ($self, $which, $iface) = @_;

    my $advOptionsModel = $self->_getModel('leaseTimesModel', $iface);

    my $fieldName = $which . '_leased_time';
    return $advOptionsModel->row()->valueByName($fieldName);
}

# Method: _thinClientOptions
#
#    Get the thin client option (nextServer or filename) if defined
#
sub _thinClientOptions # (iface, element)
{
    my ($self, $iface, $element) = @_;

    my $thinClientModel = $self->_getModel('thinClientModel', $iface);

    my $ret = {};
    my $row = $thinClientModel->findValue(hosts => $element);
    if ( defined($row) ) {
        $ret->{nextServer} = $thinClientModel->nextServer($row->id());
        $ret->{filename}   = $row->valueByName('remoteFilename');
    }
    return $ret;

}

# Method: _dynamicDNS
#
#    Get the domains to be updated by DHCP server (dynamic or statics)
#
# Returns:
#
#    undef - if the dynamic DNS feature is not enabled
#
sub _dynamicDNS # (which, iface)
{
    my ($self, $which, $iface) = @_;

    return undef unless (EBox::Global->modExists('dns'));

    my $dynamicDNSModel = $self->_getModel('dynamicDNSModel', $iface);

    my $dynamicOptionsRow = $dynamicDNSModel->row();
    if ($dynamicOptionsRow->valueByName('enabled')) {
        if ($which eq 'dynamic') {
            return $dynamicOptionsRow->printableValueByName('dynamic_domain');
        } elsif ($which eq 'static') {
            my $staticOption = $dynamicOptionsRow->elementByName('static_domain');
            if ($staticOption->selectedType() eq 'same') {
                return $dynamicOptionsRow->printableValueByName('dynamic_domain');
            } elsif ($staticOption->selectedType() eq 'custom') {
                return $dynamicOptionsRow->printableValueByName('static_domain');
            }
        }
    }
    return undef;
}

# Return the reverse zones for the given interface
sub _reverseZones
{
    my ($self, $iface) = @_;

    my $initRange = $self->initRange($iface);
    $initRange =~ s/1$/0/; # To make a network interface
    my $endRange  = $self->endRange($iface);

    my @revZones;
    my $ip = new Net::IP("$initRange - $endRange");
    do {
        my $rev = Net::IP->new($ip->ip())->reverse_ip();
        if ( defined($rev) ) {
            # If the response is 10.in-addr.arpa, transform it to 0.0.10.in-addr.arpa
            my @subdomains = split(/\./, $rev);
            if (@subdomains < 5) {
                $rev = '0.' . $rev for (1 .. (5 - @subdomains));
            }
            push(@revZones, $rev);
        }
    } while ( $ip += 256 );

    return \@revZones;
}

# Return the key file to update DNS
sub _keysFile
{
    my ($self) = @_;

    my $gl = EBox::Global->getInstance();
    if ( $gl->modExists('dns') ) {
        my $dnsMod = EBox::Global->modInstance('dns');
        if ( $dnsMod->configured() ) {
            return $dnsMod->keysFile();
        }
    }
    return '';
}

# Return if the dynamic DNS feature is enabled for this DHCP server or
# not given the iface list info
sub _dynamicDNSEnabled # (ifacesInfo)
{
    my ($self, $ifacesInfo) = @_;

    return 0 unless ( EBox::Global->modExists('dns') );

    if ( defined($ifacesInfo) ) {
        my $nDynamicOptionsOn = grep { defined($ifacesInfo->{$_}->{'dynamicDomain'}) } keys %{$ifacesInfo};
        return ($nDynamicOptionsOn > 0);
    } else {
        my $net = EBox::Global->modInstance('network');
        my $ifaces = $net->allIfaces();
        foreach my $iface (@{$ifaces}) {
            if ( $net->ifaceMethod($iface) eq 'static' ) {
                my $mod = $self->_getModel('dynamicDNSModel', $iface);
                if ( $mod->row()->valueByName('enabled') ) {
                    return 1;
                }
            }
        }
        return 0;
    }
}

# Configure the firewall rules to add
# XXX maybe this is dead code?
sub _configureFirewall
{
    my ($self) = @_;

    my $fw = EBox::Global->modInstance('firewall');
    try {
        $fw->removeOutputRule('udp', 67);
        $fw->removeOutputRule('udp', 68);
        $fw->removeOutputRule('tcp', 67);
        $fw->removeOutputRule('tcp', 68);
    } catch EBox::Exceptions::Internal with { };

    if ($self->isEnabled()) {
        $fw->addOutputRule('tcp', 67);
        $fw->addOutputRule('tcp', 68);
        $fw->addOutputRule('udp', 67);
        $fw->addOutputRule('udp', 68);
    }
}

# Returns those model instances attached to the given interface
sub _removeDataModelsAttached
{
    my ($self, $iface) = @_;

    # RangeTable/Options/FixedAddressTable
    foreach my $modelName (qw(leaseTimesModel thinClientModel optionsModel rangeModel fixedAddrModel)) {
        my $model = $self->_getModel($modelName, $iface);
        if ( defined ( $model )) {
            $model->removeAll(1);
        }
        $self->{$modelName}->{$iface} = undef;
    }
}

# Model getter, check if there are any model with the given
# description, if not, calling models again to create. Done until
# model provider works correctly with model method overriding models
# instead of modelClasses
sub _getModel
{
    my ($self, $modelName, $iface) = @_;

    unless ( exists $self->{$modelName}->{$iface} ) {
        $self->models();
    }
    return $self->{$modelName}->{$iface};

}

# Check there are enough static interfaces to have DHCP service enabled
sub _checkStaticIfaces
{
    my ($self, $adjustNumber) = @_;
    defined $adjustNumber or $adjustNumber = 0;

    my $nStaticIfaces = $self->_nStaticIfaces() + $adjustNumber;
    if ($nStaticIfaces == 0) {
        if ($self->isEnabled()) {
            $self->enableService(0);
            EBox::info('DHCP service was deactivated because there was not any static interface left');
        }
    }
}

# Return the current number of static interfaces
sub _nStaticIfaces
{
    my ($self) = @_;

    my $net = EBox::Global->modInstance('network');
    my $ifaces = $net->allIfaces();
    my $staticIfaces = grep  { $net->ifaceMethod($_) eq 'static' } @{$ifaces};

    return $staticIfaces;
}

# Check if the given member is allowed to be a fixed address in the
# given interface
# It should match the following criteria:
#  * The member name must be a valid hostname
#    - If not, then the member name is become to a valid one
#  * Be a valid host IP address
#  * Have a valid MAC address
#  * The IP address must be in range available for the given interface
#  * It must be not used by in the range for the given interface
#  * It must be not the interface address
#  * The member name must be unique in the object realm
#  * The MAC address must be unique for subnet
#
sub _allowedMemberInFixedAddress
{
    my ($self, $iface, $member, $objId, $readOnly) = @_;

    unless (EBox::Validate::checkDomainName($member->{'name'})) {
        $member->{'name'} = lc($member->{'name'});
        $member->{'name'} =~ s/[^a-z0-9\-]/-/g;
    }

    if ($member->{mask} != 32 or (not defined($member->{macaddr}))) {
        return 0;
    }

    my $memberIP = new Net::IP($member->{ip});
    my $gl       = EBox::Global->getInstance($readOnly);
    my $net      = $gl->modInstance('network');
    my $objs     = $gl->modInstance('objects');
    my $netIP    = new Net::IP($self->initRange($iface)
                               . '-' . $self->endRange($iface));

    # Check if the IP address is within the network
    unless ($memberIP->overlaps($netIP) == $IP_A_IN_B_OVERLAP) {
        # The IP address from the member is not in the network
        EBox::debug('IP address ' . $memberIP->print() . ' is not in the '
                    . 'network ' . $netIP->print());
        return 0;
    }

    # Check the IP address is not the interface address
    my $ifaceIP = new Net::IP($net->ifaceAddress($iface));
    unless ( $memberIP->overlaps($ifaceIP) == $IP_NO_OVERLAP ) {
        # The IP address is the interface IP address
        EBox::debug('IP address ' . $memberIP->print() . " is the $iface interface address");
        return 0;
    }

    # Check the member IP address is not within any given range by
    # RangeTable model
    my $rangeModel = $self->_getModel('rangeModel', $iface);
    foreach my $id (@{$rangeModel->ids()}) {
        my $rangeRow = $rangeModel->row($id);
        my $from     = $rangeRow->valueByName('from');
        my $to       = $rangeRow->valueByName('to');
        my $range    = new Net::IP( $from . '-' . $to);
        unless ( $memberIP->overlaps($range) == $IP_NO_OVERLAP ) {
            # The IP address is in the range
            EBox::debug('IP address ' . $memberIP->print() . ' is in range '
                        . $rangeRow->valueByName('name') . ": $from-$to");
            return 0;
        }
    }

    # Check the given member is unique within the object realm
    my @fixedAddressTables = @{EBox::Model::ModelManager->instance()->model('/dhcp/FixedAddressTable/*')};
    # Delete the self model
    @fixedAddressTables = grep { $_->index() ne $iface } @fixedAddressTables;

    foreach my $model (@fixedAddressTables) {
        my $ids = $model->ids();
        foreach my $id (@{$ids}) {
            my $row = $model->row($id);
            my $otherObjId = $row->valueByName('object');
            my $mbs = $objs->objectMembers($otherObjId);
            next if ( $otherObjId eq $objId); # If they are the same object

            # Check for the same member name in other object
            my @matches = grep { $_->{name} eq $member->{name} } @{$mbs};
            foreach my $match (@matches) {
                next unless ( $match->{mask} == 32 and defined($match->{macaddr}));
                EBox::warn('IP address ' . $memberIP->print() . ' not added '
                           . 'because there are two members with the same name '
                           . $member->{name} . ' in other fixed address table');
                return 0;
            }
        }
    }

    # Check for the same MAC address
    my $fixedAddrModel = $self->_getModel('fixedAddrModel', $iface);
    my $ids = $fixedAddrModel->ids();
    foreach my $id ( @{$ids} ) {
        my $row = $fixedAddrModel->row($id);
        my $otherObjId = $row->valueByName('object');
        next if ( $otherObjId eq $objId ); # Check done by unique MAC address property
        my $mbs = $objs->objectMembers($otherObjId);
        my @matches = grep {
            defined($_->{macaddr})
            and ($_->{macaddr} eq $member->{macaddr})
            and ($_->{name} ne $member->{name})
        } @{$mbs};
        if ( @matches > 0 ) {
            EBox::warn('MAC address ' . $member->{macaddr} . ' is being '
                       . 'used by ' . $member->{name} . ' and, at least, '
                       . $matches[0]->{name});
            return 0;
        }
    }

    return 1;
}

# Method: gatewayDelete
#
#  Overrides:
#    EBox::NetworkObserver::gatewayDelete
sub gatewayDelete
{
    my ($self, $gwName) = @_;

    my $global = EBox::Global->getInstance($self->{ro});
    my $network = $global->modInstance('network');
    foreach my $iface (@{$network->allIfaces()}) {
        next unless ($network->ifaceMethod($iface) eq 'static');
        my $options = $self->_getModel('optionsModel', $iface);
        my $optionsGwName = $options->gatewayName();
        if ($gwName eq $optionsGwName) {
            return 1;
        }
    }

    return 0;
}

1;
