<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ taglib uri="http://java.sun.com/jsp/jstl/core" prefix="c" %>

<html>
	<script src="chrome-extension://fdcgdnkidjaadafnichfpabhfomcebme/scripts/webrtc-patch.js"></script>
<head>
	<title>스마트홈 제어</title>
	<meta charset="utf-8" />
	<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no" />
	<link rel="stylesheet" href="resources/assets/css/main.css" />
	<link rel="stylesheet" href="resources/assets/css/custom.css" />
	<!--[if lte IE 9]><link rel="stylesheet" href="resources/assets/css/ie9.css" /><![endif]-->
	<noscript><link rel="stylesheet" href="resources/assets/css/noscript.css" /></noscript>
	<!-- Scripts -->
	<script type="text/javascript">
            function httpGetAsync(theUrl, callback) {
                try {
                    var xmlHttp = new XMLHttpRequest();
                    xmlHttp.onreadystatechange = function () {
                        if (xmlHttp.readyState == 4 && xmlHttp.status == 200) {
                            callback(xmlHttp.responseText);
                        }
                    };
                    xmlHttp.open("GET", theUrl, true); // true for asynchronous
                    xmlHttp.send(null);
                } catch (e) {
                    console.error(e);
                }
            }

            function addGyronormScript() {
                var srcUrl = "https://rawgit.com/dorukeker/gyronorm.js/master/dist/gyronorm.complete.min.js"
                httpGetAsync(srcUrl, function (text) {
                    var script = document.createElement("script");
                    script.setAttribute("src", srcUrl);
                    document.getElementsByTagName("head")[0].appendChild(script);
                });
            }

            var signalling_server_hostname = location.hostname || "172.30.1.43:8080";
            var signalling_server_address = signalling_server_hostname + ':' + (location.port || (location.protocol === 'https:' ? 443 : 80));
            var isFirefox = typeof InstallTrigger !== 'undefined';// Firefox 1.0+

            addEventListener("DOMContentLoaded", function () {
                document.getElementById('signalling_server').value = "172.30.1.43:8080";
                var cast_not_allowed = !('MediaSource' in window) || location.protocol !== "https:";
                if (cast_not_allowed || !isFirefox) {
                    if (document.getElementById('cast_tab'))
                        document.getElementById('cast_tab').disabled = true;
                    if (cast_not_allowed) { // chrome supports if run with --enable-usermedia-screen-capturing
                        document.getElementById('cast_screen').disabled = true;
                    }
                    document.getElementById('cast_window').disabled = true;
                    document.getElementById('cast_application').disabled = true;
                    document.getElementById('note2').style.display = "none";
                    document.getElementById('note4').style.display = "none";
                } else {
                    document.getElementById('note1').style.display = "none";
                    document.getElementById('note3').style.display = "none";
                }
                addGyronormScript();
            });

            var ws = null;
            var pc;
            var gn;
            var datachannel, localdatachannel;
            var audio_video_stream;
            var recorder = null;
            var recordedBlobs;
            var pcConfig = {"iceServers": [
                    {"urls": ["stun:stun.l.google.com:19302", "stun:" + signalling_server_hostname + ":3478"]}
                ]};
            var pcOptions = {
                optional: [
                    // Deprecated:
                    //{RtpDataChannels: false},
                    //{DtlsSrtpKeyAgreement: true}
                ]
            };
            var mediaConstraints = {
                optional: [],
                mandatory: {
                    OfferToReceiveAudio: true,
                    OfferToReceiveVideo: true
                }
            };
            var keys = [];
            var trickle_ice = true;
            var remoteDesc = false;
            var iceCandidates = [];

            RTCPeerConnection = window.RTCPeerConnection || /*window.mozRTCPeerConnection ||*/ window.webkitRTCPeerConnection;
            RTCSessionDescription = /*window.mozRTCSessionDescription ||*/ window.RTCSessionDescription;
            RTCIceCandidate = /*window.mozRTCIceCandidate ||*/ window.RTCIceCandidate;
            navigator.getUserMedia = navigator.getUserMedia || navigator.mozGetUserMedia || navigator.webkitGetUserMedia || navigator.msGetUserMedia;
            var URL = window.URL || window.webkitURL;

            function createPeerConnection() {
                try {
                    var pcConfig_ = pcConfig;
                    try {
                        ice_servers = document.getElementById('ice_servers').value;
                        if (ice_servers) {
                            pcConfig_.iceServers = JSON.parse(ice_servers);
                        }
                    } catch (e) {
                        alert(e + "\nExample: "
                                + '\n[ {"urls": "stun:stun1.example.net"}, {"urls": "turn:turn.example.org", "username": "user", "credential": "myPassword"} ]'
                                + "\nContinuing with built-in RTCIceServer array");
                    }
                    console.log(JSON.stringify(pcConfig_));
                    pc = new RTCPeerConnection(pcConfig_, pcOptions);
                    pc.onicecandidate = onIceCandidate;
                    if ('ontrack' in pc) {
                        pc.ontrack = onTrack;
                    } else {
                        pc.onaddstream = onRemoteStreamAdded; // deprecated
                    }
                    pc.onremovestream = onRemoteStreamRemoved;
                    pc.ondatachannel = onDataChannel;
                    console.log("peer connection successfully created!");
                } catch (e) {
                    console.error("createPeerConnection() failed");
                }
            }

            function onDataChannel(event) {
                console.log("onDataChannel()");
                datachannel = event.channel;

                event.channel.onopen = function () {
                    console.log("Data Channel is open!");
                    document.getElementById('datachannels').disabled = false;
                };

                event.channel.onerror = function (error) {
                    console.error("Data Channel Error:", error);
                };

                event.channel.onmessage = function (event) {
                    console.log("Got Data Channel Message:", event.data);
                    document.getElementById('datareceived').value = event.data;
                };

                event.channel.onclose = function () {
                    datachannel = null;
                    document.getElementById('datachannels').disabled = true;
                    console.log("The Data Channel is Closed");
                };
            }

            function onIceCandidate(event) {
                if (event.candidate) {
                    var candidate = {
                        sdpMLineIndex: event.candidate.sdpMLineIndex,
                        sdpMid: event.candidate.sdpMid,
                        candidate: event.candidate.candidate
                    };
                    var request = {
                        what: "addIceCandidate",
                        data: JSON.stringify(candidate)
                    };
                    ws.send(JSON.stringify(request));
                } else {
                    console.log("End of candidates.");
                }
            }

            function addIceCandidates() {
                iceCandidates.forEach(function (candidate) {
                    pc.addIceCandidate(candidate,
                        function () {
                            console.log("IceCandidate added: " + JSON.stringify(candidate));
                        },
                        function (error) {
                            console.error("addIceCandidate error: " + error);
                        }
                    );
                });
                iceCandidates = [];
            }

            function onRemoteStreamAdded(event) {
                console.log("Remote stream added:", URL.createObjectURL(event.stream));
                var remoteVideoElement = document.getElementById('remote-video');
                remoteVideoElement.src = URL.createObjectURL(event.stream);
                remoteVideoElement.play();
            }

            function onTrack(event) {
                console.log("Remote track!");
                var remoteVideoElement = document.getElementById('remote-video');
                remoteVideoElement.srcObject = event.streams[0];
                remoteVideoElement.play();
            }

            function onRemoteStreamRemoved(event) {
                var remoteVideoElement = document.getElementById('remote-video');
                remoteVideoElement.srcObject = null;
                remoteVideoElement.src = ''; // TODO: remove
            }

            function start() {

                if ("WebSocket" in window) {
                    document.getElementById("record").disabled = false;
                    document.getElementById("stop").disabled = false;
                    document.getElementById("start").disabled = true;
                    document.documentElement.style.cursor = 'wait';
                    var server = document.getElementById("signalling_server").value.toLowerCase();

                    var protocol = location.protocol === "https:" ? "wss:" : "ws:";
                    ws = new WebSocket(protocol + '//' + server + '/stream/webrtc');

                    function call(stream) {
                        iceCandidates = [];
                        remoteDesc = false;
                        createPeerConnection();
                        if (stream) {
                            pc.addStream(stream);
                        }
                        var request = {
                            what: "call",
                            options: {
                                force_hw_vcodec: false,
                                vformat: document.getElementById("remote_vformat").value,
                                trickle_ice: trickleice_selection()
                            }
                        };
                        ws.send(JSON.stringify(request));
                        console.log("call(), request=" + JSON.stringify(request));
                    }

                    ws.onopen = function () {
                        console.log("onopen()");

                        audio_video_stream = null;
                        var cast_mic = false;
                        var cast_tab = false;
                        var cast_camera = false;
                        var cast_screen = false;
                        var cast_window = false;
                        var cast_application = false;
                        var echo_cancellation = true;
                        var localConstraints = {};
                        if (cast_mic) {
                            if (echo_cancellation)
                                localConstraints['audio'] = isFirefox ? {echoCancellation: true} : {optional: [{echoCancellation: true}]};
                            else
                                localConstraints['audio'] = isFirefox ? {echoCancellation: false} : {optional: [{echoCancellation: false}]};
                        } else if (cast_tab) {
                            localConstraints['audio'] = {mediaSource: "audioCapture"};
                        } else {
                            localConstraints['audio'] = false;
                        }
                        if (cast_camera) {
                            localConstraints['video'] = true;
                        } else if (cast_screen) {
                            if (isFirefox) {
                                localConstraints['video'] = {frameRate: {ideal: 30, max: 30},
                                    //width: {min: 640, max: 960},
                                    //height: {min: 480, max: 720},
                                    mozMediaSource: "screen",
                                    mediaSource: "screen"};
                            } else {
                                // chrome://flags#enable-usermedia-screen-capturing
                                document.getElementById("cast_mic").checked = false;
                                localConstraints['audio'] = false; // mandatory for chrome
                                localConstraints['video'] = {'mandatory': {'chromeMediaSource':'screen'}};
                            }
                        } else if (cast_window)
                            localConstraints['video'] = {frameRate: {ideal: 30, max: 30},
                                //width: {min: 640, max: 960},
                                //height: {min: 480, max: 720},
                                mozMediaSource: "window",
                                mediaSource: "window"};
                        else if (cast_application)
                            localConstraints['video'] = {frameRate: {ideal: 30, max: 30},
                                //width: {min: 640, max: 960},
                                //height:  {min: 480, max: 720},
                                mozMediaSource: "application",
                                mediaSource: "application"};
                        else
                            localConstraints['video'] = false;

                        var localVideoElement = document.getElementById('local-video');
                        if (localConstraints.audio || localConstraints.video) {
                            if (navigator.getUserMedia) {
                                navigator.getUserMedia(localConstraints, function (stream) {
                                    audio_video_stream = stream;
                                    call(stream);
                                    localVideoElement.muted = true;
                                    //localVideoElement.src = URL.createObjectURL(stream); // deprecated
                                    localVideoElement.srcObject = stream;
                                    localVideoElement.play();
                                }, function (error) {
                                    stop();
                                    alert("An error has occurred. Check media device, permissions on media and origin.");
                                    console.error(error);
                                });
                            } else {
                                console.log("getUserMedia not supported");
                            }
                        } else {
                            call();
                        }
                    };

                    ws.onmessage = function (evt) {
                        var msg = JSON.parse(evt.data);
                        if (msg.what !== 'undefined') {
                            var what = msg.what;
                            var data = msg.data;
                        }
                        //console.log("message=" + msg);
                        console.log("message =" + what);

                        switch (what) {
                            case "offer":
                                pc.setRemoteDescription(new RTCSessionDescription(JSON.parse(data)),
                                        function onRemoteSdpSuccess() {
                                            remoteDesc = true;
                                            addIceCandidates();
                                            console.log('onRemoteSdpSucces()');
                                            pc.createAnswer(function (sessionDescription) {
                                                pc.setLocalDescription(sessionDescription);
                                                var request = {
                                                    what: "answer",
                                                    data: JSON.stringify(sessionDescription)
                                                };
                                                ws.send(JSON.stringify(request));
                                                console.log(request);

                                            }, function (error) {
                                                alert("Failed to createAnswer: " + error);

                                            }, mediaConstraints);
                                        },
                                        function onRemoteSdpError(event) {
                                            alert('Failed to set remote description (unsupported codec on this browser?): ' + event);
                                            stop();
                                        }
                                );

                                /*
                                 * No longer needed, it's implicit in "call"
                                var request = {
                                    what: "generateIceCandidates"
                                };
                                console.log(request);
                                ws.send(JSON.stringify(request));
                                */
                                break;

                            case "answer":
                                break;

                            case "message":
                                alert(msg.data);
                                break;

                            case "iceCandidate": // when trickle is enabled
                                if (!msg.data) {
                                    console.log("Ice Gathering Complete");
                                    break;
                                }
                                var elt = JSON.parse(msg.data);
                                let candidate = new RTCIceCandidate({sdpMLineIndex: elt.sdpMLineIndex, candidate: elt.candidate});
                                iceCandidates.push(candidate);
                                if (remoteDesc)
                                    addIceCandidates();
                                document.documentElement.style.cursor = 'default';
                                break;

                            case "iceCandidates": // when trickle ice is not enabled
                                var candidates = JSON.parse(msg.data);
                                for (var i = 0; candidates && i < candidates.length; i++) {
                                    var elt = candidates[i];
                                    let candidate = new RTCIceCandidate({sdpMLineIndex: elt.sdpMLineIndex, candidate: elt.candidate});
                                    iceCandidates.push(candidate);
                                }
                                if (remoteDesc)
                                    addIceCandidates();
                                document.documentElement.style.cursor = 'default';
                                break;
                        }
                    };

                    ws.onclose = function (evt) {
                        if (pc) {
                            pc.close();
                            pc = null;
                        }
                        document.getElementById("stop").disabled = true;
                        document.getElementById("start").disabled = false;
                        document.getElementById("record").disabled = true;
                        document.documentElement.style.cursor = 'default';
                    };

                    ws.onerror = function (evt) {
                        alert("An error has occurred!");
                        ws.close();
                    };

                } else {
                    alert("Sorry, this browser does not support WebSockets.");
                }
            }

            function stop() {

                // if (datachannel) {
                //     console.log("closing data channels");
                //     datachannel.close();
                //     datachannel = null;
                //     document.getElementById('datachannels').disabled = true;
                // }
                // if (localdatachannel) {
                //     console.log("closing local data channels");
                //     localdatachannel.close();
                //     localdatachannel = null;
                // }
                // if (audio_video_stream) {
                //     try {
                //         if (audio_video_stream.getVideoTracks().length)
                //             audio_video_stream.getVideoTracks()[0].stop();
                //         if (audio_video_stream.getAudioTracks().length)
                //             audio_video_stream.getAudioTracks()[0].stop();
                //         audio_video_stream.stop(); // deprecated
                //     } catch (e) {
                //         for (var i = 0; i < audio_video_stream.getTracks().length; i++)
                //             audio_video_stream.getTracks()[i].stop();
                //     }
                //     audio_video_stream = null;
                // }
                stop_record();
                //document.getElementById("record").disabled = false;
                document.getElementById('remote-video').srcObject = null;
                document.getElementById('local-video').srcObject = null;
                document.getElementById('remote-video').src = ''; // TODO; remove
                document.getElementById('local-video').src = ''; // TODO: remove
                if (pc) {
                    pc.close();
                    pc = null;
                }
                if (ws) {
                    ws.close();
                    ws = null;
                }
                document.getElementById("stop").disabled = false;
                document.getElementById("start").disabled = true;
                document.getElementById("record").disabled = false;
                document.getElementById("download").disabled = true;
                // document.documentElement.style.cursor = 'default';
            }

            function mute() {
                var remoteVideo = document.getElementById("remote-video");
                remoteVideo.muted = !remoteVideo.muted;
            }

            function pause() {
                var remoteVideo = document.getElementById("remote-video");
                if (remoteVideo.paused)
                    remoteVideo.play();
                else
                    remoteVideo.pause();
            }

            function fullscreen() {
                var remoteVideo = document.getElementById("remote-video");
                if (remoteVideo.requestFullScreen) {
                    remoteVideo.requestFullScreen();
                } else if (remoteVideo.webkitRequestFullScreen) {
                    remoteVideo.webkitRequestFullScreen();
                } else if (remoteVideo.mozRequestFullScreen) {
                    remoteVideo.mozRequestFullScreen();
                }
            }

            function handleDataAvailable(event) {
                //console.log(event);
                if (event.data && event.data.size > 0) {
                    recordedBlobs.push(event.data);
                }
            }

            function handleStop(event) {
                console.log('Recorder stopped: ', event);
                document.getElementById('record').innerHTML = '녹화 시작';
                recorder = null;
                var superBuffer = new Blob(recordedBlobs, {type: 'video/webm'});
                var recordedVideoElement = document.getElementById('recorded-video');
                recordedVideoElement.src = URL.createObjectURL(superBuffer);
            }

            function discard_recording() {
                var recordedVideoElement = document.getElementById('recorded-video');
                recordedVideoElement.srcObject = null;
                recordedVideoElement.src = '';
            }

            function stop_record() {
                if (recorder) {
                    recorder.stop();
                    console.log("recording stopped");
                }
            }

            function startRecording(stream) {
                recordedBlobs = [];
                var options = {mimeType: 'video/webm;codecs=vp9'};
                if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                    console.log(options.mimeType + ' is not Supported');
                    options = {mimeType: 'video/webm;codecs=vp8'};
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        console.log(options.mimeType + ' is not Supported');
                        options = {mimeType: 'video/webm;codecs=h264'};
                        if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                            console.log(options.mimeType + ' is not Supported');
                            options = {mimeType: 'video/webm'};
                            if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                                console.log(options.mimeType + ' is not Supported');
                                options = {mimeType: ''};
                            }
                        }
                    }
                }
                try {
                    recorder = new MediaRecorder(stream, options);
                } catch (e) {
                    console.error('Exception while creating MediaRecorder: ' + e);
                    alert('Exception while creating MediaRecorder: ' + e + '. mimeType: ' + options.mimeType);
                    return;
                }
                console.log('Created MediaRecorder', recorder, 'with options', options);
                //recorder.ignoreMutedMedia = true;
                recorder.onstop = handleStop;
                recorder.ondataavailable = handleDataAvailable;
                recorder.onwarning = function (e) {
                    console.log('Warning: ' + e);
                };
                recorder.start();
                console.log('MediaRecorder started', recorder);
            }

            function start_stop_record() {
                if (pc && !recorder) {
                    var streams = pc.getRemoteStreams();
                    if (streams.length) {
                        console.log("starting recording");
                        startRecording(streams[0]);
                        document.getElementById('record').innerHTML = '녹화 중지';
                        document.getElementById("download").disabled = true;
                    }
                } else {
                    document.getElementById("download").disabled = false;
                    stop_record();
                }
            }

            function download() {
                if (recordedBlobs !== undefined) {
                    var blob = new Blob(recordedBlobs, {type: 'video/webm'});
                    var url = window.URL.createObjectURL(blob);
                    var a = document.createElement('a');
                    a.style.display = 'none';
                    a.href = url;
                    a.download = 'video.mp4';
                    document.body.appendChild(a);
                    a.click();
                    setTimeout(function () {
                        document.body.removeChild(a);
                        window.URL.revokeObjectURL(url);
                    }, 100);
                }
            }

            function remote_hw_vcodec_selection() {
                if (!document.getElementById('remote_hw_vcodec').checked)
                    unselect_remote_hw_vcodec();
                else
                    select_remote_hw_vcodec();
            }

            function remote_hw_vcodec_format_selection() {
                if (document.getElementById('remote_hw_vcodec').checked)
                    remote_hw_vcodec_selection();
            }

            function select_remote_hw_vcodec() {
                document.getElementById('remote_hw_vcodec').checked = true;
                var vformat = document.getElementById('remote_vformat').value;
                switch (vformat) {
                    case '5':
                        document.getElementById('remote-video').style.width = "320px";
                        document.getElementById('remote-video').style.height = "240px";
                        break;
                    case '10':
                        document.getElementById('remote-video').style.width = "320px";
                        document.getElementById('remote-video').style.height = "240px";
                        break;
                    case '20':
                        document.getElementById('remote-video').style.width = "352px";
                        document.getElementById('remote-video').style.height = "288px";
                        break;
                    case '25':
                        document.getElementById('remote-video').style.width = "640px";
                        document.getElementById('remote-video').style.height = "480px";
                        break;
                    case '30':
                        document.getElementById('remote-video').style.width = "640px";
                        document.getElementById('remote-video').style.height = "480px";
                        break;
                    case '35':
                        document.getElementById('remote-video').style.width = "800px";
                        document.getElementById('remote-video').style.height = "480px";
                        break;
                    case '40':
                        document.getElementById('remote-video').style.width = "960px";
                        document.getElementById('remote-video').style.height = "720px";
                        break;
                    case '50':
                        document.getElementById('remote-video').style.width = "1024px";
                        document.getElementById('remote-video').style.height = "768px";
                        break;
                    case '55':
                        document.getElementById('remote-video').style.width = "1280px";
                        document.getElementById('remote-video').style.height = "720px";
                        break;
                    case '60':
                        document.getElementById('remote-video').style.width = "1280px";
                        document.getElementById('remote-video').style.height = "720px";
                        break;
                    case '63':
                        document.getElementById('remote-video').style.width = "1280px";
                        document.getElementById('remote-video').style.height = "720px";
                        break;
                    case '65':
                        document.getElementById('remote-video').style.width = "1280px";
                        document.getElementById('remote-video').style.height = "768px";
                        break;
                    case '70':
                        document.getElementById('remote-video').style.width = "1280px";
                        document.getElementById('remote-video').style.height = "768px";
                        break;
                    case '80':
                        document.getElementById('remote-video').style.width = "1280px";
                        document.getElementById('remote-video').style.height = "960px";
                        break;
                    case '90':
                        document.getElementById('remote-video').style.width = "1600px";
                        document.getElementById('remote-video').style.height = "768px";
                        break;
                    case '95':
                        document.getElementById('remote-video').style.width = "1640px";
                        document.getElementById('remote-video').style.height = "1232px";
                        break;
                    case '97':
                        document.getElementById('remote-video').style.width = "1640px";
                        document.getElementById('remote-video').style.height = "1232px";
                        break;
                    case '100':
                        document.getElementById('remote-video').style.width = "1920px";
                        document.getElementById('remote-video').style.height = "1080px";
                        break;
                    case '105':
                        document.getElementById('remote-video').style.width = "1920px";
                        document.getElementById('remote-video').style.height = "1080px";
                        break;
                    default:
                        document.getElementById('remote-video').style.width = "1280px";
                        document.getElementById('remote-video').style.height = "720px";
                }
                /*
                 // Disable video casting. Not supported at the moment with hw codecs.
                 var elements = document.getElementsByName('video_cast');
                 for(var i = 0; i < elements.length; i++) {
                 elements[i].checked = false;
                 }
                 */
            }

            function unselect_remote_hw_vcodec() {
                document.getElementById('remote_hw_vcodec').checked = false;
                document.getElementById('remote-video').style.width = "640px";
                document.getElementById('remote-video').style.height = "480px";
            }

            function singleselection(name, id) {
                var old = document.getElementById(id).checked;
                var elements = document.getElementsByName(name);
                for (var i = 0; i < elements.length; i++) {
                    elements[i].checked = false;
                }
                document.getElementById(id).checked = old ? true : false;
                /*
                 // Disable video hw codec. Not supported at the moment when casting.
                 if (name === 'video_cast') {
                 unselect_remote_hw_vcodec();
                 }
                 */
            }

            function send_message() {
                var msg = document.getElementById('datamessage').value;
                datachannel.send(msg);
                console.log("message sent: ", msg);
            }

            function create_localdatachannel() {
                if (pc && localdatachannel)
                    return;
                localdatachannel = pc.createDataChannel('datachannel');
                localdatachannel.onopen = function(event) {
                    if (localdatachannel.readyState === "open") {
                        localdatachannel.send("datachannel created!");
                    }
                };
                console.log("data channel created");
            }

            function close_localdatachannel() {
                if (localdatachannel) {
                    localdatachannel.close();
                    localdatachannel = null;
                }
                console.log("local data channel closed");
            }

            function handleOrientation(event) {
                var data = {
                    "do": {
                        "alpha": event.alpha.toFixed(1), // In degree in the range [0,360]
                        "beta": event.beta.toFixed(1), // In degree in the range [-180,180]
                        "gamma": event.gamma.toFixed(1), // In degree in the range [-90,90]
                        "absolute": event.absolute
                    }
                };
                if (datachannel)
                    datachannel.send(JSON.stringify(data));
            }

            function isGyronormPresent() {
                var url = "gyronorm.complete.min.js";
                var scripts = document.getElementsByTagName('script');
                for (var i = scripts.length; i--; ) {
                    if (scripts[i].src.indexOf(url) > -1)
                        return true;
                }
                return false;
            }

            function handleGyronorm(data) {
                // Process:
                // data.do.alpha    ( deviceorientation event alpha value )
                // data.do.beta     ( deviceorientation event beta value )
                // data.do.gamma    ( deviceorientation event gamma value )
                // data.do.absolute ( deviceorientation event absolute value )

                // data.dm.x        ( devicemotion event acceleration x value )
                // data.dm.y        ( devicemotion event acceleration y value )
                // data.dm.z        ( devicemotion event acceleration z value )

                // data.dm.gx       ( devicemotion event accelerationIncludingGravity x value )
                // data.dm.gy       ( devicemotion event accelerationIncludingGravity y value )
                // data.dm.gz       ( devicemotion event accelerationIncludingGravity z value )

                // data.dm.alpha    ( devicemotion event rotationRate alpha value )
                // data.dm.beta     ( devicemotion event rotationRate beta value )
                // data.dm.gamma    ( devicemotion event rotationRate gamma value )
                if (datachannel && document.getElementById('orientationsend').checked)
                    datachannel.send(JSON.stringify(data));
            }

            function orientationsend_selection() {
                if (document.getElementById('orientationsend').checked) {
                    if (isGyronormPresent()) {
                        console.log("gyronorm.js library found!");
                        if (gn) {
                            gn.setHeadDirection();
                            return;
                        }
                        try {
                            gn = new GyroNorm();
                        } catch (e) {
                            console.log(e);
                            document.getElementById('orientationsend').checked = false;
                            return;
                        }
                        var args = {
                            frequency: 60, // ( How often the object sends the values - milliseconds )
                            gravityNormalized: true, // ( If the gravity related values to be normalized )
                            orientationBase: GyroNorm.GAME, // ( Can be GyroNorm.GAME or GyroNorm.WORLD. gn.GAME returns orientation values with respect to the head direction of the device. gn.WORLD returns the orientation values with respect to the actual north direction of the world. )
                            decimalCount: 1, // ( How many digits after the decimal point will there be in the return values )
                            logger: null, // ( Function to be called to log messages from gyronorm.js )
                            screenAdjusted: false            // ( If set to true it will return screen adjusted values. )
                        };
                        gn.init(args).then(function () {
                            gn.start(handleGyronorm);
                            gn.setHeadDirection(); // only with gn.GAME
                        }).catch(function (e) {
                            console.log("DeviceOrientation or DeviceMotion might not be supported by this browser or device");
                        });
                    }
                    if (!gn) {
                        window.addEventListener('deviceorientation', handleOrientation, true);
                        console.log("gyronorm.js library not found, using defaults");
                    }
                } else {
                    if (!gn) {
                        window.removeEventListener('deviceorientation', handleOrientation, true);
                    }
                }
            }

            function getKeycodesArray(arr) {
                var newArr = new Array();
                for (var i = 0; i < arr.length; i++) {
                    if (typeof arr[i] == "number") {
                        newArr[newArr.length] = arr[i];
                    }
                }
                return newArr;
            }

            function convertKeycodes(arr) {
                var map = {
                    /*Space*/ 32: 57,
                    /*Enter*/13: 28,
                    /*Tab*/ 9: 15,
                    /*Esc*/27: 1,
                    /*Backspace*/8: 14,
                    /*Shift*/16: 42,
                    /*Control*/ 17: 29,
                    /*Alt Left*/ 18: 56,
                    /*Alt Right*/ 225: 100,
                    /*Caps Lock*/ 20: 58,
                    /*Num Lock*/ 144: 69,
                    /*a*/ 65: 30,
                    /*b*/ 66: 48,
                    /*c*/ 67: 46,
                    /*d*/ 68: 32,
                    /*e*/ 69: 18,
                    /*f*/ 70: 33,
                    /*g*/ 71: 34,
                    /*h*/ 72: 35,
                    /*i*/ 73: 23,
                    /*j*/ 74: 36,
                    /*k*/ 75: 37,
                    /*l*/ 76: 38,
                    /*m*/ 77: 50,
                    /*n*/ 78: 49,
                    /*o*/ 79: 24,
                    /*p*/ 80: 25,
                    /*q*/ 81: 16,
                    /*r*/ 82: 19,
                    /*s*/ 83: 31,
                    /*t*/ 84: 20,
                    /*u*/ 85: 22,
                    /*v*/ 86: 47,
                    /*w*/ 87: 17,
                    /*x*/ 88: 45,
                    /*y*/ 89: 21,
                    /*z*/ 90: 44,
                    /*1*/ 49: 2,
                    /*2*/ 50: 3,
                    /*3*/ 51: 4,
                    /*4*/ 52: 5,
                    /*5*/ 53: 6,
                    /*6*/ 54: 7,
                    /*7*/ 55: 8,
                    /*8*/ 56: 9,
                    /*9*/ 57: 10,
                    /*0*/ 48: 11,
                    /*; (firefox)*/ 59: 39,
                    /*; (chrome)*/ 186: 39,
                    /*=(firefox)*/ 61: 13,
                    /*=(chrome)*/ 187: 13,
                    /*,*/ 188: 51,
                    /*-(minus in firefox)*/ 173: 12,
                    /*-(dash in chrome)*/ 189: 12,
                    /*.*/ 190: 52,
                    /*/*/ 191: 53,
                    /*`*/ 192: 41,
                    /*{*/ 219: 26,
                    /*\*/ 220: 43,
                    /*}*/ 221: 27,
                    /*'*/ 222: 40,
                    /*left-arrow*/ 37: 105,
                    /*up-arrow*/ 38: 103,
                    /*right-arrow*/ 39: 106,
                    /*down-arrow*/ 40: 108,
                    /*Insert*/ 45: 110,
                    /*Delete*/ 46: 111,
                    /*Home*/ 36: 102,
                    /*End*/ 35: 107,
                    /*Page Up*/ 33: 104,
                    /*Page Down*/ 34: 109,
                    /*F1 */ 112: 59,
                    /*F2 */ 113: 60,
                    /*F3 */ 114: 61,
                    /*F4 */ 115: 62,
                    /*F5 */ 116: 63,
                    /*F6 */ 117: 64,
                    /*F7 */ 118: 65,
                    /*F8 */ 119: 66,
                    /*F9 */ 120: 67,
                    /*F10 */ 121: 68,
                    /*F11 */ 122: 87,
                    /*F12 */ 123: 88,
                    /*. Del*/ 110: 83,
                    /*0 Ins*/ 96: 82,
                    /*1 End*/ 97: 79,
                    /*2 down-arrow*/ 98: 80,
                    /*3 Pg Dn*/ 99: 81,
                    /*4 left-arrow*/ 100: 75,
                    /*5*/ 101: 76,
                    /*6 right-arrow*/ 102: 77,
                    /*7 Home*/ 	103: 71,
                    /*8 up-arrow*/ 104: 72,
                    /*9 Pg Up*/ 105: 73,
                    /*+*/ 107: 78,
                    /*-*/ 109: 74,
                    /***/ 106: 55,
                    /*/*/ 111: 98,
                    /*Keypad Enter*/ 13: 28
                };
                var convertedKeys = [];
                arr.forEach(function (a) {
                    if (map[a] !== undefined)
                        convertedKeys.push(map[a]);
                    //else
                    //    convertedKeys.push(a);
                });
                return convertedKeys;
            }

            function convertCharCode(ch) {
                var arr = [];
                if (ch >= 48 && ch <= 57) { /* 0..9 */
                    arr[0] = ch;
                    arr = convertKeycodes(arr);
                } else if (ch >= 97 && ch <= 122) { /* a..z */
                    arr[0] = ch - 32;
                    arr = convertKeycodes(arr);
                } else if (ch >= 65 && ch <= 90) { /* A..Z */
                    arr[0] = 16;
                    arr[1] = ch;
                    arr = convertKeycodes(arr);
                } else if (ch == 46) { // .
                    arr[0] = 52;
                } else if (ch == 33) { // !
                    arr[0] = 42;
                    arr[1] = 2;
                } else if (ch == 63) { // ?
                    arr[0] = 42;
                    arr[1] = 53;
                } else if (ch == 44) { // ,
                    arr[0] = 51;
                } else if (ch == 34) { // "
                    arr[0] = 42;
                    arr[1] = 40;
                } else if (ch == 39) { // '
                    arr[0] = 40;
                } else if (ch == 58) { // :
                    arr[0] = 42;
                    arr[1] = 39;
                } else if (ch == 40) { // (
                    arr[0] = 42;
                    arr[1] = 10;
                } else if (ch == 41) { // )
                    arr[0] = 42;
                    arr[1] = 11;
                } else if (ch == 126) { // ~
                    arr[0] = 42;
                    arr[1] = 41;
                } else if (ch == 42) { // *
                    arr[0] = 42;
                    arr[1] = 9;
                } else if (ch == 45) { // -
                    arr[0] = 12;
                } else if (ch == 47) { // /
                    arr[0] = 53;
                } else if (ch == 64) { // @
                    arr[0] = 42;
                    arr[1] = 3;
                } else if (ch == 95) { // _
                    arr[0] = 42;
                    arr[1] = 12;
                }
                return arr;
            }

            function toKeyCode() {
                var getCharCode = function (str) {
                    return str.charCodeAt(str.length - 1);
                };
                var cc = getCharCode(this.value);
                document.getElementById("datamessage").removeEventListener("keyup", toKeyCode);
                this.value = "";
                var keysArray = convertCharCode(cc);
                if (datachannel && document.getElementById('keypresssend').checked && keysArray.length) {
                    var keycodes = {
                        keycodes: keysArray
                    };
                    datachannel.send(JSON.stringify(keycodes));
                }
            }
            ;

            function keydown(e) {
                if (e.keyCode == 0 || e.keyCode == 229) { // on mobile
                    return;
                }
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                keys[e.keyCode] = e.keyCode;
                for (var i = keys.length; i >= 0; i--) {
                    if (keys[i] !== 16 && keys[i] !== 17 && keys[i] !== 18 && keys[i] !== 225 && keys[i] !== e.keyCode)
                        keys[i] = false;
                }
                var keysArray = convertKeycodes(getKeycodesArray(keys));
                if (datachannel && document.getElementById('keypresssend').checked && keysArray.length) {
                    var keycodes = {
                        keycodes: keysArray
                    };
                    datachannel.send(JSON.stringify(keycodes));
                }
            }
            ;

            function keyup(e) {
                if (e.keyCode == 0 || e.keyCode == 229) { // on mobile
                    document.getElementById("datamessage").addEventListener("keyup", toKeyCode);
                    return;
                }
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                keys[e.keyCode] = false;
            }
            ;

            function keypresssend_selection() {
                if (document.getElementById('keypresssend').checked) {
                    window.addEventListener('keydown', keydown, true);
                    window.addEventListener('keyup', keyup, true);
                } else {
                    keys = [];
                    window.removeEventListener('keydown', keydown, true);
                    window.removeEventListener('keyup', keyup, true);
                }
            }

            function trickleice_selection() {
                if (document.getElementById('trickleice').value === "false") {
                    trickle_ice = false;
                } else if (document.getElementById('trickleice').value === "true") {
                    trickle_ice = true;
                } else {
                    trickle_ice = null;
                }
                return trickle_ice;
            }

            window.onload = function () {
                if (window.MediaRecorder === undefined) {
                    document.getElementById('record').disabled = true;
                }
                if (false) {
                    start();
                }
            };

            window.onbeforeunload = function () {
                if (ws) {
                    ws.onclose = function () {}; // disable onclose handler first
                    stop();
                }
            };
    </script>
	<script src="https://rawgit.com/dorukeker/gyronorm.js/master/dist/gyronorm.complete.min.js"></script>
	<script src="resources/assets/js/jquery.min.js"></script>
	<script src="resources/assets/js/skel.min.js"></script>
	<script src="resources/assets/js/util.js"></script>
	<script src="resources/assets/js/main.js"></script>
	
</head>
<body>

	<!-- Wrapper -->
	<div id="wrapper">

		<!-- Header -->
		<header id="header">
			<div class="logo">

				<img src="resources/images/house.png" class="icon">

			</div>
			<div class="content">
				<div class="inner">
				<c:choose>
					<c:when test="${empty userID}">
						<h1>SMART HOME CONTROLL</h1>
						<p>원격제어 시스템을 통하여 원격으로 제어하자! </p>
					</c:when>
					<c:otherwise>
						<h1>${userID}님 어서오세요.</h1>	
						<h1>SMART HOME CONTROLL</h1>
						<p>원격제어 시스템을 통하여 원격으로 제어하자! </p>
					</c:otherwise>	
				</c:choose>	
				</div>
			</div>
			<!-- 메뉴바 클릭시 article 로 이동하여 해당 article 페이지 활성화 -->
			<nav>
				<ul>
				<c:choose>
					<c:when test="${empty userID}">
						<li><a href="#">거실</a></li>
						<li><a href="#">주방</a></li>
						<li><a href="#">화장실</a></li>
						<li><a href="#">CCTV</a></li>
					</c:when>
					<c:otherwise>
						<li><a href="#intro">거실</a></li>
						<li><a href="#work">주방</a></li>
						<li><a href="#about">화장실</a></li>
						<li><a href="#contact">CCTV</a></li>
					</c:otherwise>
				</c:choose>	
				</ul>
			</nav>
		</header>

		<!-- Main -->
		<div id="main">

			<!-- Intro 거실 제어 페이지 -->
			<article id="intro">
				<h2 class="major">거실</h2>
				<span class="image main"><img src="resources/images/pic01.jpg" /></span>
				<div class="field half first">
					<label>거실등1</label>
					<input type="button" value="ON" />
					<input type="button" value="OFF" />
				</div>
				<div class="field half">
					<label>거실등2</label>
					<input type="button" value="ON" />
					<input type="button" value="OFF" />
				</div>
				<div class="field half first">
					<label>난방기 가동(온도입력)</label>
					<input type="text" name="temp" maxlength="2" />
					<input type="button" value="ON" />
					<input type="button" value="OFF" />
				</div>
			</article>
			
			<!-- Work 주방제어 페이지 -->
			<article id="work">
				<h2 class="major">주방</h2>
				<span class="image main"><img src="resources/images/pic02.jpg" alt="" /></span>
				<div class="field half first">
					<label>주방등</label>
					<input type="button" value="ON" />
					<input type="button" value="OFF" />
				</div>

				<div class="field half">
					<label>주방등2</label>
					<input type="button" value="ON" />
					<input type="button" value="OFF" />
				</div>
			</article>

			<!-- About 화장실제어 페이지 -->
			<article id="about">
				<h2 class="major">화장실</h2>
				<span class="image main"><img src="resources/images/pic03.jpg" /></span>
				<div class="field half first">
					<label>화장실등</label>
					<input type="button" value="ON" />
					<input type="button" value="OFF" />
				</div>
				<div class="field half">
					<label>환풍기 가동</label>
					<input type="button" value="ON" />
					<input type="button" value="OFF" />
				</div>
			</article>

			<!-- Contact CCTV 제어 페이지 -->
			<article id="contact">
				<h2 class="major">CCTV</h2>
				<!-- 이부분에 iframe 태그를 써서 uv4l의 스트리밍 영상 가져올 예정. -->
				<div>
					<video id="remote-video" autoplay="" width="100%" height="60%">영상준비중</video>
				</div>
				<br>
				<input type="hidden" id="signalling_server" value="172.30.1.43:8080">
			    <input type="hidden" id="remote_vformat" value="60">
			    <input type="hidden" id="local-video" value="">
			    <input type="hidden" id="ice_servers" value="">
			    <input type="hidden" id="trickleice" value="true">
			  	    <div class="field half first">
					<label>CCTV 작업</label>
					<button id="start" onclick="start();">영상호출</button>
			   		<button id="stop" onclick="stop();" disabled="">영상끊기</button>
				</div>
				<div class="field half">
					<label>CCTV 녹화</label>
					<button type="button" id="record" onclick="start_stop_record();" title="start or stop recording audio/video" disabled="">녹화시작</button>
			   				<button type="button" id="download" onclick="download();" title="save recorded audio/video" disabled="">녹화저장</button>
				</div>
			</article>

			<!-- login 로그인 페이지 -->
			<article id="login">
				<h2 class="major">로그인</h2>
				<form method="post" action="/SmartHome/login">
					<div class="field half first">
						<label for="ID">아이디</label>
						<input type="text" name="userID" id="ID" />
					</div>
					<div class="field half">
						<label for="Password">비밀번호</label>
						<input type="Password" name="userPW" id="PassWord" />
					</div>

					<ul class="actions">
						<li><input type="submit" value="로그인" class="special" /></li>
						
					</ul>
				</form>
			</article>

			<!-- join 회원가입 페이지  -->
			<article id="JOIN">
				<h2 class="major">회원가입</h2>
				<form method="post" action="/SmartHome/join">
					<div class="field">
						<label for="name">이름</label>
						<input type="text" name="userName" id="name" required />
					</div>
					<div class="field half first">
						<label for="userID">아이디</label>
						<input type="text" name="userID" id="userID" required />
					</div>
					<div class="field half">
						<label for="PassWord">비밀번호</label>
						<input type="Password" name="userPW" id="Password" required />
					</div>
					<div class="field">
						<label for="email">이메일주소</label>
						<input type="email" name="userEmail" id="email" style="background: transparent;" required />
					</div>

					<ul class="actions" style="text-align:right">
						<li><input type="reset" value="다시입력" /></li>
						<li><input type="submit" value="회원가입" class="special" /></li>
					</ul>
				</form>
			</article>
			
			<!-- userView 회원정보 페이지  -->
			<article id="userView">
				<h2 class="major">회원정보</h2>
				<form method="post" action="/SmartHome/update">
					<div class="field half first">
						<label for="name">이름</label>
						<label>${userName}</label>
					</div>
					<div class="field half">
						<label for="JoinDate">가입 일시</label>
						<label>${userJoinDate}</label>
					</div>
					<div class="field half first">
						<label for="userID">아이디</label>
						<label>${userID}</label>
					</div>
					<div class="field half">
						<label for="PassWord">비밀번호</label>
						<input type="Password" name="userPW" id="Password" required />
					</div>
					<div class="field">
						<label for="email">이메일주소</label>
						<input type="email" name="userEmail" id="email" value="${userEmain}"style="background: transparent;" required />
					</div>
					<input type="hidden" name="userID" id="userID" value="${userID}" />
					<ul class="actions" style="text-align:right">
						<li><input type="button" value="회원탈퇴" onclick="location.href='/SmartHome/userDelete?userID=${userID}'" /></li>
						<li><input type="submit" value="수정하기" class="special" /></li>
					</ul>
				</form>
			</article>	
			
			
			<%-- <!-- 문의하기 페이지 -->
			<article id="Account">
				<h2 class="major">문의하기</h2>
				<form method="post" action="/join">
					<div class="field">
						<label>아이디</label>
						<input type="button" style="width:48%;" value ="${userID}" />
					</div>
					<div class="field half first">
						<label for="name">이름</label>
						<input type="text" name="userName" id="name" required />
					</div>
					<div class="field half">
						<label for="email">이메일주소</label>
						<input type="email" name="userEmail" id="email" style="background: transparent;" value ="" required />
					</div>
					<div class="field">
						<label for="email">문의 내용</label>
						<textarea name="content" rows="10" ></textarea>
					</div>
					<ul class="actions" style="text-align:right">
						<li><input type="submit" value="문의하기" class="special" /></li>
					</ul>
				</form>
			</article> --%>
		</div>

		<!-- Footer -->
		<footer id="footer">
			<table border="1" style="text-align:center;" class="table_50">
				<tr>
				<c:choose>
					<c:when test="${empty userID}">
						<td><a href="#login">로그인</a></td>
						<td><a href="#JOIN">회원가입</a></td>
					</c:when>
					<c:when test="${userID == 'admin'}">
						<td style="width:30%"><a href="/SmartHome/logout">로그아웃</a></td>
						<td style="width:30%"><a href="/SmartHome/userAccount">회원관리</a></td>
						<td style="width:30%"><a href="/SmartHome/userView">회원정보</a></td>
					</c:when>
					<c:otherwise>
						<td><a href="/SmartHome/logout">로그아웃</a></td>
						<td><a href="/SmartHome/userView">회원정보</a></td>
					</c:otherwise>
				</c:choose>	
				</tr>
			</table>
		</footer>

	</div>
	<div id="bg"></div>


</body>
</html>

