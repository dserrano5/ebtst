function _set_progress(p) {
    $("#progress_text").html(p + '%');
    $("#progress_bar").css({
        width: p + '%',
        float: "left",
        //"border": "1px solid black",
        //"background-color": "white",
    });
}
function _center_on_screen(elem) {
    elem.css ("position", "fixed");
    elem.css ("top",  Math.max (0, ($(window).height() - elem.outerHeight())/2 + $(window).scrollTop() ) + "px");
    elem.css ("left", Math.max (0, ($(window).width()  - elem.outerWidth() )/2 + $(window).scrollLeft()) + "px");
}
var interval_id;
var running = 0;
function _gp() {
    $.ajax({
        url: base_href+'/progress',
        success: function(data) {
            var cur = data['cur'];
            var total = data['total'];
            var pct = 100*cur/total;
            console.log ('progress: cur ('+cur+') total ('+total+') pct ('+pct+')');
            _set_progress (Math.floor (pct));
            //if (cur < total) {   ## apparently 20000 isn't less than 166000
            //if (pct < 100) {
            //    $("#progress").show ('slow');
            //} else {
            //    console.log ('progress: cur ('+cur+') !< total ('+total+'), hiding div');
            //}
        }
    });
}
function go(dest) {
    if (running) { return; }
    running = 1;
    _center_on_screen ($("#progress"));
    _set_progress (0);
    var timeout_id = setTimeout (function(){
        console.log ('timeout! calling and setting interval');
        $("#progress").show ('slow');
        _gp();
        interval_id = setInterval (function(){_gp()}, 5000);
    }, 2000);
    $.get (
        base_href+dest,
        function(data) {
            console.log ('ok, clearing interval, hiding progress, moving forward');
            running = 0;
            clearInterval (interval_id);
            $("#progress").hide ('slow');
            window.location.href = base_href+dest;
        }
    ).error (
        function(jqXHR, textStatus, errorThrown) {
            console.log ('ouch, error');
            running = 0;
            clearTimeout (timeout_id);
            clearInterval (interval_id);
            $("#progress").hide ('slow');
            if (errorThrown) {
                $("#error_msg").html ('<br>' + errorThrown + '<br>');
            } else {
                $("#error_msg").html ('<br>' + textStatus + '<br>');
            }
        }
    );
}
