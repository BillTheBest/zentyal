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

package EBox::Html;

use strict;
use warnings;

use EBox::Global;
use EBox::Config;
use EBox::Gettext;
use EBox::Menu::Root;

use HTML::Mason;

#
# Method: title
#
#	Returns the html code for the title
#
# Returns:
#
#	string - containg the html code for the title
#
sub title
{
    my $save = __('Save changes');
    my $logout = __('Logout');

    my $global = EBox::Global->getInstance();
    my $finishClass;
    if ($global->unsaved()) {
        $finishClass = "changed";
    } else {
        $finishClass = "notchanged";
    }

    # Display control panel button only if the eBox is subscribed
    my $remoteServicesURL = '';
    if ($global->modExists('remoteservices')) {
        my $remoteServicesMod = $global->modInstance('remoteservices');
        if ($remoteServicesMod->eBoxSubscribed()) {
            unless (EBox::Config::configkey('hide_cloud_link')) {
                $remoteServicesURL = $remoteServicesMod->controlPanelURL();
            }
        }
    }
    my $image_title = $global->theme()->{'image_title'};

    my $html = makeHtml('headTitle.mas',
                        save => $save,
                        logout => $logout,
                        finishClass => $finishClass,
                        remoteServicesURL => $remoteServicesURL,
                        image_title => $image_title,
                       );
    return $html;
}

#
# Method: titleNoAction
#
#	Returns the html code for the title without action buttons
#
# Returns:
#
#	string - containg the html code for the title
#
sub titleNoAction
{
    my $global = EBox::Global->getInstance();
    my $image_title = $global->theme()->{'image_title'};

    my $html = makeHtml('headTitle.mas',
                        image_title => $image_title,
                       );
    return $html;
}



#
# Method: menu
#
#	Returns the html code for the menu
#
# Returns:
#
#	string - containg the html code for the menu
#
sub menu
{
    my $current = shift;

    my $global = EBox::Global->getInstance();

    my $root = new EBox::Menu::Root('current' => $current);
    foreach (@{$global->modNames}) {
        my $mod = $global->modInstance($_);
        $mod->menu($root);
    }

    return $root->html;
}

#
# Method: footer
#
#	Returns the html code for the footer page
#
# Returns:
#
#	string - containg the html code for the footer page
#
sub footer
{
    my $global = EBox::Global->getInstance();
    my $copyright = $global->theme()->{'copyright_footer'};

    my $html = makeHtml('footer.mas',
                        'copyright_footer' => $copyright);
    return $html;
}

#
# Method: header
#
#	Returns the html code for the header page
#
# Returns:
#
#	string - containg the html code for the header page
#
sub header # (title)
{
    my ($title) = @_;

    my $serverName = __('Zentyal');
    my $global = EBox::Global->getInstance();
    if ( $global->modExists('remoteservices') ) {
        my $remoteServicesMod = $global->modInstance('remoteservices');
        if ( $remoteServicesMod->eBoxSubscribed() ) {
            $serverName = $remoteServicesMod->eBoxCommonName();
        }
    }

    $title = "$serverName - $title";

    my $favicon = $global->theme()->{'favicon'};
    my $html = makeHtml('header.mas', title => $title, favicon => $favicon );
    return $html;

}


sub makeHtml
{
    my ($filename, @params) = @_;

    my $filePath = EBox::Config::templates . "/$filename";

    my $output;
    my $interp = HTML::Mason::Interp->new(comp_root => EBox::Config::templates, out_method => \$output,);
    my $comp = $interp->make_component(comp_file => $filePath);

    $interp->exec($comp, @params);
    return $output;
}

1;
