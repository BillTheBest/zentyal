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

package EBox::DNS;

use strict;
use warnings;

use base qw(EBox::Module::Service
            EBox::Model::ModelProvider
            EBox::Model::CompositeProvider
            );

use EBox::Objects;
use EBox::Gettext;
use EBox::Config;
use EBox::Exceptions::Sudo::Command;
use EBox::Service;
use EBox::Menu::Item;
use EBox::Sudo;
use EBox::Validate qw( :all );
use EBox::DNS::Model::DomainTable;
use EBox::DNS::Model::HostnameTable;
use EBox::DNS::Model::AliasTable;
use EBox::Model::ModelManager;
use EBox::Sudo;

use Error qw(:try);
use File::Temp;
use Fcntl qw(:seek);
use IO::Socket::INET;
use Net::IP;
use Perl6::Junction qw(any);
use Tie::File;

# FIXME: extract this from somewhere to support multi-distro?
#use constant BIND9CONFDIR => "@BIND9CONFDIR@";
#use constant BIND9CONFFILE => "@BIND9CONF@";
#use constant BIND9CONFOPTIONSFILE => "@BIND9CONFOPTIONS@";
#use constant BIND9CONFLOCALFILE => "@BIND9CONFLOCAL@";
#use constant BIND9INIT     => "@BIND9_INIT@";
#use constant BIND9_UPDATE_ZONES => "@BIND9_UPDATE_ZONES@";

use constant BIND9CONFDIR => "/etc/bind";
use constant BIND9CONFFILE => "/etc/bind/named.conf";
use constant BIND9CONFOPTIONSFILE => "/etc/bind/named.conf.options";
use constant BIND9CONFLOCALFILE => "/etc/bind/named.conf.local";
use constant BIND9INIT     => "/etc/init.d/bind9";
use constant BIND9_UPDATE_ZONES => "/var/lib/bind";

use constant PIDFILE       => "/var/run/bind/run/named.pid";
use constant NAMESERVER_HOST => 'ns';
use constant KEYSFILE => BIND9CONFDIR . '/keys';

use constant DNS_CONF_FILE => EBox::Config::etc() . 'dns.conf';
use constant DNS_INTNETS => 'intnets';
use constant NS_UPDATE_CMD => 'nsupdate';
use constant DELETED_RR_KEY => 'deleted_rr';
use constant DNS_PORT => 53;

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'dns',
                                      printableName => 'DNS',
                                      @_);

    bless($self, $class);
    return $self;
}

# Method: modelClasses
#
# Overrides:
#
#       <EBox::ModelProvider::modelClasses>
#
sub modelClasses
{
    return [
            {
             class      => 'EBox::DNS::Model::DomainTable',
             parameters => [
                            directory => 'domainTable',
                           ],
            },
            {
             class      => 'EBox::DNS::Model::HostnameTable',
             parameters => [
                            directory => 'hostnameTable',
                           ],
            },
            {
             class      => 'EBox::DNS::Model::AliasTable',
             parameters => [
                            directory => 'aliasTable',
                           ],
            },
            'EBox::DNS::Model::MailExchanger',
            'EBox::DNS::Model::NameServer',
            'EBox::DNS::Model::Text',
            'EBox::DNS::Model::Services',
            'EBox::DNS::Model::Forwarder',
            'EBox::DNS::Model::Settings',
           ];
}

# Method: compositeClasses
#
# Overrides:
#
#       <EBox::CompositeProvider::compositeClasses>
#
sub compositeClasses
{
    return [ 'EBox::DNS::Composite::Global' ];
}

# Method: _exposedMethods
#
#
# Overrides:
#
#      <EBox::Model::ModelProvider::_exposedMethods>
#
# Returns:
#
#      hash ref - the list of the exposes method in a hash ref every
#      component
#
sub _exposedMethods
  {

      my %exposedMethods =
        (
         'addDomain1' => { action   => 'add',
                          path     => [ 'DomainTable' ],
                        },
         'removeDomain' => { action  => 'del',
                             path    => [ 'DomainTable' ],
                             indexes => [ 'domain' ],
                           },
         'addHostName' => { action  => 'add',
                            path    => [ 'DomainTable', 'hostnames' ],
                            indexes => [ 'domain' ],
                          },
         'setIP'       => { action   => 'set',
                            path     => [ 'DomainTable', 'hostnames' ],
                            indexes  => [ 'domain', 'hostname' ],
                            selector => [ 'ipaddr' ]
                          },
         'changeName'  => { action   => 'set',
                            path     => [ 'DomainTable', 'hostnames' ],
                            indexes  => [ 'domain', 'hostname' ],
                            selector => [ 'hostname' ]
                          },
         'getHostNameByName' => { action   => 'get',
                                  path     => [ 'DomainTable', 'hostnames' ],
                                  indexes  => [ 'domain', 'hostname' ],
                                },
         'getHostNameByIP' => { action  => 'get',
                                path    => [ 'DomainTable', 'hostnames' ],
                                indexes => [ 'domain', 'ipaddr' ],
                              },
         'removeHostName' => { action => 'del',
                               path   => [ 'DomainTable', 'hostnames' ],
                               indexes => [ 'domain', 'hostname' ],
                             },
         'addMailExchanger' => { action  => 'add',
                                 path    => [ 'DomainTable', 'mailExchangers' ],
                                 indexes => [ 'domain' ],
                               },
         # Both following two methods are only working with custom MX records
         'changeMXPreference' => { action  => 'set',
                                   path    => [ 'DomainTable', 'mailExchangers' ],
                                   indexes => [ 'domain', 'hostName' ],
                                   selector => [ 'preference' ]
                                 },
         'removeMailExchanger' => { action  => 'del',
                                    path    => [ 'DomainTable', 'mailExchangers' ],
                                    indexes => [ 'domain', 'hostName' ],
                                  },
         );

      return \%exposedMethods;

  }

# Method: addDomain
#
#  Add new domain to table model
#
# Parameters:
#
#       Check <EBox::DNS::Model::DomainTable> for details
#
sub addDomain
{
    my ($self, $domainData) = @_;

    my $domainModel = EBox::Model::ModelManager->instance()->model('DomainTable');

    $domainModel->addDomain($domainData);
}

# Method: domains
#  returns an array with all domain names
#
# Returns:
#
#  Array ref - containing hash refs with the following elements:
#
#    name    - String the domain's name
#    ipaddr  - String the domain's ip address
#    dynamic - Boolean indicating if the domain is dynamically updated
#
sub domains
{
    my $self = shift;
    my @array;

    my $model = EBox::Model::ModelManager->instance()->model('DomainTable');

    foreach my $id (@{$model->ids()})
    {
        my $row = $model->row($id);
        my $domaindata;

        $domaindata->{'name'} = $row->valueByName('domain');
        $domaindata->{'ipaddr'} = $row->valueByName('ipaddr');
        $domaindata->{'dynamic'} = $row->valueByName('dynamic');

        push(@array, $domaindata);
    }

    return \@array;
}


# Method: getHostnames
#
#       Given a domain name, it returns an array ref of hostnames that
#       it contains.
#
# Parameters:
#
#       domain - String the domain's name
#
# Returns:
#
#       array ref - containing the same structure as
#       <EBox::DNS::hostnames> returns
#
sub getHostnames
{

    my ($self, $domain) = @_;

    my $domainRow = $self->model('DomainTable')->findRow(domain => $domain);
    unless ( defined($domainRow) ) {
        throw EBox::Exceptions::DataNotFound(data  => __('domain'),
                                             value => $domain);
    }

    return $self->_hostnames($domainRow->subModel('hostnames'));

}

# Method: aliases
#  returns an array with all alias structure of a hostname
#
# Parameters:
#   model to iterate over
#
# Returns:
#  array ref with this structure data:
#
#  'name': alias name
#
sub aliases
{
    my ($self, $model) = @_;
    my @array;

    foreach my $id (@{$model->ids()})
    {
        my $alias = $model->row($id);
        my $aliasdata;

        $aliasdata->{'name'} = $alias->valueByName('alias');

        push(@array, $aliasdata);
    }

    return \@array;
}

# Method: findAlias
#
#       Return the hostname which the alias refers to given a domain
#
# Parameters:
#
#       domainName - String the domain name
#
#       alias - String the alias name
#
# Returns:
#
#       String - the hostname which the alias refers to
#
# Exceptions:
#
#       <EBox::Exceptions::MissingArgument> - thrown if any compulsory
#       argument is missing
#
#       <EBox::Exceptions::DataNotFound> - thrown if the domain does
#       not exist or the alias does not exist
#
sub findAlias
{
    my ($self, $domainName, $alias) = @_;

    $domainName or throw EBox::Exceptions::MissingArgument('domainName');
    $alias or throw EBox::Exceptions::MissingArgument('alias');

    my $domModel = $self->model('DomainTable');
    $domModel->{cachedVersion} = 0;
    my $id = $domModel->find(domain => $domainName);
    unless ( defined($id)) {
        throw EBox::Exceptions::DataNotFound(data => 'domain',
                                             value => $domainName);
    }
    my $row = $domModel->row($id);
    foreach my $ids (@{$row->subModel('hostnames')->ids()}) {
        my $hostnameRow = $row->subModel('hostnames')->row($id);
        for my $aliasId (@{$hostnameRow->subModel('alias')->ids()}) {
            my $aliasRow = hostnameRow->subModel('alias')->row($aliasId);
            if ($alias eq $aliasRow->valueByName('alias')) {
                return $hostnameRow->valueByName('hostname');
            }
        }
    }

    throw EBox::Exceptions::DataNotFound(data  => 'alias',
                                         value => $alias);
}

# Method: NameserverHost
#
#       Return those host which is the nameserver for every domain. It
#       is a constant
#
# Returns:
#
#       String - the nameserver host name for every eBox defined
#       domain
#
sub NameserverHost
{
    return NAMESERVER_HOST;
}

# Method: updateReversedData
#  updates or adds new item to the array data passed as parameters
#
# Parameters:
#  array ref that holds reversed info data
#  groupIDData structure to update or add
#
sub updateReversedData
{
    my ($self, $reversedData, $groupIPData) = @_;

    # Try to find an previously added groupip item (from other domain)
    my $pos = -1;
    for(my $i = 0; $i < @{$reversedData}; $i++) {
        if ($reversedData->[$i]->{'groupip'} eq $groupIPData->{'groupip'}) {
            my $jpos = -1;
            for (my $j = 0; $j < @{$reversedData->[$i]->{'domain'}}; $j++) {
                if($reversedData->[$i]->{'domain'}->[$j]->{'name'}
                        eq $groupIPData->{'domain'}->{'name'}) {

                    # Ignore the repeated IP address for the same domain
                    my @toAdd = ();
                    foreach my $host (@{$groupIPData->{'domain'}->{'hosts'}}) {
                        my $nMatch = grep { $host->{ip} == $_->{ip} } @{$reversedData->[$i]->{'domain'}->[$j]->{'hosts'}};
                        push(@toAdd, $host) if ($nMatch == 0);
                    }

                    push(@{$reversedData->[$i]->{'domain'}->[$j]->{'hosts'}},
                         @toAdd);
                    $jpos = $j;
                    last;
                }
            }

            if ($jpos < 0) {
                # Remove those whose ip is already in the groupip
                for (my $idxHost = 0; $idxHost < @{$groupIPData->{'domain'}->{'hosts'}}; $idxHost++) {
                    my $host = $groupIPData->{'domain'}->{'hosts'}->[$idxHost];
                    my $anyIPMatch = 0;
                    foreach my $domain (@{$reversedData->[$i]->{'domain'}}) {
                        my $nMatch = grep { $host->{ip} == $_->{ip} } @{$domain->{'hosts'}};
                        $anyIPMatch = ($nMatch > 0);
                        last if ($anyIPMatch);
                    }
                    if ( $anyIPMatch ) {
                        delete $groupIPData->{'domain'}->{'hosts'}->[$idxHost];
                    }
                }
                push(@{$reversedData->[$i]->{'domain'}}, $groupIPData->{'domain'});
                if ( $groupIPData->{'dynamic'} ) {
                    $reversedData->[$i]->{'dynamic'} = $groupIPData->{'dynamic'};
                    push(@{$reversedData->[$i]->{'tsigKeyNames'}},
                         $groupIPData->{'tsigKeyName'});
                }
            }
            $pos = $i;
            last;
        }
    }

    if($pos < 0) {
        my $item = { 'groupip'      => $groupIPData->{'groupip'},
                     'dynamic'      => $groupIPData->{'dynamic'},
                     'tsigKeyNames' => [ $groupIPData->{'tsigKeyName'} ] };
        push(@{$item->{'domain'}}, $groupIPData->{'domain'});
        push(@{$reversedData}, $item);
    }
}

# Method: switchToReverseInfoData
#
#  Return a structure with all necessary data to build reverse db config
#  files.
#
# Parameters:
#
#  array ref - structure returned by <EBox::DNS::_completeDomain>
#
# Returns:
#
#  array ref structure data with:
#
#  'groupip': ip range to define a zone file info
#  'dynamic': boolean indicating if the zone is dynamic
#  'tsigKeyName' : String indicating the name of the TSIG key for
#                  being updated if the domain is dynamic
#  'domain': an array of hosts and domain data:
#  'name': domain name
#  'hosts': an array of hostnames and hostip:
#  'ip': less significant block of an ip address
#  'name': name of the host in the domain
#
sub switchToReverseInfoData
{
    my ($self, $info) = @_;
    my @reversedData;

    foreach my $domainData (@{$info}) {
        my $domain = $domainData->{'name'};

        if ( $domainData->{'dynamic'} ) {
            my $groupIPs = $self->_getRanges($domainData);

            foreach my $groupIP (@{$groupIPs}) {
                my $groupIPData = { 'groupip'     => $groupIP,
                                    'dynamic'     => 1,
                                    'tsigKeyName' => $domain,
                                    'domain'  => { 'name'  => $domain,
                                                   'hosts' => [] }};
                $self->updateReversedData(\@reversedData, $groupIPData);
            }
        }

        # Check for IP address in domain
        if ($domainData->{'ipaddr'}) {
            push(@{$domainData->{'hosts'}},
                 {
                     'name' => '', 'ip' => $domainData->{'ipaddr'} });
        }

        foreach my $hostData (@{$domainData->{'hosts'}}) {
            # Remove wildcard since it is possible to set a reverse domain
            next if ($hostData->{'name'} eq '*');
            my @ipblocks = split(/\./, $hostData->{'ip'});

            #Set group ip bind format (reverse order)
            my $groupip = join(".", $ipblocks[2], $ipblocks[1], $ipblocks[0]);
            my $hostip = $ipblocks[3];

            my $newDomainData;
            $newDomainData->{'name'} = $domain;
            $newDomainData->{'hosts'} = [ { ip => $hostip,
                                            name => $hostData->{'name'} } ];

            my $groupIPData;
            $groupIPData->{'groupip'} = $groupip;
            $groupIPData->{'domain'}  = $newDomainData;
            $groupIPData->{'dynamic'} = 0;

            $self->updateReversedData(\@reversedData, $groupIPData);
        }

    }

    return \@reversedData;
}

# Method: usedFiles
#
# Override EBox::Module::Service::usedFiles
#
sub usedFiles
{
    my ($self) = @_;
    my $files = [{
            'file' => BIND9CONFFILE,
            'module' => 'dns',
            'reason' => __('main bind9 configuration file'),
        },
       {
           'file' => BIND9CONFOPTIONSFILE,
           'module' => 'dns',
           'reason' => __('bind9 options configuration file'),
       },
       {
           'file' => BIND9CONFLOCALFILE ,
           'module' => 'dns',
           'reason' => __('local bind9 configuration file'),
       },
       {
           'file'   => KEYSFILE,
           'module' => 'dns',
           'reason' => __('Keys configuration file'),
       },
    ];


    my @domainIds = @{$self->_domainIds()};

    my @domainData;
    foreach my $domainId (@domainIds)
    {
        my $domdata = $self->_completeDomain($domainId);
        push(@domainData, $domdata);
        my $file = BIND9CONFDIR . "/db." . $domdata->{'name'};
        push (@{$files},
                {
                'file' => $file,
                'module' => 'dns',
                'reason' => __x('configuration file for zone {zone}',
                    zone => $file )
                });

    }

    my $reversedData = $self->switchToReverseInfoData(\@domainData);
    my @inaddrs;
    foreach my $reversedDataItem(@{$reversedData})
    {
        my $file = BIND9CONFDIR . "/db." . $reversedDataItem->{'groupip'};
        push (@{$files},
                {
                'file' => $file,
                'module' => 'dns',
                'reason' =>
                    __x('configuration file for reverse resolution zone {zone}'
                        , zone => $file )
                });

    }

    return $files;
}

# Method: actions
#
# Overrides:
#
#    <EBox::Module::Service::actions>
#
sub actions
{
    return [
        { 'action' => __x('Change the permissions for {dir} to allow writing to bind group',
                          dir => BIND9CONFDIR),
          'reason' => __('Let the bind daemon to be dynamically updated'),
          'module' => 'dns'
        },
        {
          'action' => __('Remove bind9 init script link'),
          'reason' => __('Zentyal will take care of starting and stopping ' .
                        'the services.'),
          'module' => 'dns'
        }
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

    # Create default rules and services
    # only if installing the first time
    unless ($version) {
        my $services = EBox::Global->modInstance('services');

        my $serviceName = 'dns';
        unless ($services->serviceExists(name => $serviceName)) {
            $services->addMultipleService(
                'name' => $serviceName,
                'description' => 'Domain Name Service',
                'readOnly' => 1,
                'services' => $self->_services(),
            );
        }

        my $firewall = EBox::Global->modInstance('firewall');
        $firewall->setInternalService($serviceName, 'accept');
        $firewall->saveConfigRecursive();
    }

    # Execute initial-setup script to create SQL tables
    $self->SUPER::initialSetup($version);
}

sub _services
{
    return [
             {
              'protocol' => 'udp',
              'sourcePort' => 'any',
              'destinationPort' => 53,
             },
             {
              'protocol' => 'tcp',
              'sourcePort' => 'any',
              'destinationPort' => 53,
             },
    ];
}

# Method: _daemons
#
#  Override <EBox::Module::Service::_daemons>
#
sub _daemons
{
    return [
        {
            'name' => 'ebox.bind9'
        }
    ];
}

# Method: enableService
#
# Overrides:
#
#  <EBox::Module::Service::enableService>
#
sub enableService
{
    my ($self, $status) = @_;

    $self->SUPER::enableService($status);
    $self->configureFirewall();
}

# Method: _setConf
#
# Overrides:
#
#  <EBox::Module::Service::_setConf>
#
sub _setConf
{
    my ($self) = @_;
    my @array = ();

    $self->writeConfFile(BIND9CONFFILE,
            "dns/named.conf.mas",
            \@array);

    push(@array, 'forwarders' => $self->_forwarders());

    $self->writeConfFile(BIND9CONFOPTIONSFILE,
            "dns/named.conf.options.mas",
            \@array);

    @array = ();

    my @domainIds = @{$self->_domainIds()};
    # Hash to store the keys indexed by name, storing the secret
    my %keys = ();

    # Delete the already removed RR from dynamic zones
    $self->_removeDeletedRR();

    # Delete files from no longer used domains
    $self->_removeDomainsFiles();

    my @domainData;
    foreach my $domainId (@domainIds) {
        my $domdata = $self->_completeDomain($domainId);
        push(@domainData, $domdata);

        my $file;
        if ( $domdata->{'dynamic'} ) {
            $file = BIND9_UPDATE_ZONES;
        } else {
            $file = BIND9CONFDIR;
        }
        $file .= '/db.' . $domdata->{'name'};

        @array = ();
        push(@array, 'domain' => $domdata);
        push(@array, 'nameserverHostname' => __PACKAGE__->NameserverHost());
        # Prevent to write the file again if this is dynamic and the
        # journal file has been already created
        if ( $domdata->{'dynamic'} and -e "${file}.jnl" ) {
            $self->_updateDynDirectZone($domdata);
        } else {
            $self->writeConfFile($file,"dns/db.mas",\@array);
            EBox::Sudo::root("chown bind:bind '$file'");
        }

        # Add the updater key if the zone is dynamic
        if ( $domdata->{'dynamic'} ) {
            $keys{$domdata->{'name'}} = $domdata->{'tsigKey'};
        }
    }

    my $reversedData = $self->switchToReverseInfoData(\@domainData);

    # Remove the unused reverse files
    $self->_removeUnusedReverseFiles($reversedData);

    my @inaddrs;
    foreach my $reversedDataItem (@{$reversedData}) {
        my $file;
        if ( $reversedDataItem->{'dynamic'} ) {
            $file = BIND9_UPDATE_ZONES;
        } else {
            $file = BIND9CONFDIR;
        }
        $file .= "/db." . $reversedDataItem->{'groupip'};
        push(@inaddrs, { ip      => $reversedDataItem->{'groupip'},
                         dynamic => $reversedDataItem->{'dynamic'},
                         keyNames => $reversedDataItem->{'tsigKeyNames'},
                     } );
        @array = ();
        push(@array, 'rdata' => $reversedDataItem);
        if ( $reversedDataItem->{'dynamic'} and -e "${file}.jnl" ) {
            $self->_updateDynReverseZone($reversedDataItem);
        } else {
            $self->writeConfFile($file, "dns/dbrev.mas", \@array);
            EBox::Sudo::root("chown bind:bind '$file'");
        }

    }

    my @domains = @{$self->domains()};
    my @intnets = @{$self->_intnets()};

    @array = ();
    push(@array, 'confDir' => BIND9CONFDIR);
    push(@array, 'dynamicConfDir' => BIND9_UPDATE_ZONES);
    push(@array, 'domains' => \@domains);
    push(@array, 'inaddrs' => \@inaddrs);
    push(@array, 'intnets' => \@intnets);
    $self->writeConfFile(BIND9CONFLOCALFILE,
            "dns/named.conf.local.mas",
            \@array);

    @array = ( 'keys' => \%keys );
    $self->writeConfFile(KEYSFILE, 'dns/keys.mas', \@array);

    # Set transparent DNS cache
    $self->_setTransparentCache();

}

sub configureFirewall
{
    my ($self) = @_;

    my $fw = EBox::Global->modInstance('firewall');

    if ($self->isEnabled()) {
        $fw->addOutputRule('udp', 53);
        $fw->addOutputRule('tcp', 53);
    } else {
        $fw->removeOutputRule('udp', 53);
        $fw->removeOutputRule('tcp', 53);
    }
}

# Method: menu
#
#       Overrides EBox::Module method.
#
sub menu
{
    my ($self, $root) = @_;

    $root->add(new EBox::Menu::Item('text' => $self->printableName(),
                                    'url' => 'DNS/Composite/Global',
                                    'separator' => 'Infrastructure',
                                    'order' => 420));
}

sub logReportInfo
{
    my ($self) = @_;

    my $domains = @{$self->domains()};
    my $data = [
        {
            'table'  => 'dns_domains',
            'values' => {
                'domains' => $domains
            }
        }
    ];
    return $data;
}

sub consolidateReportInfoQueries
{
    return [
        {
            'target_table' => 'dns_domains_report',
            'query' => {
                'select' => 'domains',
                'from' => 'dns_domains'
            }
        }
    ];
}

# Method: report
#
# Overrides:
#   <EBox::Module::Base::report>
sub report
{
    my ($self, $beg, $end, $options) = @_;

    my $report = {};

    $report->{'domains'} = $self->runMonthlyQuery($beg, $end, {
        'select' => 'domains',
        'from' => 'dns_domains_report',
    }, { 'name' => 'domains' });

    return $report;
}

# Method: keysFile
#
#     Get the keys file path
#
# Returns:
#
#     String - the keys file path
#
sub keysFile
{
    return KEYSFILE;
}

# Method: deletedRRsKey
#
#     Return the deleted RRs state key for adding RRs to delete on
#     dynamic zones
#
# Returns:
#
#     String
#
sub deletedRRsKey
{
    return DELETED_RR_KEY;
}

# Group: Protected methods

# Method: _postServiceHook
#
#     Override this method to try to update the dynamic zones from
#     static definition if the daemon was stopped on configuration
#     regeneration
#
# Overrides:
#
#     <EBox::Module::Service::_postServiceHook>
#
sub _postServiceHook
{
    my ($self, $enabled) = @_;

    if ( $enabled ) {
        my $nTry = 0;
        do {
            sleep(1);
        } while ( $nTry < 5 and (not $self->_isNamedListening()));
        if ( $nTry < 5 ) {
            foreach my $cmd (@{$self->{nsupdateCmds}}) {
                EBox::Sudo::root($cmd);
                my ($filename) = $cmd =~ m:\s(.*?)$:;
                unlink($filename); # Remove the temporary file
            }
            delete $self->{nsupdateCmds};
        }
    }

    return $self->SUPER::_postServiceHook($enabled);
}

# Group: Private methods

sub _intnets
{
    my ($self) = @_;

    my $intnets_string = EBox::Config::configkeyFromFile(DNS_INTNETS,
                                                         DNS_CONF_FILE);
    my @intnets = ();

    if (defined($intnets_string)) {
        @intnets = split(',', $intnets_string);
    }

    return \@intnets;
}

# Method: _hostnames
#  returns an array with all hostname structure
#
# Parameters:
#   model to iterate over
#
# Returns:
#  array ref with this structure data:
#
#  'name': hostname
#  'ip': ip address of hostname
#  'aliases': an array ref returned by <EBox::DNS::aliases> method.
#
sub _hostnames
{
    my ($self, $model) = @_;
    my @array;

    foreach my $id (@{$model->ids()})
    {
        my $hostname = $model->row($id);
        my $hostdata;

        $hostdata->{'name'} = $hostname->valueByName('hostname');
        $hostdata->{'ip'} = $hostname->valueByName('ipaddr');
        $hostdata->{'aliases'} =
            $self->aliases($hostname->subModel('alias'));

        push(@array, $hostdata);
    }

    return \@array;
}

# Method: _formatMailExchangers
#
#       Format the mail exchangers to write configuration settings
#       properly. That is, custom MX records appends a full stop after
#       the type value.
#
# Parameters:
#
#       mailExchangers - model to iterate over
#
#            hostName - String the host's name
#            id - String the row identifier
#            preference - Int the preference attribute
#            ownerDomain - if the hostname owns to the same domain.
#            custom - if the hostname is a foreign one
#
# Returns:
#
#   Array ref of hashes containing the following keys:
#
#      hostName
#       preference
sub _formatMailExchangers
{
    my ($self, $mailExchangers) = @_;

    my @mailExchangers;
    foreach my $id (@{$mailExchangers->ids()}) {
        my $mx = $mailExchangers->row($id);
        my $hostName = $mx->valueByName('hostName');
        if ($mx->elementByName('hostName')->selectedType() eq 'custom') {
            unless ( $hostName =~ m:\.$: ) {
                $hostName .= '.';
            }
        } else {
            $hostName = $mx->parentRow()
               ->subModel('hostnames')
               ->row($hostName)
               ->valueByName('hostname');
        }
        push (@mailExchangers, {
                hostName => $hostName,
                preference => $mx->valueByName('preference')
                });
    }
    return \@mailExchangers;
}

# Method: _formatNameServers
#
#       Format the name servers to write configuration settings
#       properly. That is, custom NS records appends a full stop after
#       the type value.
#
#       If it has none configured, it will configure the following:
#
#       @ NS 127.0.0.1 # If there is no hostname named NS
#       @ NS ns        # If there is a hostname whose name is 'ns'
#
# Parameters:
#
#       nameServers - model to iterate over
#
#            hostName - String the host's name
#            id - String the row identifier
#            ownerDomain - if the hostname owns to the same domain.
#            custom - if the hostname is a foreign one
#
#       hostnames   - model with hostnames for that domain
#
# Returns:
#
#   Array ref of the name servers to set on
#
sub _formatNameServers
{
    my ($self, $nameServers, $hostnames) = @_;

    my @nameservers;
    foreach my $id (@{$nameServers->ids()}) {
        my $ns = $nameServers->row($id);
        my $hostName = $ns->valueByName('hostName');
        if ($ns->elementByName('hostName')->selectedType() eq 'custom') {
            unless ( $hostName =~ m:\.$: ) {
                $hostName .= '.';
            }
        } else {
            $hostName = $ns->printableValueByName('hostName');
        }
        push (@nameservers, $hostName);
    }
    if ( @nameservers == 0 ) {
        # Look for any hostname whose name is 'ns'
        my $matchedId = $hostnames->findId(hostname => __PACKAGE__->NameserverHost());
        if ( defined($matchedId) ) {
            push(@nameservers, __PACKAGE__->NameserverHost());
        }
    }

    return \@nameservers;
}

# Method: _formatTXT
#
#       Format the TXT records to write configuration settings
#       properly
#
# Parameters:
#
#       text - model to iterate over
#
#            hostName - String the host's name
#            id - String the row identifier
#            txt_data - String the TXT record data
#
# Returns:
#
#   Array ref of hashes containing the following keys:
#
#      hostName
#      txt_data
sub _formatTXT
{
    my ($self, $txt) = @_;

    my @txtRecords;
    foreach my $id (@{$txt->ids()}) {
        my $row = $txt->row($id);
        my $hostName = $row->valueByName('hostName');
        if ($row->elementByName('hostName')->selectedType() eq 'domain') {
            $hostName = $row->parentRow()->valueByName('domain') . '.';
        } else {
            $hostName = $row->parentRow()
               ->subModel('hostnames')
               ->row($hostName)
               ->valueByName('hostname');
        }
        push (@txtRecords, {
                hostName => $hostName,
                txt_data => $row->valueByName('txt_data')
               });
    }
    return \@txtRecords;
}

# Method: _formatSRV
#
#       Format the SRV records to write configuration settings
#       properly
#
# Parameters:
#
#       srv - model to iterate over
#
#            service_name - String the service's name
#            protocol - String the protocol
#            priority - Int the priority
#            weight - Int the weight
#            port - Int the target port
#            id - String the row identifier
#            hostName - String the target host name
#
# Returns:
#
#   Array ref of hashes containing the following keys:
#
#      service_name
#      protocol
#      priority
#      weight
#      target_port
#      target_host
#
sub _formatSRV
{
    my ($self, $srv) = @_;

    my @srvRecords;
    foreach my $id (@{$srv->ids()}) {
        my $row = $srv->row($id);
        my $targetHost = $row->valueByName('hostName');
        if ($row->elementByName('hostName')->selectedType() eq 'custom') {
            unless ( $targetHost =~ m:\.$: ) {
                $targetHost = $targetHost . '.';
            }
        } else {
            $targetHost = $row->parentRow()
               ->subModel('hostnames')
               ->row($targetHost)
               ->valueByName('hostname');
        }
        push (@srvRecords, {
                service_name => $row->valueByName('service_name'),
                protocol => $row->valueByName('protocol'),
                priority => $row->valueByName('priority'),
                weight => $row->valueByName('weight'),
                target_port => $row->valueByName('port'),
                target_host => $targetHost,
               });
    }
    return \@srvRecords;
}


# Method: _completeDomain
#
#  Return a structure with all required data to build bind db config files
#
# Parameters:
#
#  domain - String the domain's identifier
#
# Returns:
#
# hash ref - structure data with:
#
#  'name': domain name
#  'ipaddr': domain ip address
#  'dynamic' : the domain is dynamically updated
#  'tsigKey' : the TSIG key is the domain is dynamic
#  'hosts': an array ref returned by <EBox::DNS::_hostnames> method.
#  'mailExchangers' : an array ref returned by <EBox::DNS::_formatMailExchangers>
#  'nameServers' : an array ref returned by <EBox::DNS::_formatNameServers>
#  'txt' : an array ref returned by <EBox::DNS::_formatTXT>
#  'srv' : an array ref returned by <EBox::DNS::_formatSRV>
#
sub _completeDomain # (domainId)
{
    my ($self, $domainId) = @_;

    my $model = $self->model('DomainTable');
    my $row = $model->row($domainId);

    my $domdata;
    $domdata->{'name'} = $row->valueByName('domain');
    foreach my $key (qw(ipaddr dynamic tsigKey)) {
        $domdata->{$key} = $row->valueByName($key);
    }
    $domdata->{'hosts'} = $self->_hostnames(
            $row->subModel('hostnames'));

    my $subModel = $row->subModel('mailExchangers');
    $domdata->{'mailExchangers'} = $self->_formatMailExchangers($subModel);
    $domdata->{'nameServers'} = $self->_formatNameServers($row->subModel('nameServers'),
                                                          $row->subModel('hostnames'));
    $domdata->{'txt'} = $self->_formatTXT($row->subModel('txt'));
    $domdata->{'srv'} = $self->_formatSRV($row->subModel('srv'));

    return $domdata;
}

# Return the forwarders, if any
sub _forwarders
{
    my ($self) = @_;

    my $fwdModel = $self->model('Forwarder');
    my @forwarders = ();
    foreach my $id (@{$fwdModel->ids()}) {
        push(@forwarders, $fwdModel->row($id)->valueByName('forwarder'));
    }

    return \@forwarders;
}

# Return the domain row ids in an array ref
sub _domainIds
{
    my ($self) = @_;

    my $model = $self->model('DomainTable');
    return $model->ids();
}

# Get the ranges for the given domain if used by DHCP module
sub _getRanges
{
    my ($self, $domainData) = @_;

    my @ranges = ();

    my $dhcp = EBox::Global->modInstance('dhcp');
    my $net  = EBox::Global->modInstance('network');

    return \@ranges unless (defined($dhcp));

    foreach my $iface (grep { $net->ifaceMethod($_) eq 'static'} @{$net->allIfaces()}) {
        my $dynDNSRow = $dhcp->dynamicDNSDomains($iface);
        my @domains = ( $dynDNSRow->printableValueByName('dynamic_domain') );
        if ( $dynDNSRow->valueByName('static_domain') ne 'same' ) {
            push(@domains, $dynDNSRow->printableValueByName('static_domain'));
        }
        if ( $domainData->{'name'} eq any(@domains) ) {
            my $initRange = $dhcp->initRange($iface);
            $initRange =~ s/1$/0/;
            my $endRange  = $dhcp->endRange($iface);
            my $ip = new Net::IP("$initRange - $endRange");
            do {
                my $rev = Net::IP->new($ip->ip())->reverse_ip();
                if ( defined($rev) ) {
                    # If the response is 10.in-addr.arpa, transform it to 0.0.10.in-addr.arpa
                    my @subdomains = split(/\./, $rev);
                    if (@subdomains < 5) {
                        $rev = '0.' . $rev for (1 .. (5 - @subdomains));
                    }
                    $rev =~ s:\.in-addr\.arpa\.::;
                    push(@ranges, $rev);
                }
            } while ($ip += 256);
        }
    }
    return \@ranges;
}

# Update an already created dynamic reverse zone using nsupdate
sub _updateDynReverseZone
{
    my ($self, $rdata) = @_;

    my $fh = new File::Temp(DIR => EBox::Config::tmp());

    my $zone = $rdata->{'groupip'} . ".in-addr.arpa";
    foreach my $groupItem (@{$rdata->{'domain'}}) {
        foreach my $host (@{$groupItem->{'hosts'}}) {
            print $fh 'update delete ' . $host->{'ip'} . ".$zone. PTR\n";
            my $prefix = "";
            $prefix = $host->{'name'} . '.' if ( $host->{'name'} );
            print $fh 'update add ' . $host->{'ip'} . ".$zone. 259200 PTR $prefix" . $groupItem->{'name'} . ".\n";
        }
    }
    # Send the previous commands in batch
    if ( $fh->tell() > 0 ) {
        close($fh);
        tie my @file, 'Tie::File', $fh->filename();
        unshift(@file, "zone $zone");
        push(@file, "send");
        untie(@file);
        $self->_launchNSupdate($fh);
    }

}

# Update the dynamic direct zone
sub _updateDynDirectZone
{
    my ($self, $domData) = @_;

    my $zone = $domData->{'name'};
    my $fh = new File::Temp(DIR => EBox::Config::tmp());

    print $fh "zone $zone\n";
    # Delete everything to make sure the RRs are deleted
    # Likewise, MX applies
    # We cannot do it with dhcpd like records
    print $fh "update delete $zone A\n";

    if ( $domData->{'ipaddr'} ) {
        print $fh "update add $zone 259200 A " . $domData->{'ipaddr'} . "\n";
    }

    # print $fh "update delete $zone NS\n";
    foreach my $ns ( @{$domData->{'nameServers'}}) {
        if ( $ns !~ m:\.:g ) {
            $ns .= ".$zone";
        }
        print $fh "update add $zone 259200 NS $ns\n";
    }

    my %seen = ();
    foreach my $host (@{$domData->{'hosts'}}) {
        unless ( $seen{$host->{'name'}} ) {
            # To avoid deleting same name records with different IP addresses
            print $fh 'update delete ' . $host->{'name'} . ".$zone A \n";
        }
        $seen{$host->{'name'}} = 1;
        print $fh 'update add ' . $host->{'name'} . ".$zone 259200 A " . $host->{'ip'} . "\n";
        foreach my $alias (@{$host->{'aliases'}}) {
            print $fh 'update delete ' . $alias->{'name'} . ".$zone CNAME \n";
            print $fh 'update add ' . $alias->{'name'} . ".$zone 259200 CNAME " . $host->{'name'} . ".$zone\n";
        }

    }

    print $fh "update delete $zone MX\n";
    foreach my $mxRR ( @{$domData->{'mailExchangers'}} ) {
        my $mx = $mxRR->{'hostName'};
        if ( $mx !~ m:\.:g ) {
            $mx .= ".$zone";
        }
        print $fh "update add $zone 259200 MX " . $mxRR->{'preference'} . " $mx\n";
    }

    foreach my $txtRR ( @{$domData->{'txt'}} ) {
        my $txt = $txtRR->{'hostName'};
        if ( $txt !~ m:\.:g ) {
            $txt .= ".$zone";
        }
        print $fh "update add $txt 259200 TXT " . $txtRR->{'txt_data'} . "\n";
    }

    foreach my $srvRR ( @{$domData->{'srv'}} ) {
        if ( $srvRR->{'target_host'} !~ m:\.:g ) {
            $srvRR->{'target_host'} .= ".$zone";
        }
        print $fh 'update add _' . $srvRR->{'service_name'} . '._'
                  . $srvRR->{'protocol'} . ".${zone}. 259200 SRV " . $srvRR->{'priority'}
                  . ' ' . $srvRR->{'weight'} . ' ' . $srvRR->{'target_port'}
                  . ' ' . $srvRR->{'target_host'} . "\n";
    }

    print $fh "send\n";
    $self->_launchNSupdate($fh);

}

# Remove no longer available RR in dynamic zones
sub _removeDeletedRR
{
    my ($self) = @_;

    my $deletedRRs = $self->st_get_list(DELETED_RR_KEY);

    my $fh = new File::Temp(DIR => EBox::Config::tmp());
    foreach my $rr (@{$deletedRRs}) {
        print $fh "update delete $rr\n";
    }

    if ( $fh->tell() > 0 ) {
        print $fh "send\n";
        $self->_launchNSupdate($fh);
        $self->st_unset(DELETED_RR_KEY);
    }

}

# Send the nsupdate command or defer to the postservice hook
sub _launchNSupdate
{
    my ($self, $fh) = @_;

    my $cmd = NS_UPDATE_CMD . ' -l -t 10 ' . $fh->filename();
    if ( $self->_isNamedListening() ) {
        try {
            EBox::Sudo::root($cmd);
        } otherwise {
            $fh->unlink_on_destroy(0); # For debug purposes
        };
    } else {
        $self->{nsupdateCmds} = [] unless exists $self->{nsupdateCmds};
        push(@{$self->{nsupdateCmds}}, $cmd);
        $fh->unlink_on_destroy(0);
        EBox::warn('Cannot contact with named, trying in posthook');
    }

}

# Check if named is listening
sub _isNamedListening
{
    my ($self) = @_;

    my $sock = new IO::Socket::INET(PeerAddr => '127.0.0.1',
                                    PeerPort => 53,
                                    Proto    => 'tcp');
    if ( $sock ) {
        close($sock);
        return 1;
    } else {
        return 0;
    }

}

# Remove no longer used domain files to avoid confusing the user
sub _removeDomainsFiles
{
    my ($self) = @_;

    return if ($self->isReadOnly());

    my $oldList = $self->st_get_list('domain_files');
    my @newList = ();

    my $domainModel = $self->model('DomainTable');
    foreach my $id (@{$domainModel->ids()}) {
        my $row = $domainModel->row($id);
        my $file;
        if ( $row->valueByName('dynamic') ) {
            $file = BIND9_UPDATE_ZONES;
        } else {
            $file = BIND9CONFDIR;
        }
        $file .= "/db." . $row->valueByName('domain');
        push(@newList, $file);
    }

    $self->_removeDisjuncFiles($oldList, \@newList);

    $self->st_set_list('domain_files', 'string', \@newList);

}

# Remove no longer used reverse zone files
sub _removeUnusedReverseFiles
{
    my ($self, $reversedData) = @_;

    return if ($self->isReadOnly());

    my $oldList = $self->st_get_list('inarpa_files');
    my @newList = ();
    foreach my $reversedDataItem (@{$reversedData}) {
        my $file;
        if ( $reversedDataItem->{'dynamic'} ) {
            $file = BIND9_UPDATE_ZONES;
        } else {
            $file = BIND9CONFDIR;
        }
        $file .= "/db." . $reversedDataItem->{'groupip'};
        push(@newList, $file);
    }

    $self->_removeDisjuncFiles($oldList, \@newList);

    $self->st_set_list('inarpa_files', 'string', \@newList);

}

# Delete files from disjunction
sub _removeDisjuncFiles
{
    my ($self, $oldList, $newList) = @_;

    my %newSet = map { $_ => 1 } @{$newList};

    # Show the elements in @oldList which are not in %newSet
    my @disjunc = grep { not exists $newSet{$_} } @{$oldList};

    foreach my $file (@disjunc) {
        if ( -f $file ) {
            EBox::Sudo::root("rm -rf '$file'");
        }
        # Remove the jnl if exists as well (only applicable for dyn zones)
        if ( -f "${file}.jnl" ) {
            EBox::Sudo::root("rm -rf '${file}.jnl'");
        }
    }

}

# Set configuration for transparent DNS cache
# TODO: Move FirewallHelper to core to avoid this implementation here without
# using the framework
sub _setTransparentCache
{
    my ($self) = @_;

    if ( $self->model('Settings')->row()->valueByName('transparent') ) {
        # The transparent cache DNS setting is enabled
        my $gl = EBox::Global->getInstance(1);
        if ( $gl->modExists('firewall') ) {
            my $fw = $gl->modInstance('firewall');
            if ( $fw->isEnabled() ) {
                my @rules = ();
                my $net = $gl->modInstance('network');
                eval 'use EBox::FirewallHelper;';
                my $fwHelper = new EBox::FirewallHelper();
                foreach my $iface (@{$net->InternalIfaces()}) {
                    my $addrs = $net->ifaceAddresses($iface);
                    my $input = $fwHelper->_inputIface($iface);
                    foreach my $addr ( map { $_->{address} } @{$addrs} ) {
                        next unless ( defined($addr) and ($addr ne ""));
                        my $rule = "-t nat -A premodules $input "
                                   . "! -d $addr -p tcp --dport " . DNS_PORT
                                   . ' -j REDIRECT --to-ports ' . DNS_PORT;
                        push(@rules, $rule);
                        $rule = "-t nat -A premodules $input "
                                . "! -d $addr -p udp --dport " . DNS_PORT
                                . ' -j REDIRECT --to-ports ' . DNS_PORT;
                        push(@rules, $rule);
                    }
                }
                my @cmds = map { '/sbin/iptables ' . $_ } @rules;
                EBox::Sudo::root(@cmds);
            }
        }
    }
}

# Method: addAlias
#
# Parameters:
# - domain
# - hostname
# - alias
#
# Warning:
# alias is added to the first found matching hostame
# Note:
#  we implement this because vhosttable does not allow exposed method
sub addAlias
{
    my ($self, $domain, $hostname, $alias) = @_;
    $domain or
        throw EBox::Exceptions::MissingArgument('domain');
    $hostname or
        throw EBox::Exceptions::MissingArgument('hostname');
    $alias or
        throw EBox::Exceptions::MissingArgument('alias');


    my $domainModel = $self->model('DomainTable');
    my $domainRow;
    foreach my $id (@{  $domainModel->ids() }) {
        my $row = $domainModel->row($id);
        if ($row->valueByName('domain') eq $domain) {
            $domainRow = $row;
            last;
        }
    }
    if (not $domainRow) {
        throw EBox::Exceptions::DataNotFound(
            data => __('domain'),
            value => $domain
           );
    }


    my $hostnamesModel = $domainRow->subModel('hostnames');
    my $aliasModel;
    foreach my $id (@{  $hostnamesModel->ids() }) {
        my $row = $hostnamesModel->row($id);
        if ($row->valueByName('hostname') eq $hostname) {
            $aliasModel = $row->subModel('alias');
            last;
        }
    }
    if (not $aliasModel) {
        throw EBox::Exceptions::DataNotFound(
            data => __('hostname'),
            value => $hostname
           );
    }

    $aliasModel->addRow(alias => $alias);
}

# Method: removeAlias
#
#  Remove alias for the doamin and hostname. If there are several hostnames the
#  alias is removed in all of them
#
# Parameters:
# - domain
# - hostname
# - alias
#
# Note:
#  we implement this because vhosttable does not allow exposed method
sub removeAlias
{
    my ($self, $domain, $hostname, $alias) = @_;
    $domain or
        throw EBox::Exceptions::MissingArgument('domain');
    $hostname or
        throw EBox::Exceptions::MissingArgument('hostname');
    $alias or
        throw EBox::Exceptions::MissingArgument('alias');

    my $domainModel = $self->model('DomainTable');
    my $domainRow;
    foreach my $id (@{  $domainModel->ids() }) {
        my $row = $domainModel->row($id);
        if ($row->valueByName('domain') eq $domain) {
            $domainRow = $row;
            last;
        }
    }
    if (not $domainRow) {
        throw EBox::Exceptions::DataNotFound(
            data => __('domain'),
            value => $domain
           );
    }

    my $hostnamesModel = $domainRow->subModel('hostnames');
    my $hostnameFound;
    my $aliasFound;
    foreach my $id (@{  $hostnamesModel->ids() }) {
        my $row = $hostnamesModel->row($id);
        if ($row->valueByName('hostname') eq $hostname) {
            $hostnameFound = 1;
            my $aliasModel = $row->subModel('alias');
            foreach my $aliasId  (@{ $aliasModel->ids() } ) {
                my $row = $aliasModel->row($aliasId);
                if ($row->valueByName('alias') eq $alias) {
                    $aliasFound = 1;
                    $aliasModel->removeRow($aliasId);
                    last;
                }
            }
        }
    }

    if (not $hostnameFound) {
        throw EBox::Exceptions::DataNotFound(
            data => __('hostname'),
            value => $hostname
           );
    }elsif (not $aliasFound) {
        throw EBox::Exceptions::DataNotFound(
            data => __('alias'),
            value => $alias
           );
    }
}

1;
