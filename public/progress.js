function _set_progress(p, label) {
    if (label) { label += ': '; }
    $("#progress_text").html(label + p + '%');
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
function _gp(label) {
    $.ajax({
        url: 'progress',
        success: function(data) {
            var cur = data['cur'];
            var total = data['total'];
            var pct = total ? 100*cur/total : 0;
            //console.log ('progress: cur ('+cur+') total ('+total+') pct ('+pct+')');
            _set_progress (Math.floor (pct), label);
            //if (cur < total) {   ## apparently 20000 isn't less than 166000
            //if (pct < 100) {
            //    $("#progress").show ('slow');
            //} else {
            //    console.log ('progress: cur ('+cur+') !< total ('+total+'), hiding div');
            //}
        },
        error: function(jqXHR, textStatus, errorThrown) {
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
    });
}
function go(dest) {
    if (running) { return; }
    running = 1;
    var label = dest.split ('/')[0];
    _center_on_screen ($("#progress"));
    var timeout_id = setTimeout (function(){
        //console.log ('timeout! progress(0), calling and setting interval');
        _set_progress (0, label);
        $("#progress").show ('slow');
        _gp(label);
        interval_id = setInterval (function(){_gp(label)}, 5000);
    }, 2000);
    $.get (
        dest,
        function(data) {
            if ('ok' == data) {
                //console.log ('ok, clearing interval, hiding progress, moving forward');
                running = 0;
                clearTimeout (timeout_id);
                clearInterval (interval_id);
                $("#progress").hide ('slow');
                window.location.href = dest;
            //} else if ('ko' == data) {
            //    console.log ('ko');
            //    running = 0;
            //    clearTimeout (timeout_id);
            //    clearInterval (interval_id);
            //    $("#progress").hide ('slow');
            //    $("#error_msg").html ('<br>' + 'ko' + '<br>');
            } else {
                //console.log ('ok, clearing interval, hiding progress, moving forward onto ('+data+')');
                running = 0;
                clearInterval (interval_id);
                $("#progress").hide ('slow');
                go (data);
            }
        }
    ).error (
        function(jqXHR, textStatus, errorThrown) {
            //console.log ('ouch, error');
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

var t0;
function up_progress(e) {
    var t = new Date();
    if (t - t0 < 3000) { return; }
    t0 = t;

    if (e.lengthComputable) {
        _center_on_screen ($("#progress"));
        $("#progress").show ('slow');

        var cur = e.loaded;
        var total = e.total;
        var pct = total ? 100*cur/total : 0;
        //console.log ('loaded ('+e.loaded+') total ('+e.total+'), progress: cur ('+cur+') total ('+total+') pct ('+pct+')');
        _set_progress (Math.floor (pct), 'upload');
    } else {
        //console.log ('!e.lengthComputable');
    }
}

function config_submit_button() {
    var formData = new FormData($('#config_form')[0]);
    t0 = new Date();
    $.ajax ({
        url: 'upload',
        type: 'POST',
        xhr: function() {  // custom xhr
            myXhr = $.ajaxSettings.xhr();
            if (myXhr.upload) {
                //console.log ('good, xhr can upload');
                myXhr.upload.addEventListener ('progress', up_progress, false);
            } else {
                //console.log ('oops, xhr can not upload');
            }
            return myXhr;
        },
        //beforeSend: function() { },
        success: function(data) {
            $("#progress").hide ('slow');
            if ('ko' == data) {
                //console.log ('upload: ko');
            } else {
                //console.log ('upload: ok, data ('+data+')');
                var url = 'import/' + data;
                go (url);
            }
        },
        error: function(jqXHR, textStatus, errorThrown) {
            $("#progress").hide ('slow');
            if (errorThrown) {
                $("#error_msg").html ('<br>' + errorThrown + '<br>');
            } else {
                $("#error_msg").html ('<br>' + textStatus + '<br>');
            }
        },
        data: formData,
        //Options to tell JQuery not to process data or worry about content-type
        cache: false,
        contentType: false,
        processData: false
    });
}
function gen_output() {
    var formData = new FormData($('#calc_sections')[0]);
    if (running) { return; }
    running = 1;
    var label = 'BBCode/HTML';
    _center_on_screen ($("#progress"));
    var timeout_id = setTimeout (function(){
        //console.log ('gen_output timeout! progress(0), calling and setting interval');
        _set_progress (0, label);
        $("#progress").show ('slow');
        _gp(label);
        interval_id = setInterval (function(){_gp(label)}, 5000);
    }, 2000);
    $.ajax ({
        url: 'calc_sections',
        type: 'POST',
        success: function(data) {
            running = 0;
            clearTimeout (timeout_id);
            clearInterval (interval_id);
            $("#progress").hide ('slow');
            if ('ko' == data) {
                //console.log ('gen_output: ko');
            } else if ('index' == data) {
                go (data);
            } else {
                //console.log ('gen_output: ok, data ('+data+')');
                var url = 'gen_output_' + data;
                window.open (url);
            }
        },
        error: function(jqXHR, textStatus, errorThrown) {
            running = 0;
            clearTimeout (timeout_id);
            clearInterval (interval_id);
            $("#progress").hide ('slow');
            if (errorThrown) {
                $("#error_msg").html ('<br>' + errorThrown + '<br>');
            } else {
                $("#error_msg").html ('<br>' + textStatus + '<br>');
            }
        },
        data: formData,
        cache: false,
        contentType: false,
        processData: false
    });
}
