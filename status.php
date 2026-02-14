<?php
$cfgFile = $settings['configDirectory'] . '/plugin.fpp-AirPlayMatrix.json';
$defaultConfig = array(
    'enabled' => true,
    'airplay_name' => 'FPP AirPlay Matrix',
    'model_name' => 'Matrix',
    'fps' => 20,
    'flip_x' => false,
    'flip_y' => false,
    'uxplay_extra_args' => ''
);

if (file_exists($cfgFile)) {
    $json = json_decode(file_get_contents($cfgFile), true);
    if (is_array($json)) {
        $defaultConfig = array_merge($defaultConfig, $json);
    }
}
?>

<div id="global" class="settings">
  <h2>AirPlay Video to Matrix</h2>
  <div class="container-fluid settingsTable settingsGroupTable">
    <div class="row"><div class="col-md"><b>Daemon Status:</b> <span id="am-status">Checking...</span></div></div>
    <div class="row"><div class="col-md" id="am-status-detail"></div></div>

    <div class="row"><div class="col-auto"><label><input type="checkbox" id="cfg-enabled"> Enabled</label></div></div>
    <div class="row"><div class="col-auto">AirPlay Receiver Name:</div><div class="col-auto"><input type="text" id="cfg-airplay-name" size="30" maxlength="64"></div></div>
    <div class="row"><div class="col-auto">Matrix Model Name:</div><div class="col-auto"><input type="text" id="cfg-model-name" size="20" maxlength="64"></div><div class="col-auto"><button class="buttons" onclick="loadModels(); return false;">Load Models</button></div></div>
    <div class="row"><div class="col-auto">Available Models:</div><div class="col-auto" id="am-models">(not loaded)</div></div>

    <div class="row"><div class="col-auto">Output FPS:</div><div class="col-auto"><input type="number" id="cfg-fps" min="5" max="60" step="1"></div></div>
    <div class="row"><div class="col-auto"><label><input type="checkbox" id="cfg-flip-x"> Flip Horizontally</label></div></div>
    <div class="row"><div class="col-auto"><label><input type="checkbox" id="cfg-flip-y"> Flip Vertically</label></div></div>
    <div class="row"><div class="col-auto">Extra UxPlay Args:</div><div class="col-auto"><input type="text" id="cfg-uxplay-extra-args" size="60" maxlength="256"></div></div>

    <div class="row" style="margin-top: 12px;">
      <div class="col-auto">
        <button class="buttons" onclick="saveConfig(); return false;">Save Config</button>
        <button class="buttons" onclick="pluginAction('start'); return false;">Start</button>
        <button class="buttons" onclick="pluginAction('stop'); return false;">Stop</button>
        <button class="buttons" onclick="pluginAction('restart'); return false;">Restart</button>
        <button class="buttons" onclick="refreshStatus(); return false;">Refresh Status</button>
      </div>
    </div>
  </div>
</div>

<script>
var defaultConfig = <?php echo json_encode($defaultConfig, JSON_PRETTY_PRINT); ?>;
var configFileApi = 'api/configfile/plugin.fpp-AirPlayMatrix.json';

function applyConfig(cfg) {
  $('#cfg-enabled').prop('checked', !!cfg.enabled);
  $('#cfg-airplay-name').val(cfg.airplay_name || 'FPP AirPlay Matrix');
  $('#cfg-model-name').val(cfg.model_name || 'Matrix');
  $('#cfg-fps').val(cfg.fps || 20);
  $('#cfg-flip-x').prop('checked', !!cfg.flip_x);
  $('#cfg-flip-y').prop('checked', !!cfg.flip_y);
  $('#cfg-uxplay-extra-args').val(cfg.uxplay_extra_args || '');
}

function readConfigFromForm() {
  var fps = parseInt($('#cfg-fps').val(), 10);
  if (isNaN(fps)) {
    fps = 20;
  }

  var airplayName = ($('#cfg-airplay-name').val() || '').trim();
  if (!airplayName) {
    airplayName = 'FPP AirPlay Matrix';
  }

  var modelName = ($('#cfg-model-name').val() || '').trim();
  if (!modelName) {
    modelName = 'Matrix';
  }

  return {
    enabled: $('#cfg-enabled').is(':checked'),
    airplay_name: airplayName,
    model_name: modelName,
    fps: fps,
    flip_x: $('#cfg-flip-x').is(':checked'),
    flip_y: $('#cfg-flip-y').is(':checked'),
    uxplay_extra_args: ($('#cfg-uxplay-extra-args').val() || '').trim()
  };
}

function loadConfig() {
  $.get(configFileApi, function(data) {
    if (data && typeof data === 'object') {
      defaultConfig = $.extend({}, defaultConfig, data);
    }
    applyConfig(defaultConfig);
  }).fail(function() {
    applyConfig(defaultConfig);
  });
}

function saveConfig() {
  var cfg = readConfigFromForm();
  $.ajax({
    type: 'POST',
    url: configFileApi,
    dataType: 'json',
    data: JSON.stringify(cfg),
    processData: false,
    contentType: 'application/json',
    success: function() {
      $.jGrowl('Config saved. Restart plugin to apply changes immediately.', { themeState: 'success' });
      SetRestartFlag(2);
    },
    error: function(xhr) {
      $.jGrowl('Failed to save config: ' + xhr.responseText, { themeState: 'danger' });
    }
  });
}

function pluginAction(action) {
  $.ajax({
    type: 'POST',
    url: 'api/plugin/fpp-AirPlayMatrix/' + action,
    dataType: 'json',
    contentType: 'application/json',
    data: '{}',
    success: function(data) {
      if (data && data.message) {
        $.jGrowl(data.message, { themeState: data.ok ? 'success' : 'danger' });
      }
      setTimeout(refreshStatus, 600);
    },
    error: function(xhr) {
      $.jGrowl('Action failed: ' + xhr.responseText, { themeState: 'danger' });
      setTimeout(refreshStatus, 600);
    }
  });
}

function refreshStatus() {
  $.get('api/plugin/fpp-AirPlayMatrix/status', function(data) {
    $('#am-status').text(data.running ? 'Running' : 'Stopped');

    var detail = [];
    if (data.pid) {
      detail.push('PID: ' + data.pid);
    }
    if (data.model_name) {
      detail.push('Model: ' + data.model_name);
    }
    if (data.airplay_name) {
      detail.push('AirPlay Name: ' + data.airplay_name);
    }
    if (data.message) {
      detail.push(data.message);
    }
    $('#am-status-detail').text(detail.join(' | '));
  }).fail(function(xhr) {
    $('#am-status').text('Unknown');
    $('#am-status-detail').text('Unable to read status: ' + xhr.responseText);
  });
}

function loadModels() {
  $.get('api/overlays/models', function(data) {
    if (!Array.isArray(data) || data.length === 0) {
      $('#am-models').text('(none)');
      return;
    }
    var names = data.map(function(m) { return m.Name; });
    $('#am-models').text(names.join(', '));
  }).fail(function() {
    $('#am-models').text('(error loading models)');
  });
}

$(document).ready(function() {
  loadConfig();
  loadModels();
  refreshStatus();
});
</script>
