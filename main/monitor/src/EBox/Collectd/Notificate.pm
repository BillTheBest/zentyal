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

# Class: EBox::Collectd::Notificate
#
#    Add the Zentyal own notification plugin to collectd.
#
#    Documentation is available on:
#
#     http://collectd.org/documentation/manpages/collectd-perl.5.shtml
#
#    Based on flexible alert frequency, if a notification is set to
#    persist, then the alerts must be sent after X seconds happened
#    the same notification level

package EBox::Collectd::Notificate;

use strict;
use warnings;

# Core
#use Errno;
#use Fcntl;

# External uses
use Collectd qw(:all);
use Data::Dumper;
use File::Temp;
use File::Slurp;
use JSON;

# Constants
# Set it fixed not to include Zentyal packages
use constant EVENTS_INCOMING_DIR       => '/var/run/zentyal/events/incoming/';
use constant EVENTS_INCOMING_READY_DIR => EVENTS_INCOMING_DIR . 'ready/';
use constant EVENTS_FIFO               => '/var/lib/zentyal/tmp/events-fifo';
use constant NOTIFICATION_CONF         => '/var/lib/zentyal/conf/monitor/notif.conf';
use constant EBOX_USER                 => 'ebox';

our %persistConf = ();

plugin_register(TYPE_INIT, 'init', 'ebox_init_notify');
plugin_register(TYPE_NOTIF, 'notificate', 'ebox_notify');

# Procedure: ebox_init_notify
#
#     Read the notification configuration in JSON format
#
#     This file is written by monitor module. Content:
#
#       { 'plugin' => { 'plugin_instance' => { 'type' => {
#       'type_instance' => { 'level' => { 'first' => 0, 'after' => n
#       }}}}}}
#
sub ebox_init_notify
{
    if ( -r NOTIFICATION_CONF ) {
        my $content = File::Slurp::read_file(NOTIFICATION_CONF);
        %persistConf = %{decode_json($content)};
    }

    return 1;

}

# Procedure: ebox_notify
#
#     Dispatch a notification to the Zentyal system using FIFO, if
#     possible, if not, using a directory
#
# Parameters:
#
#     notification - hash ref with the following elements:
#         severity => NOTIF_FAILURE || NOTIF_WARNING || NOTIF_OKAY,
#         time     => time (),
#         message  => 'status message',
#         host     => $hostname_g,
#         plugin   => 'myplugin',
#         type     => 'mytype',
#         plugin_instance => '',
#         type_instance   => ''
#         meta     => [ { name => <name>, value => <value> }, ... ]
#
sub ebox_notify
{
    my ($not) = @_;

    my $level  = 'fatal';
    my $aLevel = 'info';
    if ( $not->{severity} == NOTIF_FAILURE ) {
        $level  = 'error';
        $aLevel = 'warn';
    } elsif ( $not->{severity} == NOTIF_WARNING ) {
        $level  = 'warn';
        $aLevel = 'error';
    } else {
        $level  = 'info';
        $aLevel = 'warn';
    }

    $not->{plugin_instance} = '' unless defined($not->{plugin_instance});
    $not->{type_instance}   = '' unless defined($not->{type_instance});

    if ( exists $persistConf{$not->{plugin}}->{$not->{plugin_instance}}->{$not->{type}}->{$not->{type_instance}} ) {
        my $measureConf  = $persistConf{$not->{plugin}}->{$not->{plugin_instance}}->{$not->{type}}->{$not->{type_instance}}->{$level};
        my $aMeasureConf = $persistConf{$not->{plugin}}->{$not->{plugin_instance}}->{$not->{type}}->{$not->{type_instance}}->{$aLevel};
        if ( $measureConf->{first} ) {
            if ( $measureConf->{first} + $measureConf->{after} < $not->{time} ) {
                $measureConf->{first} = 0;
            } else {
                # Nothing new under the sun
                return 1;
            }
        } else {
            # First valid value
            $measureConf->{first}  = $not->{time};
            # Switching from this level to the contrary (clear counters)
            $aMeasureConf->{first} = 0;
            return 1;
        }
    }

    my $src = 'monitor-' . $not->{plugin};
    $src .= '-' . $not->{plugin_instance} if (defined($not->{plugin_instance})
                                              and $not->{plugin_instance} ne '');
    $src .= '-' . $not->{type} if ( $not->{type} ne $not->{plugin} );
    $src .= '-' . $not->{type_instance} if ($not->{type_instance} ne '');

    my $evt = {
        message => $not->{message},
        source  => $src,
        level   => $level,
        timestamp => $not->{time}
       };

    # Dumpered event without newline chars
    $Data::Dumper::Indent = 0;
    $Data::Dumper::Useqq = 1;
    my $strEvt = Dumper($evt);
    $strEvt .= "\n";
    # Unbuffered I/0 (Not used for now)
#     my $rv = sysopen(my $fifo, EVENTS_FIFO, O_NONBLOCK|O_WRONLY);
#     if (not defined($rv)) {
#         _notifyUsingFS($strEvt);
#         return 1;
#     }
#     $rv = syswrite($fifo, $strEvt, length($strEvt));
#     if ( (! defined($rv) and $!{EAGAIN}) or ($rv != length($strEvt))) {
#         # The syscall would block
#         _notifyUsingFS($strEvt);
#     }
#     close($fifo);

    _notifyUsingFS($strEvt);

    return 1;

}

# Group: Private procedures
sub _notifyUsingFS
{
    my ($strEvt) = @_;

    my $fileTemp = new File::Temp(TEMPLATE => 'evt_XXXXX',
                                  DIR      => EVENTS_INCOMING_DIR,
                                  UNLINK   => 0);
    print $fileTemp $strEvt;
    # Make files readable by Zentyal
#    my ($login, $pass, $uid, $gid) = getpwnam(EBox::Config::user());
    my ($login, $pass, $uid, $gid) = getpwnam(EBOX_USER);
    chown($uid, $gid , $fileTemp->filename());
    my ($basename) = ($fileTemp->filename() =~ m:.*/(.*)$:g);
    symlink($fileTemp->filename(), EVENTS_INCOMING_READY_DIR . $basename);

}

1;
