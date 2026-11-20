# Define a common library for all tests.
libtests_common = static_library(
  'tests',
  'common.vala',
  dependencies: libft_core_dep,
  include_directories: config_h_dir,
  install: false
)


# Define tests. Each test is a separate executable.
test_names = [
  'event-bus',
  'event-producer',
  'job-queue',
  'expression',
  'expression-parser',
  'provider-set',
  'provided-object',
  'background-manager',
  'cycle',
  'time-block',
  'timer',
  'timestamp',
  'timezone-history',
  'scheduler',
  'session',
  'session-manager',
  'stats-manager',
  'database',
  'notification-manager',
  'command',
  'action-manager',
  'matrix',
  'utils',
]

test_env = environment()
test_env.set('LANGUAGE', '')
test_env.set('LANG', 'C')
test_env.set('G_TEST_SRCDIR', meson.current_source_dir())
test_env.set('G_TEST_BUILDDIR', meson.current_build_dir())
test_env.set('G_DEBUG', 'gc-friendly')
test_env.set('GSETTINGS_SCHEMA_DIR', meson.project_build_root() / 'data')
test_env.set('GSETTINGS_BACKEND', 'memory')
test_env.set('MALLOC_CHECK_', '2')

foreach test_name : test_names
  test_sources = [
    f'test-@test_name@.vala',
    compiled_schemas,
    resources,
  ]
  test(
    test_name,
    executable(
      f'test-@test_name@',
      test_sources,
      dependencies: libft_core_dep,
      link_with: libtests_common,
      c_args: [
        '-UG_DISABLE_ASSERT',
      ],
    ),
    env: test_env,
    suite: 'tests',
  )
endforeach

test(
  'portal',
  executable(
    'test-portal',
    'test-portal.vala',
    files(
      meson.project_source_root() / 'src/plugins/portal/interfaces.vala',
      meson.project_source_root() / 'src/plugins/portal/request.vala',
      meson.project_source_root() / 'src/plugins/portal/background-provider.vala',
    ),
    dependencies: libft_core_dep,
    link_with: libtests_common,
    include_directories: config_h_dir,
  ),
  env: test_env,
  suite: 'tests',
)
