require_relative 'test_base.rb'

class KataContainerTest < TestBase

  def self.hex_prefix
    '6ED'
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  multi_os_test '3B1',
  'after kata_new the timeout script is in /usr/local/bin' do
    filename = 'timeout_cyber_dojo.sh'
    in_kata_as('salmon') {
      src = assert_cyber_dojo_sh("cat /usr/local/bin/#{filename}")
      local_src = IO.read("/app/src/#{filename}")
      assert_equal local_src.strip, src.strip
    }
  end

end
