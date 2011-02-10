# Copyright (C) 2008-2010 eBox Technologies S.L.
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


# package EBox::CGI::Progress
#
#  This class is to used to show the progress of a long operation
#
#  This CGI is not intended to be caled directly, any CGI whom wants to switch
#   to a progress view must inherit from ProgressClient and call to the method showProgress
package EBox::CGI::Progress;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::Config;
use EBox::Gettext;
use Encode;
use File::Slurp;

## arguments:
##  title [required]
sub new
{
    my $class = shift;
    my $self = $class->SUPER::new('template' => '/progress.mas',
                                  @_);

    bless($self, $class);
    return $self;
}


sub _process
{
    my ($self) = @_;

    my @params = ();
    push @params, (progressId => $self->_progressId);

    my $title = ($self->param('title'));
    if ($title) {
        $self->{title} = encode (utf8 => $title);
    }

    my @paramsNames = qw( text currentItemCaption itemsLeftMessage
            endNote errorNote reloadInterval currentItemUrl
            nextStepUrl nextStepText nextStepTimeout );
    foreach my $name (@paramsNames) {
        # We use unsafeParam because these paramaters can be i18'ed.
        # Also, these parameters are only used to generate html, no command
        # or so is run.
        use Encode;
        my $value = encode (utf8 => $self->unsafeParam($name));

        $value or
            next;

        push @params, ($name => $value);
    }

    my $file = '/var/lib/zentyal/.first';
    if (-f $file) {
        my $software = EBox::Global->modInstance('software');
        # FIXME: workaround to show ads only during installation
        unless ( $self->{title} and
                encode(utf8 => __('Saving changes')) eq $self->{title} ) {
            push @params, ( adsJson => loadAds() );
        }
    }

    $self->{params} = \@params;
}


sub _progressId
{
    my ($self) = @_;
    my $pId = $self->param('progress');

    $pId or throw EBox::Exceptions::Internal('No progress indicator id supplied');
    return $pId;
}

sub _menu
{
    my ($self) = @_;
    my $file = '/var/lib/zentyal/.first';
    if (-f $file and EBox::Global->modExists('software')) {
        my $software = EBox::Global->modInstance('software');
        # FIXME: workaround to show distinct menu for saving changes and installation proccess
        if ( $self->{title} and
             encode(utf8 => __('Saving changes')) eq $self->{title} ) {
            $software->firstTimeMenu(4);
        } else {
            $software->firstTimeMenu(2);
        }
    } else {
        $self->SUPER::_menu(@_);
    }
}

sub _top
{
    my $global = EBox::Global->getInstance();
    my $img = $global->theme()->{'image_title'};
    print "<div id='top'></div><div id='header'><img src='$img'/></div>";
    return;
}

sub loadAds
{
    my $path = EBox::Config::share() . 'zentyal-software/ads';
    my $file = "$path/ads_" + EBox::locale();
    EBox::info("Try load ads from: $file");
    unless (-f $file) {
        $file =  "$path/ads_" . substr (EBox::locale(),0,2) ;
        EBox::info("File $file doesn't exists, loading default ads");
        unless(-f $file) {
            $file = "$path/ads_EN_en";
        }
    }
    my @ads = read_file($file) or throw EBox::Exceptions::Internal("Error opening ads: $!");
    my $text = "";
    foreach my $line (@ads) {
        $text .= $line . "\n";
    }
    return $text;
}

1;
