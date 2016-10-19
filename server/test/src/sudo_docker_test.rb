
require_relative './lib_test_base'
require_relative './mock_sheller'

class SudoDockerTest < LibTestBase

  def self.hex(suffix)
    '1BF' + suffix
  end

  def setup
    super
    ENV[env_name('shell')]  = 'ExternalSheller'
    ENV[env_name('log')] = 'SpyLogger'
    test_id = ENV['DIFFER_TEST_ID']
    @stdoutFile = "/tmp/cyber-dojo/stdout.#{@test_id}"
    @stderrFile = "/tmp/cyber-dojo/stderr.#{@test_id}"
  end

  def teardown
    super
  end

  attr_reader :stdoutFile, :stderrFile

  test '111',
  'show info' do
    p `uname -a`
    p `whoami`
    p `ls -al /var/run/docker.sock`
    p `cat /etc/group`

    # - - - - - - - - - - - - - - - - - - - - - - - - - -
    # Why do the tests break on a manually built server? (see below)
    # Why do the tests break on Docker-Toolbox setup?
    # - - - - - - - - - - - - - - - - - - - - - - - - - -

    # -------------------------------------
    # On manually built server (Google cloud, after installing docker)
    #    B4C test fails. I can run [docker images] _without_ sudoing
    # -------------------------------------
    # On host itself
    #    whoami     -> jrbjagger
    #    uname -a   -> 14.04.1-Ubuntu
    #    ls -al     -> srw-rw---- 1 root docker 0 Oct 19 10:17 /var/run/docker.sock
    #    /etc/group -> docker:x:999:
    #
    # From test inside container
    #    whoami     -> cyber-dojo
    #    uname -a   -> 14.04.1-Ubuntu
    #    ls -al     -> srw-rw---- 1 root ping 0 Oct 19 10:17 /var/run/docker.sock
    #    /etc/group -> ping:x:999:
    #
    # -------------------------------------
    # On travis:
    #   tests pass CI I cant and test passes...
    # -------------------------------------
    # Travis host itself (travis is member of docker group)
    #    whoami     -> travis?
    #    uname -a   -> 14.04.1-Ubuntu
    #    ls -al     -> srw-rw----  1 root docker 0 Oct 19 10:17
    #    /etc/group -> docker:x:999:travis:
    #
    # From test running inside container
    #    whoami     -> cyber-dojo
    #    uname -a   -> 14.04.1-Ubuntu
    #    ls -al     -> srw-rw----  1 root ping 0 Oct 19 10:17
    #    /etc/group -> ping:x:999:
    # -------------------------------------

  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'B4C',
  'sudoless docker command fails with exit_status non-zero' do
    # NB: sudoless [docker images]...
    # o) locally on a Mac using Docker-Toolbox it _can_ be run, and this test fails
    # o) on a proper Travis CI Linux box it can't be run, and this test passes
    command = "docker images >#{stdoutFile} 2>#{stderrFile}"
    output, exit_status = shell.exec([command])
    refute_equal success, exit_status, '[docker image] can be run without sudo!!'
    assert `cat #{stderrFile}`.start_with? 'Cannot connect to the Docker daemon'
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '279',
  'sudo docker command succeeds and exits zero' do
    # NB: sudo [docker images]...
    # o) locally on a Mac using Docker-Toolbox this test is no good (see above)
    # o) on a proper Travis CI Linux box this test is currently passing...
    command = "#{sudo} docker images >#{stdoutFile} 2>#{stderrFile}"
    output, exit_status = shell.exec([command])
    assert_equal success, exit_status
    docker_images = `cat #{stdoutFile}`
    assert docker_images.include? 'cyberdojo/runner'
  end

  private

  include Externals

  def success
    0
  end

  def sudo
    'sudo -u docker-runner sudo'
  end

end
