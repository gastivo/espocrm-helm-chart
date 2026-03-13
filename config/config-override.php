<?php
declare(strict_types=1);

$logLevel = strtoupper(getenv('ESPOCRM_CONFIG_LOGGER_LEVEL') ?: 'WARNING');
$logTrace = (bool)getenv('ESPOCRM_CONFIG_LOGGER_TRACE');

$externalConfig = [];

$cmOverrideFile = __DIR__ . '/config-override-cm.php';
if (file_exists($cmOverrideFile)) {
    $cmConfig = include $cmOverrideFile;
    if (is_array($cmConfig)) {
        $externalConfig = array_merge_recursive($externalConfig, $cmConfig);
    } else {
        error_log("Config file '$cmOverrideFile' does not return an array.");
    }
}

$baseConfig = [
    'adminUpgradeDisabled' => filter_var(getenv('ESPOCRM_ADMIN_UPGRADE_DISABLED'), FILTER_VALIDATE_BOOLEAN),
    'logger' => [
        'level' => $logLevel,
        'handlerList' => (static function () use ($logLevel, $logTrace) {
            // Daemon mode: File-only (tail -f in daemon-wrapper.sh forwards to stdout)
            if (filter_var(getenv('ESPOCRM_DAEMON_MODE'), FILTER_VALIDATE_BOOLEAN)) {
                return [
                    [
                        'className' => 'Monolog\\Handler\\StreamHandler',
                        'params' => [
                            'stream' => '/tmp/espocrm_daemon.log',
                            'level' => $logLevel,
                        ],
                        'formatter' => [
                            'className' => 'Monolog\\Formatter\\JsonFormatter',
                            'params' => [
                                'includeStacktraces' => $logTrace,
                            ],
                        ],
                    ],
                ];
            }

            // PHP/Websocket: stdout only (file logging not needed, stdout goes to Container)
            return [
                [
                    'className' => 'Monolog\\Handler\\StreamHandler',
                    'params' => [
                        'stream' => 'php://stdout',
                        'level' => $logLevel,
                    ],
                    'formatter' => [
                        'className' => 'Monolog\\Formatter\\JsonFormatter',
                        'params' => [
                            'includeStacktraces' => $logTrace,
                        ],
                    ],
                ],
            ];
        })(),
    ],
];

return array_merge_recursive($baseConfig, $externalConfig);
