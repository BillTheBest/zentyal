helpShown = false;

function showHelp() {
    helpShown = true;
    $("hidehelp").style.display = "inline";
    $("showhelp").style.display = "none";
    $$(".help").each(function(e) {
        e.style.display = "block";
    });
}

function hideHelp() {
    helpShown = false;
    $("hidehelp").style.display = "none";
    $("showhelp").style.display = "inline";
    $$(".help").each(function(e) {
        e.style.display = "none";
    });
}

function initHelp() {
    if($$(".help").length == 0) {
        var helpbutton = $("helpbutton");
        if (helpbutton) {
            helpbutton.hide();
        }
    } else {
        var helpbutton = $("helpbutton");
        if (helpbutton) {
            helpbutton.show();
        }
        if (helpShown) {
            showHelp();
        } else {
            hideHelp();
        }
    }
}

initHelp()
document.body.addEventListener("DOMNodeInserted", initHelp, false);
