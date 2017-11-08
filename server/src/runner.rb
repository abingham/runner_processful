require_relative 'all_avatars_names'
require_relative 'logger_null'
require_relative 'string_cleaner'
require_relative 'string_truncater'
require_relative 'valid_image_name'
require 'timeout'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Uses a new long-lived container per kata.
# Each avatar's run() [docker exec]s a new process
# inside the kata's container.
#
# Negatives:
#   o) harder to secure.
#   o) uses more host resources.
#
# Positives:
#   o) avatars can share state.
#   o) opens the way to avatars sharing processes.
#   o) fastest run(). In a rough sample
#      ~30% faster than runner_stateful
# - - - - - - - - - - - - - - - - - - - - - - - - - - - -

class Runner # processful

  def initialize(parent, image_name, kata_id)
    @disk = parent.disk
    @shell = parent.shell
    @image_name = image_name
    @kata_id = kata_id
    assert_valid_image_name
    assert_valid_kata_id
  end

  attr_reader :image_name, :kata_id

  # - - - - - - - - - - - - - - - - - -
  # image
  # - - - - - - - - - - - - - - - - - -

  def image_pulled?
    image_names.include? image_name
  end

  # - - - - - - - - - - - - - - - - - -

  def image_pull
    # [1] The contents of stderr vary depending on Docker version
    _stdout,stderr,status = quiet_exec("docker pull #{image_name}")
    if status == success
      return true
    elsif stderr.include?('not found') || stderr.include?('not exist')
      return false # [1]
    else
      fail_image_name('invalid')
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # kata
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def kata_exists?
    cmd = [
      'docker ps',
        '--quiet',
        '--all',
        '--filter status=running',
        "--filter name=#{container_name}"
    ].join(space)
    stdout,_ = assert_exec(cmd)
    stdout.strip != ''
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def kata_new
    refute_kata_exists
    # The container may have exited but its
    # volume may not have been collected yet.
    quiet_exec(remove_container_cmd)
    name = container_name
    mb8 = 8 * 1024 * 1024
    mb16 = 16 * 1024 * 1024
    gb4 = 4 * 1024 * 1024 * 1024
    args = [
      '--detach',
      '--init',                            # pid-1 process
      '--interactive',                     # later execs
      "--name=#{name}",
      '--net=none',                        # security
      '--pids-limit=128',                  # no fork bombs
      '--security-opt=no-new-privileges',  # no escalation
      "--ulimit data=#{gb4}:#{gb4}",       # max data segment size
      '--ulimit core=0:0',                 # max core file size
      "--ulimit fsize=#{mb16}:#{mb16}",    # max file size
      '--ulimit locks=128:128',            # max number of file locks
      '--ulimit nofile=128:128',           # max number of files
      '--ulimit nproc=128:128',            # max number processes
      "--ulimit stack=#{mb8}:#{mb8}",      # max stack size
      '--user=root',
      "--volume #{name}:#{sandboxes_root_dir}:rw"
    ].join(space)

    init_filename = '/usr/local/bin/cyber-dojo-init.sh'
    cmd = [
      "docker run #{args}",
      image_name,
      "sh -c '([ -f #{init_filename}] && #{init_filename}); sleep 3h'"
    ].join(space)

    assert_exec(cmd)

    my_dir = File.expand_path(File.dirname(__FILE__))
    docker_cp = [
      'docker cp',
      "#{my_dir}/timeout_cyber_dojo.sh",
      "#{name}:/usr/local/bin"
    ].join(space)
    assert_exec(docker_cp)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def kata_old
    assert_kata_exists
    assert_exec(remove_container_cmd)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # avatar
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_exists?(avatar_name)
    assert_kata_exists
    assert_valid_avatar_name(avatar_name)
    dir = avatar_dir(avatar_name)
    _stdout,_stderr,status = quiet_exec(docker_cmd("[ -d #{dir} ]"))
    status == success
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_new(avatar_name, starting_files)
    assert_kata_exists
    refute_avatar_exists(avatar_name)
    make_shared_dir
    chown_shared_dir
    make_avatar_dir(avatar_name)
    chown_avatar_dir(avatar_name)
    write_files(avatar_name, starting_files)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_old(avatar_name)
    assert_kata_exists
    assert_avatar_exists(avatar_name)
    remove_avatar_dir(avatar_name)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # run
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

=begin
  def run_cyber_dojo_sh(
    avatar_name,
    deleted_filenames,
    unchanged_files, changed_files, new_files,
    max_seconds
  )
    all_files = [*unchanged_files, *changed_files, *new_files].to_h
    run(avatar_name, deleted_filenames, all_files, max_seconds)
  end
=end

  def run(avatar_name, deleted_filenames, changed_files, max_seconds)
    assert_kata_exists
    assert_avatar_exists(avatar_name)
    delete_files(avatar_name, deleted_filenames)
    write_files(avatar_name, changed_files)
    stdout,stderr,status,colour = run_timeout_cyber_dojo_sh(avatar_name, max_seconds)
    { stdout:stdout, stderr:stderr, status:status, colour:colour }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # properties
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def group
    'cyber-dojo'
  end

  def gid
    5000
  end

  def user_id(avatar_name)
    assert_valid_avatar_name(avatar_name)
    40000 + all_avatars_names.index(avatar_name)
  end

  def avatar_dir(avatar_name)
    assert_valid_avatar_name(avatar_name)
    "#{sandboxes_root_dir}/#{avatar_name}"
  end

  def sandboxes_root_dir
    '/sandboxes'
  end

  def timed_out
    'timed_out'
  end

  private

  attr_reader :disk, :shell

  def remove_container_cmd
    "docker rm --force --volumes #{container_name}"
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def delete_files(avatar_name, pathed_filenames)
    # Most of the time pathed_filenames == []
    pathed_filenames.each do |pathed_filename|
      # so do dir inside the block
      dir = avatar_dir(avatar_name)
      assert_docker_exec("rm #{dir}/#{pathed_filename}")
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def write_files(avatar_name, files)
    return if files == {}
    Dir.mktmpdir('runner') do |tmp_dir|
      # Save the files onto the host...
      files.each do |pathed_filename, content|
        sub_dir = File.dirname(pathed_filename)
        if sub_dir != '.'
          src_dir = tmp_dir + '/' + sub_dir
          shell.exec("mkdir -p #{src_dir}")
        end
        host_filename = tmp_dir + '/' + pathed_filename
        disk.write(host_filename, content)
      end
      # ...then tar-pipe them into the container.
      dir = avatar_dir(avatar_name)
      uid = user_id(avatar_name)
      tar_pipe = [
        "chmod 755 #{tmp_dir}",
        "&& cd #{tmp_dir}",
        '&& tar',
              "--owner=#{uid}",
              "--group=#{gid}",
              '-zcf',             # create a compressed tar file
              '-',                # write it to stdout
              '.',                # tar the current directory
              '|',
                  'docker exec',  # pipe the tarfile into docker container
                    "--user=#{uid}:#{gid}",
                    '--interactive',
                    container_name,
                    'sh -c',
                    "'",          # open quote
                    "cd #{dir}",
                    '&& tar',
                          '-zxf', # extract from a compressed tar file
                          '-',    # which is read from stdin
                          '-C',   # save the extracted files to
                          '.',    # the current directory
                    "'"           # close quote
      ].join(space)
      # Note: On Alpine-Linux this tar-pipe stores file date-stamps
      # to the second. Viz, the microseconds are always zero.
      # This is very unlikely to matter for a real test-event from
      # the browser but does matter in some tests.
      assert_exec(tar_pipe)
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def run_timeout_cyber_dojo_sh(avatar_name, max_seconds)
    # The processes __inside__ the docker container
    # are killed by /usr/local/bin/timeout_cyber_dojo.sh
    # See kata_new() above.
    sh_cmd = [
      '/usr/local/bin/timeout_cyber_dojo.sh',
      kata_id,
      avatar_name,
      max_seconds
    ].join(space)
    run_timeout(docker_cmd(sh_cmd), max_seconds)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  include StringCleaner
  include StringTruncater

  def run_timeout(cmd, max_seconds)
    # This kills the container from the "outside".
    # Originally I also time-limited the cpu-time from the "inside"
    # using the cpu ulimit. However a cpu-limit of 10 seconds could
    # kill the container after only 5 seconds. This is because the
    # cpu-ulimit assumes one core. The host system running the docker
    # container can have multiple cores or use hyperthreading. So a
    # piece of code running on 2 cores, both 100% utilized could be
    # killed after 5 seconds. So there is no longer a cpu-ulimit.
    r_stdout, w_stdout = IO.pipe
    r_stderr, w_stderr = IO.pipe
    pid = Process.spawn(cmd, {
      pgroup:true,
         out:w_stdout,
         err:w_stderr
    })
    begin
      Timeout::timeout(max_seconds) do
        Process.waitpid(pid)
        status = $?.exitstatus
        w_stdout.close
        w_stderr.close
        stdout = truncated(cleaned(r_stdout.read))
        stderr = truncated(cleaned(r_stderr.read))
        colour = red_amber_green(container_name, stdout, stderr, status)
        [stdout, stderr, status, colour]
      end
    rescue Timeout::Error
      # Kill the [docker exec] processes running
      # on the host. This does __not__ kill the
      # cyber-dojo.sh process running __inside__
      # the docker container. See
      # https://github.com/docker/docker/issues/9098
      # The container is killed by kata_old()
      Process.kill(-9, pid)
      Process.detach(pid)
      ['', '', 137, timed_out]
    ensure
      w_stdout.close unless w_stdout.closed?
      w_stderr.close unless w_stderr.closed?
      r_stdout.close
      r_stderr.close
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def red_amber_green(cid, stdout_arg, stderr_arg, status_arg)
    cmd = 'cat /usr/local/bin/red_amber_green.rb'
    out,_err = assert_exec("docker exec #{cid} sh -c '#{cmd}'")
    rag = eval(out)
    rag.call(stdout_arg, stderr_arg, status_arg).to_s
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # images
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def image_names
    cmd = 'docker images --format "{{.Repository}}"'
    stdout,_ = assert_exec(cmd)
    names = stdout.split("\n")
    names.uniq - ['<none>']
  end

  def container_name
    # Give containers a name with a specific prefix so they
    # can be cleaned up if any fail to be removed/reaped.
    'test_run__runner_processful_' + kata_id
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # dirs
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def make_avatar_dir(avatar_name)
    dir = avatar_dir(avatar_name)
    assert_docker_exec("mkdir -m 755 #{dir}")
  end

  def chown_avatar_dir(avatar_name)
    dir = avatar_dir(avatar_name)
    assert_docker_exec("chown #{avatar_name}:#{group} #{dir}")
  end

  def remove_avatar_dir(avatar_name)
    dir = avatar_dir(avatar_name)
    assert_docker_exec("rm -rf #{dir}")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def make_shared_dir
    # first avatar makes the shared dir
    assert_docker_exec("mkdir -m 775 #{shared_dir} || true")
  end

  def chown_shared_dir
    assert_docker_exec("chown root:#{group} #{shared_dir}")
  end

  def shared_dir
    "#{sandboxes_root_dir}/shared"
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # validation
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  include ValidImageName

  def assert_valid_image_name
    unless valid_image_name?(image_name)
      fail_image_name('invalid')
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def assert_kata_exists
    unless kata_exists?
      fail_kata_id('!exists')
    end
  end

  def refute_kata_exists
    if kata_exists?
      fail_kata_id('exists')
    end
  end

  def assert_valid_kata_id
    unless valid_kata_id?
      fail_kata_id('invalid')
    end
  end

  def valid_kata_id?
    kata_id.class.name == 'String' &&
      kata_id.length == 10 &&
        kata_id.chars.all? { |char| hex?(char) }
  end

  def hex?(char)
    '0123456789ABCDEF'.include?(char)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def assert_valid_avatar_name(avatar_name)
    unless valid_avatar_name?(avatar_name)
      fail_avatar_name('invalid')
    end
  end

  include AllAvatarsNames

  def valid_avatar_name?(avatar_name)
    all_avatars_names.include?(avatar_name)
  end

  def assert_avatar_exists(avatar_name)
    unless avatar_exists?(avatar_name)
      fail_avatar_name('!exists')
    end
  end

  def refute_avatar_exists(avatar_name)
    if avatar_exists?(avatar_name)
      fail_avatar_name('exists')
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def fail_kata_id(message)
    fail bad_argument("kata_id:#{message}")
  end

  def fail_image_name(message)
    fail bad_argument("image_name:#{message}")
  end

  def fail_avatar_name(message)
    fail bad_argument("avatar_name:#{message}")
  end

  def bad_argument(message)
    ArgumentError.new(message)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def assert_docker_exec(cmd)
    assert_exec(docker_cmd(cmd))
  end

  def docker_cmd(cmd)
    "docker exec #{container_name} sh -c '#{cmd}'"
  end

  def assert_exec(cmd)
    shell.assert_exec(cmd)
  end

  def quiet_exec(cmd)
    shell.exec(cmd, LoggerNull.new(self))
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def success
    shell.success
  end

  def space
    ' '
  end

end

# - - - - - - - - - - - - - - - - - - - - - - - -
# The implementation of write_files() is
#   o) Create copies of all (changed) files off /tmp
#   o) Tar pipe the /tmp files into the container
#
# An alternative implementation is
#   o) Tar pipe each file's content directly into the container
#
# If only one file has changed you might image this is quicker
# but testing shows its actually a bit slower.
#
# For interest's sake here's how you tar pipe from a string and
# avoid the intermediate /tmp files:
#
# require 'open3'
# files.each do |name,content|
#   filename = avatar_dir + '/' + name
#   dir = File.dirname(filename)
#   shell_cmd = "mkdir -p #{dir};"
#   shell_cmd += "cat >#{filename} && chown #{uid}:#{gid} #{filename}"
#   cmd = "docker exec --interactive --user=root #{cid} sh -c '#{shell_cmd}'"
#   stdout,stderr,ps = Open3.capture3(cmd, :stdin_data => content)
#   assert ps.success?
# end
# - - - - - - - - - - - - - - - - - - - - - - - -
