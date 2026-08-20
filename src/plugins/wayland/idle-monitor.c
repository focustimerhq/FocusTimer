/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <string.h>

#include "ft-wayland.h"
#include "ext-idle-protocol-client.h"

#define FT_WAYLAND_IDLE_MONITOR_BIND_VERSION 2

typedef struct
{
  uint32_t id;
  uint32_t timeout_ms;
  struct ext_idle_notification_v1 *notification;
  FtWaylandIdleMonitorCallback on_idled;
  FtWaylandIdleMonitorCallback on_resumed;
  gpointer user_data;
} FtWaylandIdleMonitorWatch;

struct _FtWaylandIdleMonitor
{
  struct wl_display *display;
  struct wl_seat *seat;
  struct wl_registry *registry;
  struct ext_idle_notifier_v1 *notifier;
  uint32_t notifier_global_name;
  gboolean supports_input_idle;
  gboolean ready;
  GHashTable *watches;
  uint32_t next_id;
};

static void
notification_handle_idled (void                            *data,
                           struct ext_idle_notification_v1 *notification)
{
  FtWaylandIdleMonitorWatch *watch = data;

  (void) notification;

  if (watch->on_idled != NULL) {
    watch->on_idled (watch->id, watch->user_data);
  }
}

static void
notification_handle_resumed (void                            *data,
                             struct ext_idle_notification_v1 *notification)
{
  FtWaylandIdleMonitorWatch *watch = data;

  (void) notification;

  if (watch->on_resumed != NULL) {
    watch->on_resumed (watch->id, watch->user_data);
  }
}

static const struct ext_idle_notification_v1_listener notification_listener = {
  .idled = notification_handle_idled,
  .resumed = notification_handle_resumed,
};

static void
registry_handle_global (void               *data,
                        struct wl_registry *registry,
                        uint32_t            name,
                        const char         *interface,
                        uint32_t            version)
{
  FtWaylandIdleMonitor *monitor = data;

  (void) registry;

  if (strcmp (interface, ext_idle_notifier_v1_interface.name) != 0) {
    return;
  }

  if (monitor->notifier != NULL) {
    return;
  }

  uint32_t bind_version = version < FT_WAYLAND_IDLE_MONITOR_BIND_VERSION
                              ? version
                              : FT_WAYLAND_IDLE_MONITOR_BIND_VERSION;

  monitor->notifier = wl_registry_bind (registry,
                                        name,
                                        &ext_idle_notifier_v1_interface,
                                        bind_version);
  monitor->notifier_global_name = name;
  monitor->supports_input_idle = bind_version >= 2;
  monitor->ready = monitor->notifier != NULL;
}

static void
registry_handle_global_remove (void               *data,
                               struct wl_registry *registry,
                               uint32_t            name)
{
  FtWaylandIdleMonitor *monitor = data;

  (void) registry;

  if (monitor->notifier == NULL || monitor->notifier_global_name != name) {
    return;
  }

  ext_idle_notifier_v1_destroy (monitor->notifier);
  monitor->notifier = NULL;
  monitor->notifier_global_name = 0;
  monitor->supports_input_idle = FALSE;
  monitor->ready = FALSE;
}

static const struct wl_registry_listener registry_listener = {
  .global = registry_handle_global,
  .global_remove = registry_handle_global_remove,
};

static void
watch_free (gpointer data)
{
  FtWaylandIdleMonitorWatch *watch = data;

  if (watch->notification != NULL) {
    ext_idle_notification_v1_destroy (watch->notification);
    watch->notification = NULL;
  }

  g_free (watch);
}

FtWaylandIdleMonitor *
ft_wayland_idle_monitor_new (struct wl_display *display,
                             struct wl_seat    *seat)
{
  g_return_val_if_fail (display != NULL, NULL);
  g_return_val_if_fail (seat != NULL, NULL);

  FtWaylandIdleMonitor *monitor = g_new0 (FtWaylandIdleMonitor, 1);

  monitor->display = display;
  monitor->seat = seat;
  monitor->next_id = 1;
  monitor->watches = g_hash_table_new_full (g_direct_hash,
                                            g_direct_equal,
                                            NULL,
                                            watch_free);

  monitor->registry = wl_display_get_registry (display);
  wl_registry_add_listener (monitor->registry, &registry_listener, monitor);

  wl_display_flush (display);
  wl_display_dispatch_pending (display);

  if (wl_display_roundtrip (display) < 0) {
    g_warning ("Wayland: wl_display_roundtrip failed while binding ext_idle_notifier_v1");
  }

  return monitor;
}

FtWaylandIdleMonitor *
ft_wayland_idle_monitor_ref (FtWaylandIdleMonitor *monitor)
{
  g_return_val_if_fail (monitor != NULL, NULL);

  return monitor;
}

void
ft_wayland_idle_monitor_unref (FtWaylandIdleMonitor *monitor)
{
  ft_wayland_idle_monitor_free (monitor);
}

void
ft_wayland_idle_monitor_free (FtWaylandIdleMonitor *monitor)
{
  if (monitor == NULL) {
    return;
  }

  if (monitor->watches != NULL) {
    g_hash_table_remove_all (monitor->watches);
    g_hash_table_unref (monitor->watches);
    monitor->watches = NULL;
  }

  if (monitor->notifier != NULL) {
    ext_idle_notifier_v1_destroy (monitor->notifier);
    monitor->notifier = NULL;
    monitor->notifier_global_name = 0;
  }

  if (monitor->registry != NULL) {
    wl_registry_destroy (monitor->registry);
    monitor->registry = NULL;
  }

  g_free (monitor);
}

gboolean
ft_wayland_idle_monitor_is_ready (FtWaylandIdleMonitor *monitor)
{
  g_return_val_if_fail (monitor != NULL, FALSE);

  return monitor->ready && monitor->notifier != NULL;
}

gboolean
ft_wayland_idle_monitor_supports_input_idle (FtWaylandIdleMonitor *monitor)
{
  g_return_val_if_fail (monitor != NULL, FALSE);

  return monitor->supports_input_idle;
}

static uint32_t
add_notification_internal (FtWaylandIdleMonitor         *monitor,
                           uint32_t                      timeout_ms,
                           FtWaylandIdleMonitorCallback  on_idled,
                           FtWaylandIdleMonitorCallback  on_resumed,
                           gpointer                      user_data,
                           gboolean                      use_input_idle)
{
  uint32_t id = monitor->next_id++;
  FtWaylandIdleMonitorWatch *watch = g_new0 (FtWaylandIdleMonitorWatch, 1);

  watch->id = id;
  watch->timeout_ms = timeout_ms;
  watch->on_idled = on_idled;
  watch->on_resumed = on_resumed;
  watch->user_data = user_data;

  if (use_input_idle) {
    watch->notification =
        ext_idle_notifier_v1_get_input_idle_notification (monitor->notifier,
                                                          timeout_ms,
                                                          monitor->seat);
  } else {
    watch->notification =
        ext_idle_notifier_v1_get_idle_notification (monitor->notifier,
                                                    timeout_ms,
                                                    monitor->seat);
  }

  ext_idle_notification_v1_add_listener (watch->notification,
                                         &notification_listener,
                                         watch);
  g_hash_table_insert (monitor->watches, GUINT_TO_POINTER (id), watch);

  return id;
}

uint32_t
ft_wayland_idle_monitor_add_notification (FtWaylandIdleMonitor         *monitor,
                                          uint32_t                      timeout_ms,
                                          FtWaylandIdleMonitorCallback  on_idled,
                                          FtWaylandIdleMonitorCallback  on_resumed,
                                          gpointer                      user_data)
{
  g_return_val_if_fail (monitor != NULL, 0);
  g_return_val_if_fail (ft_wayland_idle_monitor_is_ready (monitor), 0);

  return add_notification_internal (monitor,
                                    timeout_ms,
                                    on_idled,
                                    on_resumed,
                                    user_data,
                                    FALSE);
}

uint32_t
ft_wayland_idle_monitor_add_input_notification (FtWaylandIdleMonitor         *monitor,
                                                uint32_t                      timeout_ms,
                                                FtWaylandIdleMonitorCallback  on_idled,
                                                FtWaylandIdleMonitorCallback  on_resumed,
                                                gpointer                      user_data)
{
  g_return_val_if_fail (monitor != NULL, 0);
  g_return_val_if_fail (ft_wayland_idle_monitor_is_ready (monitor), 0);
  g_return_val_if_fail (monitor->supports_input_idle, 0);

  return add_notification_internal (monitor,
                                    timeout_ms,
                                    on_idled,
                                    on_resumed,
                                    user_data,
                                    TRUE);
}

void
ft_wayland_idle_monitor_remove_notification (FtWaylandIdleMonitor *monitor,
                                             uint32_t              id)
{
  g_return_if_fail (monitor != NULL);

  if (id == 0) {
    return;
  }

  g_hash_table_remove (monitor->watches, GUINT_TO_POINTER (id));
}
