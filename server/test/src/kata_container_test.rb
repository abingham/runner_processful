=begin
require_relative 'test_base.rb'
require_relative 'os_helper'

class KataContainerTest < TestBase

  include OsHelper

  def self.hex_prefix; '6ED'; end

  def hex_setup
    set_image_name image_for_test
    new_kata
  end

  def hex_teardown
    old_kata
  end

  def self.kc_test(hex_suffix, *lines, &test_block)
    if runner_class_name == 'DockerContainerRunner'
      test(hex_suffix, *lines, &test_block)
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  kc_test '3B1',
  '[Alpine] after new_kata the timeout script is in /usr/local/bin' do
    filename = 'timeout_cyber_dojo.sh'
    src = assert_docker_exec("cat /usr/local/bin/#{filename}")
    local_src = IO.read("/app/src/#{filename}")
    assert_equal local_src, src
  end

  kc_test '3B2',
  '[Ubuntu] after new_kata the timeout script is in /usr/local/bin' do
    filename = 'timeout_cyber_dojo.sh'
    src = assert_docker_exec("cat /usr/local/bin/#{filename}")
    local_src = IO.read("/app/src/#{filename}")
    assert_equal local_src, src
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  kc_test '5F9',
  '[Alpine] after new_avatar(salmon)',
  'there is a linux user called salmon inside the kata container' do
    new_avatar('salmon')
    begin
      uid = assert_docker_exec('id -u salmon').strip
      assert_equal user_id('salmon'), uid
    ensure
      old_avatar('salmon')
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  kc_test '2A8',
  '[Ubuntu] after new_avatar(salmon)',
  'there is a linux user called salmon inside the kata container' do
    new_avatar('salmon')
    begin
      uid = assert_docker_exec('id -u salmon').strip
      assert_equal user_id('salmon'), uid
    ensure
      old_avatar('salmon')
    end
  end

  private

  def container_name
    'cyber_dojo_kata_container_runner_' + kata_id
  end

end
=end