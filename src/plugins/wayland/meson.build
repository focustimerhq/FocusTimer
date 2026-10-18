if enable_plugin_wayland
  idle_protocol_xml = files('protocols/ext-idle-notify-v1.xml')

  ext_idle_protocol_client_header = custom_target(
    'ext-idle-protocol-client-header',
    input: idle_protocol_xml,
    output: 'ext-idle-protocol-client.h',
    command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'],
  )

  ext_idle_protocol_private_code = custom_target(
    'ext-idle-protocol-private-code',
    input: idle_protocol_xml,
    output: 'ext-idle-protocol.c',
    command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'],
  )

  wayland_plugin_inc = include_directories('.')

  wayland_plugin_resources = gnome.compile_resources(
    'wayland-plugin-resources',
    'wayland.gresource.xml',
    c_name: 'wayland_plugin',
  )

  libft_plugin_wayland = static_library(
    'ft_plugin_wayland',
    files(
      'idle-monitor.c',
      'idle-monitor-provider.vala',
      'wayland.vala',
    ) + [
      ext_idle_protocol_client_header,
      ext_idle_protocol_private_code,
    ] + wayland_plugin_resources,
    dependencies: [
      libft_ui_dep,
      gtk_wayland_dep,
      wayland_client_dep,
    ],
    vala_args: [
      '--vapidir', meson.current_source_dir(),
      '--pkg', 'ft-wayland',
    ],
    include_directories: [config_h_dir, wayland_plugin_inc],
  )

  libft_plugins += [libft_plugin_wayland]
endif
