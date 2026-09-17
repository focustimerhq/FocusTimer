if get_option('plugin_gnome').enabled()
  gnome_plugin_resources = gnome.compile_resources(
    'gnome-plugin-resources',
    'gnome.gresource.xml',
    c_name: 'gnome_plugin',
  )

  libft_plugin_gnome = static_library(
    'ft_plugin_gnome',
    files(
      'application-extension.vala',
      'gnome.vala',
      'idle-monitor-provider.vala',
      'indicator-provider.vala',
      'install-extension-dialog.vala',
      'interfaces.vala',
      'preferences-window-extension.vala',
      'screen-overlay-provider.vala',
      'screen-saver-provider.vala',
      'shell-extension.vala',
      'shell-extension-settings.vala',
      'window-extension.vala',
    ) + gnome_plugin_resources,
    dependencies: [libft_ui_dep],
    include_directories: config_h_dir,
  )

  libft_plugins += [libft_plugin_gnome]

  # GSchema
  install_data(
    'io.github.focustimerhq.FocusTimer.plugins.gnome.gschema.xml',
    install_dir: gschema_dir,
  )

  compile_schemas = find_program('glib-compile-schemas', required: false)
  if compile_schemas.found()
    test('Validate gnome schema file', compile_schemas,
      args: ['--strict', '--dry-run', meson.current_source_dir()]
    )
  endif

  compiled_schemas = gnome.compile_schemas(
    depend_files: 'io.github.focustimerhq.FocusTimer.plugins.gnome.gschema.xml'
  )
endif