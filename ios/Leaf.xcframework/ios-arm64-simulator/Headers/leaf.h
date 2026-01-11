#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * No error.
 */
#define ERR_OK 0

/**
 * Config path error.
 */
#define ERR_CONFIG_PATH 1

/**
 * Config parsing error.
 */
#define ERR_CONFIG 2

/**
 * IO error.
 */
#define ERR_IO 3

/**
 * Config file watcher error.
 */
#define ERR_WATCHER 4

/**
 * Async channel send error.
 */
#define ERR_ASYNC_CHANNEL_SEND 5

/**
 * Sync channel receive error.
 */
#define ERR_SYNC_CHANNEL_RECV 6

/**
 * Runtime manager error.
 */
#define ERR_RUNTIME_MANAGER 7

/**
 * No associated config file.
 */
#define ERR_NO_CONFIG_FILE 8

/**
 * No data found.
 */
#define ERR_NO_DATA 9

/**
 * Starts leaf with options, on a successful start this function blocks the current
 * thread.
 *
 * @note This is not a stable API, parameters will change from time to time.
 *
 * @param rt_id A unique ID to associate this leaf instance, this is required when
 *              calling subsequent FFI functions, e.g. reload, shutdown.
 * @param config_path The path of the config file, must be a file with suffix .conf
 *                    or .json, according to the enabled features.
 * @param auto_reload Enabls auto reloading when config file changes are detected,
 *                    takes effect only when the "auto-reload" feature is enabled.
 * @param multi_thread Whether to use a multi-threaded runtime.
 * @param auto_threads Sets the number of runtime worker threads automatically,
 *                     takes effect only when multi_thread is true.
 * @param threads Sets the number of runtime worker threads, takes effect when
 *                     multi_thread is true, but can be overridden by auto_threads.
 * @param stack_size Sets stack size of the runtime worker threads, takes effect when
 *                   multi_thread is true.
 * @return ERR_OK on finish running, any other errors means a startup failure.
 */
int32_t leaf_run_with_options(uint16_t rt_id,
                              const char *config_path,
                              bool auto_reload,
                              bool multi_thread,
                              bool auto_threads,
                              int32_t threads,
                              int32_t stack_size);

/**
 * Starts leaf with a single-threaded runtime, on a successful start this function
 * blocks the current thread.
 *
 * @param rt_id A unique ID to associate this leaf instance, this is required when
 *              calling subsequent FFI functions, e.g. reload, shutdown.
 * @param config_path The path of the config file, must be a file with suffix .conf
 *                    or .json, according to the enabled features.
 * @return ERR_OK on finish running, any other errors means a startup failure.
 */
int32_t leaf_run(uint16_t rt_id, const char *config_path);

int32_t leaf_run_with_config_string(uint16_t rt_id, const char *config);

/**
 * Reloads DNS servers, outbounds and routing rules from the config file.
 *
 * @param rt_id The ID of the leaf instance to reload.
 *
 * @return Returns ERR_OK on success.
 */
int32_t leaf_reload(uint16_t rt_id);

/**
 * Shuts down leaf.
 *
 * @param rt_id The ID of the leaf instance to reload.
 *
 * @return Returns true on success, false otherwise.
 */
bool leaf_shutdown(uint16_t rt_id);

/**
 * Tests the configuration.
 *
 * @param config_path The path of the config file, must be a file with suffix .conf
 *                    or .json, according to the enabled features.
 * @return Returns ERR_OK on success, i.e no syntax error.
 */
int32_t leaf_test_config(const char *config_path);

/**
 * Runs a health check for an outbound.
 *
 * This performs an active health check by sending a PING to healthcheck.leaf
 * and waiting for a PONG response through the specified outbound, testing both
 * TCP and UDP protocols.
 *
 * @param rt_id The ID of the leaf instance.
 * @param outbound_tag The tag of the outbound to test.
 * @param timeout_ms Timeout in milliseconds (0 for default 4 seconds).
 * @return Returns ERR_OK if either TCP or UDP health check succeeds, error code otherwise.
 */
int32_t leaf_health_check(uint16_t rt_id, const char *outbound_tag, uint64_t timeout_ms);

/**
 * Gets the last active time for an outbound.
 *
 * This returns the timestamp of the last successful connection through the outbound.
 *
 * @param rt_id The ID of the leaf instance.
 * @param outbound_tag The tag of the outbound.
 * @param timestamp_s Pointer to store the timestamp in seconds since epoch.
 * @return Returns ERR_OK on success, ERR_NO_DATA if no active time found, error code otherwise.
 */
int32_t leaf_get_last_active(uint16_t rt_id, const char *outbound_tag, uint32_t *timestamp_s);

/**
 * Gets seconds since last active time for an outbound.
 *
 * This returns the number of seconds elapsed since the last successful
 * connection through the specified outbound.
 *
 * @param rt_id The ID of the leaf instance.
 * @param outbound_tag The tag of the outbound.
 * @param since_s Pointer to store the seconds since last active.
 * @return Returns ERR_OK on success, ERR_NO_DATA if no active time found, error code otherwise.
 */
int32_t leaf_get_since_last_active(uint16_t rt_id, const char *outbound_tag, uint32_t *since_s);
