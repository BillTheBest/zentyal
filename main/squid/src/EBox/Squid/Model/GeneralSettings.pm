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

package EBox::Squid::Model::GeneralSettings;
use base 'EBox::Model::DataForm';

use strict;
use warnings;

use EBox::Global;
use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Types::Int;
use EBox::Types::Text;
use EBox::Types::Boolean;
use EBox::Types::IPAddr;
use EBox::Types::Union;
use EBox::Types::Port;
use EBox::Squid::Types::Policy;
use EBox::Sudo;

use EBox::Exceptions::External;

use constant STORE_URL => 'https://store.zentyal.com/other/advanced-security.html?utm_source=zentyal&utm_medium=HTTP_proxy_general_settings&utm_campaign=advanced_security_updates';

sub new
{
    my $class = shift @_ ;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    return $self;
}



sub _table
{
    my @tableDesc =
        (
            new EBox::Types::Boolean(
                    fieldName => 'transparentProxy',
                    printableName => __('Transparent Proxy'),
                    editable => 1,
                    defaultValue   => 0,
                    help => _transparentHelp()
                ),
            new EBox::Types::Boolean(
                    fieldName => 'removeAds',
                    printableName => __('Ad Blocking'),
                    editable => 1,
                    defaultValue   => 0,
                    help => __('Remove advertisements from all HTTP traffic')
                ),
            new EBox::Types::Port(
                    fieldName => 'port',
                    printableName => __('Port'),
                    editable => 1,
                    defaultValue   => 3128,
                 ),
            new EBox::Types::Int(
                    fieldName => 'cacheDirSize',
                    printableName => __('Cache files size (MB)'),
                    editable => 1,
                    size => 5,
                    min  => 10,
                    defaultValue   => 100,
                 ),
            new EBox::Squid::Types::Policy(
               fieldName => 'globalPolicy',
               printableName => __('Default policy'),
               defaultValue => 'deny',
               help => _policyHelp(),
               ),
        );

      my $dataForm = {
                      tableName          => 'GeneralSettings',
                      printableTableName => __('General Settings '),
                      modelDomain        => 'Squid',
                      defaultActions     => [ 'editField', 'changeView' ],
                      tableDescription   => \@tableDesc,
                      messages           => {
                          update => __('Settings changed'),
                      },
                     };

    return $dataForm;
}

# Method: viewCustomizer
#
#      To display a permanent message
#
# Overrides:
#
#      <EBox::Model::DataTable::viewCustomizer>
#
sub viewCustomizer
{
    my ($self) = @_;

    my $customizer = $self->SUPER::viewCustomizer();

    my $securityUpdatesAddOn = 0;
    if ( EBox::Global->modExists('remoteservices') ) {
        my $rs = EBox::Global->modInstance('remoteservices');
        $securityUpdatesAddOn = $rs->securityUpdatesAddOn();
    }

    unless ( $securityUpdatesAddOn ) {
        $customizer->setPermanentMessage($self->_commercialMsg(), 'ad');
    }

    return $customizer;
}

sub validateTypedRow
{
  my ($self, $action, $params_r, $actual_r) = @_;

  if (exists $params_r->{port}) {
    $self->_checkPortAvailable($params_r->{port}->value());
  }

  if (exists $params_r->{transparentProxy} or
      exists $params_r->{globalPolicy}) {

    $self->_checkPolicyWithTransProxy($params_r, $actual_r);
    $self->_checkNoAuthPolicy($params_r, $actual_r);
  }

}



sub _checkPortAvailable
{
  my ($self, $port) = @_;

  my $oldPort    = $self->portValue();
  if ($port == $oldPort) {
    # there isn't any change so we left tht things as they are
    return;
  }

  my $firewall = EBox::Global->modInstance('firewall');
  if (not $firewall->availablePort('tcp', $port )) {
      throw EBox::Exceptions::External(
              __x('{port} is already in use. Please choose another',
                  port => $port,
                 )
              );
  }
}


sub _checkPolicyWithTransProxy
{
  my ($self, $params_r, $actual_r) = @_;

  my $trans = exists $params_r->{transparentProxy} ?
                     $params_r->{transparentProxy}->value() :
                     $actual_r->{transparentProxy}->value() ;

  if (not $trans) {
    return;
  }


  my $pol = exists $params_r->{globalPolicy} ?
                     $params_r->{globalPolicy} :
                     $actual_r->{globalPolicy} ;

  if ($pol->usesAuth()) {
    throw EBox::Exceptions::External(
       __('Transparent proxy option is not compatible with authorization policy')
                                    );
  }

  my $objectPolicy = EBox::Global->modInstance('squid')->model('squid/ObjectPolicy');
  if ($objectPolicy->existsAuthObjects()) {
    throw EBox::Exceptions::External(
     __('Transparent proxy is incompatible with the authorization policy found in some objects')
                                    );
  }
}


sub _checkNoAuthPolicy
{
    my ($self, $params_r, $actual_r) = @_;
    my $pol = exists $params_r->{globalPolicy} ?
        $params_r->{globalPolicy} :
            $actual_r->{globalPolicy} ;

    if (not $pol->usesAuth()) {
        my $squid = EBox::Global->modInstance('squid');
        my $groupsPolicies = $squid->model('GlobalGroupPolicy')->groupsPolicies();
        if (@{ $groupsPolicies }) {
            throw EBox::Exceptions::External(
  __('An authorization policy is required because you are using global group policies')
                                            );
        }
    }
}


sub _policyHelp
{
    return __('<i>Filter</i> means that HTTP requests will go through the ' .
              'content filter and they might be rejected if the content is ' .
              'not considered valid.');
}

sub _transparentHelp
{
    return  __('Note that you cannot proxy HTTPS ' .
               'transparently. You will need to add ' .
               'a firewall rule if you enable this mode.');
}

sub _commercialMsg
{
    return __sx('Get Ad blocking updates to keep your HTTP proxy aware of the latest ads to remove them from the websites you browse. The Ad-blocking updates are integrated in the {oh}Advanced Security Updates{ch} add-on that guarantees that the Antivirus, Antispam, Intrusion Detection System and Content Filtering System installed on your Zentyal server are updated on daily basis based on the information provided by the most trusted IT experts.',
                oh => '<a href="' . STORE_URL . '" target="_blank">', ch => '</a>');
}

1;

