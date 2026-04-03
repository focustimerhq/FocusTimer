# Resources
resources_sources = files(
  'io.github.focustimerhq.FocusTimer.gresource.xml',
)
resources = gnome.compile_resources(
  'io.github.focustimerhq.FocusTimer',
  resources_sources,
  c_name: 'resources',
)


# Core
subdir('core')


# UI library
libft_ui_sources = files(
  'ui/log/widgets/time-label.vala',
  'ui/log/log-window.vala',
  'ui/main/dialogs/about-dialog.vala',
  'ui/main/stats/charts/bar-chart.vala',
  'ui/main/stats/charts/bubble-chart.vala',
  'ui/main/stats/charts/canvas-layout.vala',
  'ui/main/stats/charts/canvas.vala',
  'ui/main/stats/charts/chart-axis.vala',
  'ui/main/stats/charts/chart-contents.vala',
  'ui/main/stats/charts/chart-grid.vala',
  'ui/main/stats/charts/chart.vala',
  'ui/main/stats/widgets/day-chooser.vala',
  'ui/main/stats/widgets/month-chooser.vala',
  'ui/main/stats/widgets/stats-card.vala',
  'ui/main/stats/widgets/stats-date-popover.vala',
  'ui/main/stats/widgets/week-chooser.vala',
  'ui/main/stats/stats-day-page.vala',
  'ui/main/stats/stats-month-page.vala',
  'ui/main/stats/stats-page.vala',
  'ui/main/stats/stats-view.vala',
  'ui/main/stats/stats-week-page.vala',
  'ui/main/timer/widgets/session-progress-bar.vala',
  'ui/main/timer/widgets/timer-control-buttons.vala',
  'ui/main/timer/widgets/timer-label.vala',
  'ui/main/timer/widgets/timer-progress-bar.vala',
  'ui/main/timer/compact-timer-view.vala',
  'ui/main/timer/timer-view.vala',
  'ui/main/widgets/size-stack.vala',
  'ui/main/window.vala',
  'ui/overlays/lightbox.vala',
  'ui/overlays/screen-overlay.vala',
  'ui/overlays/screen-overlay-provider.vala',
  'ui/preferences/appearance/preferences-panel-appearance.vala',
  'ui/preferences/automation/action/action-edit-window.vala',
  'ui/preferences/automation/action/action-listboxrow.vala',
  'ui/preferences/automation/action/command-entryrow.vala',
  'ui/preferences/automation/action/condition-group-widget.vala',
  'ui/preferences/automation/action/condition-widget.vala',
  'ui/preferences/automation/action/variable-popover.vala',
  'ui/preferences/automation/preferences-panel-automation.vala',
  'ui/preferences/integrations/preferences-panel-integrations.vala',
  'ui/preferences/keyboard-shortcuts/accelerator-chooser-window.vala',
  'ui/preferences/keyboard-shortcuts/accelerator-row.vala',
  'ui/preferences/keyboard-shortcuts/accelerator.vala',
  'ui/preferences/keyboard-shortcuts/preferences-panel-keyboard-shortcuts.vala',
  'ui/preferences/notifications/preferences-panel-notifications.vala',
  'ui/preferences/sounds/preferences-panel-sounds.vala',
  'ui/preferences/sounds/sound-chooser-window.vala',
  'ui/preferences/sounds/volume-slider.vala',
  'ui/preferences/timer/widgets/log-scale-row.vala',
  'ui/preferences/timer/widgets/log-scale.vala',
  'ui/preferences/timer/preferences-panel-timer.vala',
  'ui/preferences/widgets/preferences-sidebar.vala',
  'ui/preferences/preferences-window.vala',
  'ui/widgets/checkmark.vala',
  'ui/widgets/gizmo.vala',
  'ui/widgets/monospace-label.vala',
  'ui/widgets/sidebar-row.vala',
  'ui/interfaces.vala',
  'ui/utils.vala',
  'application.vala',
  'dbus-services.vala',
)

libft_ui = static_library(
  'ft_ui',
  libft_ui_sources + resources,
  dependencies: [
    libft_core_dep,
    gtk_dep,
    gtk_x11_dep,
    gtk_wayland_dep,
    cairo_dep,
    graphene_dep,
    libadwaita_dep,
    peas_dep,
  ],
  include_directories: config_h_dir,
)

libft_ui_dep = declare_dependency(
  link_with: libft_ui,
  dependencies: [
    libft_core_dep,
    gtk_dep,
    libadwaita_dep,
    peas_dep,
  ],
  include_directories: [
    include_directories('.'),
  ],
)


# Plugins
subdir('plugins')


# The focus-timer executable
executable(
  'focus-timer',
  'main.vala',
  dependencies: [libft_ui_dep],
  link_whole: [libft_ui] + libft_plugins,
  export_dynamic: true,
  include_directories: config_h_dir,
  install: true,
)
