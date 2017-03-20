require_relative 'test_base'
require_relative 'os_helper'

class RunUbuntuKataTest < TestBase

  include OsHelper

  def self.hex_prefix; '2C3B9'; end

  def hex_setup
    set_image_name image_for_test
    kata_new
  end

  def hex_teardown
    kata_old
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'CA1',
  '[Ubuntu] image is indeed based on Ubuntu' do
    etc_issue = assert_docker_run 'cat /etc/issue'
    assert etc_issue.include?('Ubuntu'), etc_issue
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '268',
  "[Ubuntu] none of the 64 avatar's uid's are already taken" do
    refute_avatar_users_exist
  end

end
