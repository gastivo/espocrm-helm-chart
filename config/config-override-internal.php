<?php
declare(strict_types=1);

$externalConfig = [];

$cmOverrideFile = __DIR__ . '/config-override-internal-cm.php';
if (file_exists($cmOverrideFile)) {
    $cmConfig = include $cmOverrideFile;
    if (is_array($cmConfig)) {
        $externalConfig = array_merge_recursive($externalConfig, $cmConfig);
    } else {
        error_log("Config file '$cmOverrideFile' does not return an array.");
    }
}

$baseConfig = [];

return array_merge_recursive($baseConfig, $externalConfig);
