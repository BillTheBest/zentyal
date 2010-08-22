#!/usr/bin/perl

#
# This is a migration script to add a service and firewall rules
# for the Zentyal Asterisk system
#

package EBox::Migration;
use base 'EBox::Migration::Base';

use strict;
use warnings;

use EBox;
use EBox::Global;
use EBox::Gettext;
use Error qw(:try);

sub runGConf
{
    my ($self) = @_;

    my $service = EBox::Global->getInstance()->modInstance('services');
    my $firewall = EBox::Global->getInstance()->modInstance('firewall');

    my $serviceName = 'VoIP';
    if (not $service->serviceExists(name => $serviceName)) {
        $service->addMultipleService(
                'name' => $serviceName,
                'description' => __d('Zentyal VoIP system'),
                'translationDomain' => 'ebox-asterisk',
                'internal' => 1,
                'readOnly' => 1,
                'services' => [
                                { # sip
                                    'protocol' => 'udp',
                                    'sourcePort' => 'any',
                                    'destinationPort' => '5060',
                                },
                                { # iax1
                                    'protocol' => 'udp',
                                    'sourcePort' => 'any',
                                    'destinationPort' => '4569',
                                },
                                { # iax2
                                    'protocol' => 'udp',
                                    'sourcePort' => 'any',
                                    'destinationPort' => '5036',
                                },
                                { # rtp
                                    'protocol' => 'udp',
                                    'sourcePort' => 'any',
                                    'destinationPort' => '10000:20000',
                                },
                              ]);
   }

   $firewall->setExternalService($serviceName, 'deny');
   $firewall->setInternalService($serviceName, 'accept');
   $firewall->saveConfigRecursive();
}

EBox::init();

my $mod = EBox::Global->modInstance('asterisk');
my $migration =  __PACKAGE__->new(
        'gconfmodule' => $mod,
        'version' => 1
        );
$migration->execute();
