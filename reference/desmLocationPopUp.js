===== JS https://desm.doosanenerbility.com/resources/scripts/popUp/desmLocationPopUp.js?rv=bJ5Z2O2Jp5 =====
HTTP 200 · text/javascript · 10697 ký tự

var locationCanvas = null;
var locationCtx = null;
var locationSelPath = null;
var locationSelPathId = "";
var locationSelPathOver = null;
var locationAreaList = [];
var locationEditSeldtlInfo = null;

var v_desm_location_callback = null;
var v_desm_location_param;

function initDesmLocationPopUp(param , callback) {

	v_desm_location_callback = callback;
    v_desm_location_param = param;

	$('#dlgDesmLocation').on('shown.bs.modal', function () {
		$('#dlgDesmLocation').click();
	});

	$('#dlgDesmLocation').on('hidden.bs.modal', function () {
	  	closeDesmLocationPopUp();
	});

	$('#dlgDesmLocation').modal('show');


    initDesmLocationPopUpCode();
}

function initDesmLocationPopUpCode() {

	initDesmLocationPopUpControls();
}


function initDesmLocationPopUpControls() {

	locationCanvas = document.getElementById("canvasDlgDesmLocation");
	locationCtx = locationCanvas.getContext('2d');

	var sX,sY,cX,cY;

	var canvasX = $(locationCanvas).offset().left;
	var canvasY = $(locationCanvas).offset().top;

	$('#btnDlgDesmLocationSearch').click(function () { btnDlgDesmLocationSearchClick(); return false; });
	$('#selDlgDesmLocationMapName').change(function () { selDlgDesmLocationMapNameChange(); return false; });

	$("#canvasDlgDesmLocation").mousemove(function(e){
		canvasX = $(locationCanvas).offset().left;
		canvasY = $(locationCanvas).offset().top;
	  var x=parseInt(e.clientX-canvasX);
	  var y=parseInt(e.clientY-canvasY);

		if(locationSelPathOver != null) {
			locationSelPathOver = null;
			locationCtx.clearRect(0, 0, locationCanvas.width, locationCanvas.height);
			setLocationMapArea();
		}
		locationIsPositionOver(x, y);
	});

	$("#canvasDlgDesmLocation").click(function(e){
		canvasX = $(locationCanvas).offset().left;
		canvasY = $(locationCanvas).offset().top;
		  var x = parseInt(e.clientX-canvasX);
		  var y = parseInt(e.clientY-canvasY);

		if(locationSelPath != null) {
			locationSelPath = null;
			locationSelPathId = "";
			locationCtx.clearRect(0, 0, locationCanvas.width, locationCanvas.height);
			setLocationMapArea();
		}
		locationIsPosition(x, y);


	});


	initDefailProject(function (list) {

		if(list.length > 0) {
			$('#txtDlgDesmLocationProjectCode').val(list[0]["SEGMENT1"]);
			$('#txtDlgDesmLocationProjectName').val(list[0]["NAME"]);

			initDesmLocationCombo();
		}
	});
}

function locationIsPosition(x, y) {
	var path = getLocationPath(x, y);

	if(path == null) {
	  	locationSelPath = null;
	  	locationSelPathId = "";
	}
	else {
		locationCtx.globalAlpha = 1;
		locationCtx.strokeStyle = "#ff0000";
		locationCtx.lineWidth = 3;
		locationSelPath = path;
		locationCtx.stroke(path);

		locationSelPathId = getLocationPathId(x, y);

		locationSave();
	}
}
function locationSave() {
	var insertList = v_desm_location_param.selectList;
	var list = JSON.stringify(insertList);

	$.ajax({
		url: "/saveDesmLocationCheck.do",
		data: {"list" : list, "MAP_MST_ID" : $('#selDlgDesmLocationMapName').val(), "MAP_DTL_ID" : locationSelPathId},
		success: function (data, textStatus, jqXHR) {
			var title = $('#alertSave').val();

			if (data.LOCATION_DIFF != null) {
				title = $('#alertLocationDuplication').val();
			}

			confirm_modal("", title, null, function (callobj, result) {
				if(result) {

					$.ajax({
						url: "/saveDesmLocation.do",
						data: {"list" : list, "MAP_MST_ID" : $('#selDlgDesmLocationMapName').val(), "MAP_DTL_ID" : locationSelPathId},
						success: function (data, textStatus, jqXHR) {
							console.log(data);
							if (data.error != null) {
								if(data.error == "qtyCheckErr") {
									//var msg = $('#alertLocationSaveQtyZero').val() + " [Package No. : " + data.PACKAGE_NO + "]";
									var msg = $('#alertLocationSaveQtyZero').val() + " " + $('#gridPackageno').val() + " : " + data.PACKAGE_NO + "]";
									alert_fail(msg);
								}else {
									alert_fail($('#alertMapSaveDetailErr').val());
								}

							}
							else {
								alert_success($('#alertSuccess').val());

								if(v_desm_location_callback) {
									v_desm_location_callback("save-item", null);
								}

								$('#dlgDesmLocation').modal('hide');
							}
						}
					});
				}
			});
        }
    });

}

function getLocationPathId(x, y) {
	var path;

	locationCtx.lineWidth = 2;
	locationCtx.strokeStyle = "blue";
	locationCtx.globalAlpha = 0;

	for(var i = 0; i < locationAreaList.length; i++) {
  		var locationAreaRow = locationAreaList[i];
  		path = new Path2D();

	  	if(locationAreaRow.MAP_TYPE == "RECT") {
	  		var ps = locationAreaRow.MAP_POSITION;
	  		var psArr = ps.split(",");
	  		path.rect(psArr[0], psArr[1], psArr[2], psArr[3]);
	  	}
	  	else if(locationAreaRow.MAP_TYPE == "LINE") {
	  		var ps = locationAreaRow.MAP_POSITION;
	  		var psArr = ps.split(";");

	  		for(var j = 0; j < psArr.length; j++){
	  			var ps1 = psArr[j];
	  			var psArr1 = ps1.split(",");

	  			if(j == 0) {
	  				path.moveTo(psArr1[0], psArr1[1]);
	  			}
			  	else {
			  		path.lineTo(psArr1[0], psArr1[1]);
			  	}
	  		}
	  	}

		locationCtx.stroke(path);

		if(locationCtx.isPointInPath(path, x, y)) {

			return locationAreaRow.MAP_DTL_ID;
		}
	}

	return "";
}

function locationIsPositionOver(x, y) {
	var path = getLocationPath(x, y);

	if(locationSelPath != null){
		locationCtx.globalAlpha = 1;
		locationCtx.strokeStyle = "#ff0000";
		locationCtx.lineWidth = 3;
		locationCtx.stroke(locationSelPath);
	}

	if(path == null) {
	  	$("#canvasDlgDesmLocation").css("cursor", "");
	  	locationSelPathOver = null;
	}
	else {
  		locationSelPathOver = path;

  		locationCtx.globalAlpha = 0.5;
		locationCtx.fillStyle = "#0099FF";
		locationCtx.fill(path);

		$("#canvasDlgDesmLocation").css("cursor", "pointer");
	}
}

function getLocationPath(x, y) {
	var path;

	locationCtx.lineWidth = 2;
	locationCtx.strokeStyle = "blue";
	locationCtx.globalAlpha = 0;

	for(var i = 0; i < locationAreaList.length; i++) {
  		var locationAreaRow = locationAreaList[i];
  		path = new Path2D();

	  	if(locationAreaRow.MAP_TYPE == "RECT") {
	  		var ps = locationAreaRow.MAP_POSITION;
	  		var psArr = ps.split(",");
	  		path.rect(psArr[0], psArr[1], psArr[2], psArr[3]);
	  	}
	  	else if(locationAreaRow.MAP_TYPE == "LINE") {
	  		var ps = locationAreaRow.MAP_POSITION;
	  		var psArr = ps.split(";");

	  		for(var j = 0; j < psArr.length; j++){
	  			var ps1 = psArr[j];
	  			var psArr1 = ps1.split(",");

	  			if(j == 0) {
	  				path.moveTo(psArr1[0], psArr1[1]);
	  			}
			  	else {
			  		path.lineTo(psArr1[0], psArr1[1]);
			  	}
	  		}
	  	}

		locationCtx.stroke(path);

		if(locationCtx.isPointInPath(path, x, y)) {
			return path;
		}
	}

	return null;
}

function btnDlgDesmLocationSearchClick() {

	locationSelPath = null;
	locationSelPathId = "";
	locationSelPathOver = null;


	var paramData = {"PROJECT_NO" : $('#txtDlgDesmLocationProjectCode').val(), "MAP_MST_ID" : $("#selDlgDesmLocationMapName").val() };

	$.ajax({
		url: "/getDesmMapInfoList.do",
		data: paramData,
		success: function (data, textStatus, jqXHR) {

			var mstList = data.results.mstInfo;

			if(mstList.length < 1) {
				$("#canvasDlgDesmLocation").css("background-image", "");
				locationCtx.clearRect(0, 0, locationCanvas.width, locationCanvas.height);
			}
			else {
				var img_path = "url('" + mstList[0]["MAP_PATH"] + "')";
				$("#canvasDlgDesmLocation").css("background-image", img_path);
			}

			locationAreaList = data.results.dtlInfo;

			setLocationMapArea();
	    }
	});
}

function setLocationMapArea() {
	locationCtx.clearRect(0, 0, locationCanvas.width, locationCanvas.height);

	locationCtx.lineWidth = 2;
	locationCtx.strokeStyle = "blue";
	locationCtx.globalAlpha = 0;

	locationCtx.beginPath();

	for(var i = 0; i < locationAreaList.length; i++) {
  		var locationAreaRow = locationAreaList[i];

	  	if(locationAreaRow.MAP_TYPE == "RECT") {
	  		var ps = locationAreaRow.MAP_POSITION;
	  		var psArr = ps.split(",");
	  		locationCtx.rect(psArr[0], psArr[1], psArr[2], psArr[3]);
	  	}
	  	else if(locationAreaRow.MAP_TYPE == "LINE") {
	  		var ps = locationAreaRow.MAP_POSITION;
	  		var psArr = ps.split(";");

	  		for(var j = 0; j < psArr.length; j++){
	  			var ps1 = psArr[j];
	  			var psArr1 = ps1.split(",");

	  			if(j == 0) {
	  				locationCtx.moveTo(psArr1[0], psArr1[1]);
	  			}
			  	else {
			  		locationCtx.lineTo(psArr1[0], psArr1[1]);
			  	}
	  		}
	  	}
	}
	locationCtx.stroke();

	locationCtx.closePath();

	if(locationEditSeldtlInfo != null) {
		setLocationSelMapArea();
	}
}

function setLocationSelMapArea() {
	var path;

	locationCtx.globalAlpha = 1;
	locationCtx.strokeStyle = "#ff0000";
	locationCtx.lineWidth = 3;

	var locationAreaRow = Object.assign({}, locationEditSeldtlInfo[0]);
	path = new Path2D();

  	if(locationAreaRow.MAP_TYPE == "RECT") {
  		var ps = locationAreaRow.MAP_POSITION;
  		var psArr = ps.split(",");
  		path.rect(psArr[0], psArr[1], psArr[2], psArr[3]);
  	}
  	else if(locationAreaRow.MAP_TYPE == "LINE") {
  		var ps = locationAreaRow.MAP_POSITION;
  		var psArr = ps.split(";");

  		for(var j = 0; j < psArr.length; j++){
  			var ps1 = psArr[j];
  			var psArr1 = ps1.split(",");

  			if(j == 0) {
  				path.moveTo(psArr1[0], psArr1[1]);
  			}
		  	else {
		  		path.lineTo(psArr1[0], psArr1[1]);
		  	}
  		}
  	}

  	locationCtx.stroke(path);
	locationSelPath = path;
	locationSelPathId  = locationAreaRow.MAP_DTL_ID;
	locationEditSeldtlInfo = null;
}

function selDlgDesmLocationMapNameChange() {
	$('#btnDlgDesmLocationSearch').click();
}

function initDesmLocationCombo() {

	$("#canvasDlgDesmLocation").css("background-image", "");
	var paramData = {"PROJECT_NO" : $('#txtDlgDesmLocationProjectCode').val()};

	$.ajax({
		url: "/getDesmMapCreationList.do",
		data: paramData,
		success: function (data, textStatus, jqXHR) {

			var results = data.results;
			$("#selDlgDesmLocationMapName option").remove();

			$.each(results, function (index, entry) {
				$("#selDlgDesmLocationMapName").append("<option value='" + entry["MAP_MST_ID"] + "'>" + entry["MAP_NAME"] + "</option>");
			});

			if(v_desm_location_param.S_TYPE != null && v_desm_location_param.S_TYPE == "EDIT") {
				selectMap();
			}
			else
			{
				$('#btnDlgDesmLocationSearch').click();
			}


	    }
	});
}

function selectMap() {
	$.ajax({
		url: "/getDesmMapSearchInfoList.do",
		data: v_desm_location_param.selectList[0],
		success: function (data, textStatus, jqXHR) {

			var mstList = data.results.mstInfo;
			locationEditSeldtlInfo  = data.results.dtlInfo;
			console.log("data", data);

			$("#selDlgDesmLocationMapName").val(mstList[0].MAP_MST_ID);
			$('#btnDlgDesmLocationSearch').click();

	    }
	});
}

function closeDesmLocationPopUp() {

}



