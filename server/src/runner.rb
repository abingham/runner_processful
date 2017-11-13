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
    args = [
      '--detach',
      '--init',                            # pid-1 process
      '--interactive',                     # later execs
      '--memory=384m',
      "--name=#{name}",
      '--net=none',                        # security
      '--pids-limit=128',                  # no fork bombs
      '--security-opt=no-new-privileges',  # no escalation
      "--ulimit data=#{4*GB}:#{4*GB}",     # max data segment size
      '--ulimit core=0:0',                 # max core file size
      "--ulimit fsize=#{16*MB}:#{16*MB}",  # max file size
      '--ulimit locks=128:128',            # max number of file locks
      '--ulimit nofile=128:128',           # max number of files
      '--ulimit nproc=128:128',            # max number processes
      "--ulimit stack=#{8*MB}:#{8*MB}",    # max stack size
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

  KB = 1024
  MB = 1024 * KB
  GB = 1024 * MB

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def kata_old
    assert_kata_exists
    assert_exec(remove_container_cmd)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # avatar
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_exists?(avatar_name)
    @avatar_name = avatar_name
    assert_kata_exists
    assert_valid_avatar_name
    _stdout,_stderr,status = quiet_exec(docker_cmd("[ -d #{avatar_dir} ]"))
    status == success
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_new(avatar_name, starting_files)
    @avatar_name = avatar_name
    assert_kata_exists
    refute_avatar_exists
    make_shared_dir
    chown_shared_dir
    make_avatar_dir
    chown_avatar_dir
    write_files(starting_files)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_old(avatar_name)
    @avatar_name = avatar_name
    assert_kata_exists
    assert_avatar_exists
    remove_avatar_dir
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # run
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

=begin
  def run_cyber_dojo_sh(
    avatar_name,
    deleted_files, unchanged_files, changed_files, new_files,
    max_seconds
  )
    unchanged_files = nil # we're stateful
    all_files = [*changed_files, *new_files].to_h
    run(avatar_name, deleted_files.keys, all_files, max_seconds)
  end
=end

  def run(avatar_name, deleted_filenames, changed_files, max_seconds)
    @avatar_name = avatar_name
    assert_kata_exists
    assert_avatar_exists
    delete_files(deleted_filenames)
    write_files(changed_files)
    stdout,stderr,status,colour = run_timeout_cyber_dojo_sh(max_seconds)
    { stdout:truncated(stdout),
      stderr:truncated(stderr),
      status:status,
      colour:colour
    }
  end

  private # = = = = = = = = = = = = = = = = = = =

  include StringTruncater

  def remove_container_cmd
    "docker rm --force --volumes #{container_name}"
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def delete_files(pathed_filenames)
    pathed_filenames.each do |pathed_filename|
      assert_docker_exec("rm #{avatar_dir}/#{pathed_filename}")
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def write_files(files)
    return if files == {}
    Dir.mktmpdir('runner') do |tmp_dir|
      # Save the files onto the host...
      files.each do |pathed_filename, content|
        sub_dir = File.dirname(pathed_filename)
        unless sub_dir == '.'
          src_dir = tmp_dir + '/' + sub_dir
          shell.exec("mkdir -p #{src_dir}")
        end
        src_filename = tmp_dir + '/' + pathed_filename
        disk.write(src_filename, content)
      end
      # ...then tar-pipe them into the container.
      tar_pipe = [
        "chmod 755 #{tmp_dir}",
        "&& cd #{tmp_dir}",
        '&& tar',
              '-zcf', # create a compressed tar file
              '-',    # write it to stdout
              '.',    # tar the current directory
              '|',    # pipe the tarfile...
                  'docker exec', # ...into docker container
                    "--user=#{uid}:#{gid}", # [1]
                    '--interactive',
                    container_name,
                    'sh -c',
                    "'",          # open quote
                    "cd #{avatar_dir}",
                    '&& tar',
                          '--touch', # [2]
                          '-zxf', # extract from a compressed tar file
                          '-',    # which is read from stdin
                          '-C',   # save the extracted files to
                          '.',    # the current directory
                    "'"           # close quote
      ].join(space)
      # The files written into the container need the correct
      # content, ownership, and date-time file-stamps.
      # [1] is for the correct ownership.
      # [2] is for the date-time stamps, in particular the
      #     modification-date (stat %y). The tar --touch option
      #     is not available in a default Alpine container.
      #     So the test-framework container needs to update tar:
      #        $ apk add --update tar
      #     Also, in a default Alpine container the date-time
      #     file-stamps have a granularity of one second. In other
      #     words the microseconds value is always zero.
      #     So the test-framework container also needs to fix this:
      #        $ apk add --update coreutils
      assert_exec(tar_pipe)
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def run_timeout_cyber_dojo_sh(max_seconds)
    # The processes __inside__ the docker container
    # are killed by /usr/local/bin/timeout_cyber_dojo.sh
    # See kata_new() above.
    sh_cmd = [
      '/usr/local/bin/timeout_cyber_dojo.sh',
      image_name,
      kata_id,
      avatar_name,
      max_seconds
    ].join(space)
    run_timeout(docker_cmd(sh_cmd), max_seconds)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  include StringCleaner

  def run_timeout(cmd, max_seconds)
    # This kills the container from the "outside".
    # Originally I also time-limited the cpu-time from the "inside"
    # using the cpu ulimit. However a cpu-ulimit of 10 seconds could
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
        stdout = cleaned(r_stdout.read)
        stderr = cleaned(r_stderr.read)
        colour = red_amber_green(stdout, stderr, status)
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
      status = 137
      stdout = ''
      stderr = ''
      colour = 'timed_out'
      [stdout, stderr, status, colour]
    ensure
      w_stdout.close unless w_stdout.closed?
      w_stderr.close unless w_stderr.closed?
      r_stdout.close
      r_stderr.close
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def red_amber_green(stdout_arg, stderr_arg, status_arg)
    cid = container_name
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

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # image_name
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  attr_reader :image_name

  def assert_valid_image_name
    unless valid_image_name?(image_name)
      fail_image_name('invalid')
    end
  end

  def fail_image_name(message)
    fail bad_argument("image_name:#{message}")
  end

  include ValidImageName

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # container properties
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def container_name
    # Give containers a name with a specific prefix so they
    # can be cleaned up if any fail to be removed/reaped.
    'test_run__runner_processful_' + kata_id
  end

  def group
    'cyber-dojo'
  end

  def gid
    5000
  end

  def uid
    40000 + all_avatars_names.index(avatar_name)
  end

  def avatar_dir
    "#{sandboxes_root_dir}/#{avatar_name}"
  end

  def sandboxes_root_dir
    '/sandboxes'
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # kata
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # kata_id
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  attr_reader :kata_id

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

  def fail_kata_id(message)
    fail bad_argument("kata_id:#{message}")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # avatar
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def assert_avatar_exists
    unless avatar_exists?(avatar_name)
      fail_avatar_name('!exists')
    end
  end

  def refute_avatar_exists
    if avatar_exists?(avatar_name)
      fail_avatar_name('exists')
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # avatar_name
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  attr_reader :avatar_name

  def assert_valid_avatar_name
    unless valid_avatar_name?
      fail_avatar_name('invalid')
    end
  end

  def valid_avatar_name?
    all_avatars_names.include?(avatar_name)
  end

  def fail_avatar_name(message)
    fail bad_argument("avatar_name:#{message}")
  end

  include AllAvatarsNames

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # dirs
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def make_avatar_dir
    assert_docker_exec("mkdir -m 755 #{avatar_dir}")
  end

  def chown_avatar_dir
    assert_docker_exec("chown #{avatar_name}:#{group} #{avatar_dir}")
  end

  def remove_avatar_dir
    assert_docker_exec("rm -rf #{avatar_dir}")
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

  attr_reader :disk, :shell # externals

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
#   shell_cmd += "cat > #{filename} && chown #{uid}:#{gid} #{filename}"
#   cmd = "docker exec --interactive --user=root #{cid} sh -c '#{shell_cmd}'"
#   stdout,stderr,ps = Open3.capture3(cmd, :stdin_data => content)
#   assert ps.success?
# end
# - - - - - - - - - - - - - - - - - - - - - - - -
