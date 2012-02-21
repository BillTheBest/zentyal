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

package EBox::MailFilter::ClamAV;
# package:
use strict;
use warnings;

use Perl6::Junction qw(any all);
use File::Slurp qw(read_file write_file);
use EBox::Config;
#use EBox::Service;
use EBox::Gettext;
use EBox::Global;

use EBox::MailFilter::VDomainsLdap;

# use constant {
#   CLAMAVPIDFILE                 => '/var/run/clamav/clamd.pid',
#   CLAMD_INIT                    => '/etc/init.d/clamav-daemon',
#   CLAMD_SERVICE                  => 'ebox.clamd',
#   CLAMD_CONF_FILE               => '/etc/clamav/ebox.clamd.conf',

#   CLAMD_SOCKET                  => '/var/run/clamav/clamd.ctl',

#   FRESHCLAM_CONF_FILE           => '/etc/clamav/freshclam.conf',
#   FRESHCLAM_OBSERVER_SCRIPT     => 'freshclam-observer',
#   FRESHCLAM_CRON_SCRIPT         => '/etc/cron.hourly/freshclam',
# };


sub new
{
  my $class = shift @_;

  my $self = {};
  bless $self, $class;

  return $self;
}

sub _mailfilterModule
{
  return EBox::Global->modInstance('mailfilter');
}

sub setVDomainService
{
  my ($self, $vdomain, $service) = @_;

  my $vdomainsLdap = EBox::MailFilter::VDomainsLdap->new();
  $vdomainsLdap->checkVDomainExists($vdomain);
  $vdomainsLdap->setAntivirus($vdomain, $service);
}


sub vdomainService
{
  my ($self, $vdomain) = @_;

  my $vdomainsLdap = EBox::MailFilter::VDomainsLdap->new();
  $vdomainsLdap->checkVDomainExists($vdomain);
  $vdomainsLdap->antivirus($vdomain);
}


1;
