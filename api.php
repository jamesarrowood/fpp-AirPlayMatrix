<?php

function getEndpointsfppAirPlayMatrix() {
    $result = array();

    $result[] = array(
        'method' => 'GET',
        'endpoint' => 'status',
        'callback' => 'fppAirPlayMatrixStatus'
    );

    $result[] = array(
        'method' => 'POST',
        'endpoint' => 'start',
        'callback' => 'fppAirPlayMatrixStart'
    );

    $result[] = array(
        'method' => 'POST',
        'endpoint' => 'stop',
        'callback' => 'fppAirPlayMatrixStop'
    );

    $result[] = array(
        'method' => 'POST',
        'endpoint' => 'restart',
        'callback' => 'fppAirPlayMatrixRestart'
    );

    return $result;
}

function fppAirPlayMatrixManagerPath() {
    global $settings;

    $paths = array();

    if (isset($settings['mediaDirectory'])) {
        $paths[] = $settings['mediaDirectory'] . '/plugins/fpp-AirPlayMatrix/scripts/airplay_matrix_manager.sh';
    }

    $paths[] = dirname(__FILE__) . '/scripts/airplay_matrix_manager.sh';

    foreach ($paths as $p) {
        if (file_exists($p)) {
            return $p;
        }
    }

    return $paths[count($paths) - 1];
}

function fppAirPlayMatrixConfig() {
    global $settings;

    $cfg = array();
    $cfg['airplay_name'] = 'FPP AirPlay Matrix';
    $cfg['model_name'] = 'Matrix';

    if (!isset($settings['configDirectory'])) {
        return $cfg;
    }

    $cfgFile = $settings['configDirectory'] . '/plugin.fpp-AirPlayMatrix.json';
    if (!file_exists($cfgFile)) {
        return $cfg;
    }

    $decoded = json_decode(file_get_contents($cfgFile), true);
    if (is_array($decoded)) {
        $cfg = array_merge($cfg, $decoded);
    }

    return $cfg;
}

function fppAirPlayMatrixRun($action) {
    $script = fppAirPlayMatrixManagerPath();
    $out = array();
    $rc = 0;

    $sudoPath = '';
    if (is_executable('/usr/bin/sudo')) {
        $sudoPath = '/usr/bin/sudo';
    } else if (is_executable('/bin/sudo')) {
        $sudoPath = '/bin/sudo';
    }

    if ($sudoPath != '') {
        $cmd = escapeshellarg($sudoPath) . ' -n ' . escapeshellarg($script) . ' ' . escapeshellarg($action) . ' 2>&1';
        exec($cmd, $out, $rc);
        if ($rc == 0) {
            return array($rc, trim(implode("\n", $out)));
        }
        $out = array();
    }

    $cmd = escapeshellarg($script) . ' ' . escapeshellarg($action) . ' 2>&1';
    exec($cmd, $out, $rc);

    return array($rc, trim(implode("\n", $out)));
}

function fppAirPlayMatrixStatus() {
    $cfg = fppAirPlayMatrixConfig();
    list($rc, $out) = fppAirPlayMatrixRun('status-json');

    $result = array(
        'running' => false,
        'pid' => null,
        'airplay_name' => $cfg['airplay_name'],
        'model_name' => $cfg['model_name'],
        'message' => ''
    );

    if ($out != '') {
        $decoded = json_decode($out, true);
        if (is_array($decoded)) {
            $result = array_merge($result, $decoded);
        } else {
            $result['message'] = $out;
        }
    }

    if ($rc != 0 && $result['message'] == '') {
        $result['message'] = 'Manager status command returned non-zero';
    }

    return json($result);
}

function fppAirPlayMatrixAction($action, $verb) {
    list($rc, $out) = fppAirPlayMatrixRun($action);

    $result = array(
        'ok' => ($rc == 0),
        'action' => $verb,
        'message' => ($out != '' ? $out : ($rc == 0 ? ($verb . ' complete') : ($verb . ' failed'))),
        'rc' => $rc
    );

    return json($result);
}

function fppAirPlayMatrixStart() {
    return fppAirPlayMatrixAction('start', 'Start');
}

function fppAirPlayMatrixStop() {
    return fppAirPlayMatrixAction('stop', 'Stop');
}

function fppAirPlayMatrixRestart() {
    return fppAirPlayMatrixAction('restart', 'Restart');
}

?>
