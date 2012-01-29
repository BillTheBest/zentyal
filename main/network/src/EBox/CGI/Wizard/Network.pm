# Copyright (C) 2010-2012 eBox Technologies S.L.
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

package EBox::CGI::Network::Wizard::Network;

use strict;
use warnings;

use base 'EBox::CGI::WizardPage';

use EBox::Global;
use EBox::Gettext;
use EBox::Validate;
use Error qw(:try);

sub new # (cgi=?)
{
    my $class = shift;
    my $self = $class->SUPER::new('template' => 'network/wizard/network.mas',
                                  @_);
    bless($self, $class);
    return $self;
}


sub _masonParameters
{
    my ($self) = @_;

    my $net = EBox::Global->modInstance('network');

    my @exifaces = ();
    my @inifaces = ();
    foreach my $iface ( @{$net->ifaces} ) {
        if ( $net->ifaceIsExternal($iface) ) {
            push (@exifaces, $iface);
        } else {
            push (@inifaces, $iface);
        }
    }

    my @params = ();
    push (@params, 'extifaces' => \@exifaces);
    push (@params, 'intifaces' => \@inifaces);
    return \@params;
}


sub _processWizard
{
    my ($self) = @_;

    my $net = EBox::Global->modInstance('network');
    my $gwModel = $net->model('GatewayTable');

    # Remove possible gateways introduced by network-import script
    $gwModel->removeAll();

    foreach my $iface ( @{$net->ifaces} ) {
        my $method = $self->param($iface . '_method');

        if ($method eq 'dhcp') {
            my $ext =  $net->ifaceIsExternal($iface);
            $net->setIfaceDHCP($iface, $ext, 1);

            # As after the installation the method is already set
            # to DHCP, we need to force the change in order to
            # execute ifup during the first save changes
            $net->set_bool("interfaces/$iface/changed", 'true');
        } elsif ($method eq 'static') {
            my $ext =  $net->ifaceIsExternal($iface);
            my $addr = $self->param($iface . '_address');
            my $nmask = $self->param($iface . '_netmask');
            my $gw  = $self->param($iface . '_gateway');
            my $dns1 = $self->param($iface . '_dns1');
            my $dns2 = $self->param($iface . '_dns2');
            $net->setIfaceStatic($iface, $addr, $nmask, $ext, 1);

            if ($gw ne '') {
                try {

                    $gwModel->add(name      => $gw,
                            ip        => $gw,
                            interface => $iface,
                            weight    => 1,
                            default   => 1);
                }
                # ignore errors (probably gateway already exists)
                otherwise {};
            }

            my $dnsModel = $net->model('DNSResolver');
            if ($dns1 ne '') {
                try {
                    $dnsModel->add(nameserver => $dns1);
                } otherwise {};
            }
            if ($dns2 ne '') {
                try {
                    $dnsModel->add(nameserver => $dns2);
                } otherwise {};
            }
        }
    }
}

1;
