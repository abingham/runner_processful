require_relative 'test_base'

class SharedFolderTest < TestBase

  def self.hex_prefix
    'B4A'
  end

  # - - - - - - - - - - - - - - - - - - - - -

  multi_os_test 'B33',
  %w( first avatar_new event in a kata causes creation of sandboxes shared-dir ) do
    in_kata_as('salmon') {
      assert_cyber_dojo_sh("[ -d #{shared_dir} ]")
    }
  end

  # - - - - - - - - - - - - - - - - - - - - -

  multi_os_test 'A54',
  %w( sandboxes shared-dir creation is idempotent ) do
    in_kata_as('lion') {
      as('salmon') {
        assert_cyber_dojo_sh("[ -d #{shared_dir} ]")
      }
    }
  end

  # - - - - - - - - - - - - - - - - - - - - -

  multi_os_test '893',
  %w( sandboxes shared-dir is writable by any avatar ) do
    in_kata_as('salmon') {
      stat_group = assert_cyber_dojo_sh("stat -c '%G' #{shared_dir}").strip
      diagnostic = 'sandbox is owned by cyber-dojo'
      assert_equal 'cyber-dojo', stat_group, diagnostic
      stat_perms = assert_cyber_dojo_sh("stat -c '%A' #{shared_dir}").strip
      diagnostic = 'sandbox permissions are set'
      assert_equal 'drwxrwxr-x', stat_perms, diagnostic
    }
  end

  def shared_dir
    '/sandboxes/shared'
  end

end
