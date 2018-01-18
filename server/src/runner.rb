require_relative 'all_avatars_names'
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
#   o) avatars can share processes.
#   o) fastest run(). In a rough sample
#      ~30% faster than runner_stateful
# - - - - - - - - - - - - - - - - - - - - - - - - - - - -

class Runner # processful

  def initialize(external, image_name, kata_id)
    @external = external
    @image_name = image_name
    @kata_id = kata_id
    assert_valid_image_name
    assert_valid_kata_id
  end

  # - - - - - - - - - - - - - - - - - -
  # image
  # - - - - - - - - - - - - - - - - - -

  def image_pulled?
    cmd = 'docker images --format "{{.Repository}}"'
    shell.assert(cmd).split("\n").include?(image_name)
  end

  def image_pull
    # [1] The contents of stderr vary depending on Docker version
    docker_pull = "docker pull #{image_name}"
    _stdout,stderr,status = shell.exec(docker_pull)
    if status == shell.success
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

  def kata_new
    refute_kata_exists
    create_container
  end

  def kata_old
    assert_kata_exists
    remove_container
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # avatar
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_new(avatar_name, starting_files)
    @avatar_name = avatar_name
    assert_kata_exists
    refute_avatar_exists
    make_and_chown_dirs
    write_files(starting_files)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_old(avatar_name)
    @avatar_name = avatar_name
    assert_kata_exists
    assert_avatar_exists
    remove_sandbox_dir
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # run
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def run_cyber_dojo_sh(
    avatar_name,
    new_files, deleted_files, unchanged_files, changed_files,
    max_seconds
  )
    @avatar_name = avatar_name
    assert_kata_exists
    assert_avatar_exists
    unchanged_files = nil # we're stateful
    all_files = [*changed_files, *new_files].to_h
    delete_files(deleted_files.keys)
    write_files(all_files)
    run_timeout_cyber_dojo_sh(max_seconds)
    colour = @timed_out ? 'timed_out' : red_amber_green
    { stdout:@stdout,
      stderr:@stderr,
      status:@status,
      colour:colour
    }
  end

  private # = = = = = = = = = = = = = = = = = = =

  def delete_files(filenames)
    filenames.each do |filename|
      shell.assert(docker_exec("rm #{sandbox_dir}/#{filename}"))
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def write_files(files)
    unless files == {}
      Dir.mktmpdir do |tmp_dir|
        save_to(files, tmp_dir)
        shell.assert(tar_pipe_from(tmp_dir))
      end
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def save_to(files, tmp_dir)
    files.each do |pathed_filename, content|
      sub_dir = File.dirname(pathed_filename)
      unless sub_dir == '.'
        src_dir = tmp_dir + '/' + sub_dir
        shell.assert("mkdir -p #{src_dir}")
      end
      src_filename = tmp_dir + '/' + pathed_filename
      disk.write(src_filename, content)
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def tar_pipe_from(tmp_dir)
    # [1] is for file-stamp date-time granularity
    # This relates to the modification-date (stat %y).
    # The tar --touch option is not available in a default Alpine
    # container. To add it:
    #    $ apk add --update tar
    # Also, in a default Alpine container the date-time
    # file-stamps have a granularity of one second. In other
    # words the microseconds value is always zero.
    # To add microsecond granularity:
    #    $ apk add --update coreutils
    # See the file builder/image_builder.rb on
    # https://github.com/cyber-dojo-languages/image_builder/blob/master/
    # In particular the methods
    #    o) update_tar_command
    #    o) install_coreutils_command
    <<~SHELL.strip
      chmod 755 #{tmp_dir} &&                                          \
      cd #{tmp_dir} &&                                                 \
      tar                                                              \
        -zcf                           `# create tar file`             \
        -                              `# write it to stdout`          \
        .                              `# tar the current directory`   \
        |                              `# pipe the tarfile...`         \
          docker exec                  `# ...into docker container`    \
            --user=#{uid}:#{gid}                                       \
            --interactive                                              \
            #{container_name}                                          \
            sh -c                                                      \
              '                        `# open quote`                  \
              cd #{sandbox_dir} &&                                     \
              tar                                                      \
                --touch                `# [1]`                         \
                -zxf                   `# extract tar file`            \
                -                      `# which is read from stdin`    \
                -C                     `# save the extracted files to` \
                .                      `# the current directory`       \
              '                        `# close quote`
    SHELL
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
    run_timeout(docker_exec(sh_cmd), max_seconds)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def run_timeout(cmd, max_seconds)
    # The [docker exec] running on the _host_ is
    # killed by Process.kill. This does _not_ kill
    # the cyber-dojo.sh running _inside_ the docker
    # container. The container is killed in the ensure
    # block of in_container()
    # See https://github.com/docker/docker/issues/9098
    r_stdout, w_stdout = IO.pipe
    r_stderr, w_stderr = IO.pipe
    pid = Process.spawn(cmd, {
      pgroup:true,     # become process leader
         out:w_stdout, # redirection
         err:w_stderr  # redirection
    })
    begin
      Timeout::timeout(max_seconds) do
        _, ps = Process.waitpid2(pid)
        @status = ps.exitstatus
        @timed_out = false
      end
    rescue Timeout::Error
      Process.kill(-9, pid) # -ve means kill process-group
      Process.detach(pid)   # prevent zombie-child
      @status = 137         # don't wait for status from detach
      @timed_out = true
    ensure
      w_stdout.close unless w_stdout.closed?
      w_stderr.close unless w_stderr.closed?
      @stdout = truncated(cleaned(r_stdout.read))
      @stderr = truncated(cleaned(r_stderr.read))
      r_stdout.close
      r_stderr.close
    end
  end

  include StringCleaner
  include StringTruncater

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def red_amber_green
    # @stdout and @stderr have been truncated and cleaned.
    begin
      # In a crippled container (eg fork-bomb)
      # the [docker exec] will mostly likely raise.
      cat_cmd = 'cat /usr/local/bin/red_amber_green.rb'
      rag_lambda = shell.assert(docker_exec(cat_cmd))
      rag = eval(rag_lambda)
      colour = rag.call(@stdout, @stderr, @status).to_s
      # :nocov:
      unless ['red','amber','green'].include? colour
        colour = 'amber'
      end
      colour
    rescue
      'amber'
      # :nocov:
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # image/container
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  attr_reader :image_name

  def assert_valid_image_name
    unless valid_image_name?(image_name)
      fail_image_name('invalid')
    end
  end

  def fail_image_name(message)
    raise bad_argument("image_name:#{message}")
  end

  include ValidImageName

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def container_exists?
    cmd = [
      'docker ps',
        '--quiet',
        '--all',
        '--filter status=running',
        "--filter name=#{container_name}"
    ].join(space)
    shell.assert(cmd).strip != ''
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def create_container
    args = [
      '--detach',                 # for later exec
      '--init',                   # pid-1 process
      limits,
      "--name=#{container_name}", # for easy clean up
      '--user=root'               # chown permission
    ].join(space)

    init_filename = '/usr/local/bin/cyber-dojo-init.sh'
    docker_run = [
      'docker run',
      args,
      image_name,
      "sh -c '([ -f #{init_filename} ] && #{init_filename}); sleep 3h'"
    ].join(space)

    shell.assert(docker_run)

    docker_cp = [
      'docker cp',
      "#{my_dir}/timeout_cyber_dojo.sh",
      "#{container_name}:/usr/local/bin"
    ].join(space)

    shell.assert(docker_cp)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def limits
    # There is no cpu-ulimit. This is because a cpu-ulimit of 10
    # seconds could kill a container after only 5 seconds...
    # The cpu-ulimit assumes one core. The host system running the
    # docker container can have multiple cores or use hyperthreading.
    # So a piece of code running on 2 cores, both 100% utilized could
    # be killed after 5 seconds.
    [
      ulimit('data',   4*GB),  # data segment size
      ulimit('core',   0),     # core file size
      ulimit('fsize',  16*MB), # file size
      ulimit('locks',  128),   # number of file locks
      ulimit('nofile', 256),   # number of files
      ulimit('nproc',  128),   # number of processes
      ulimit('stack',  8*MB),  # stack size
      '--memory=512m',         # ram
      '--net=none',                      # no network
      '--pids-limit=128',                # no fork bombs
      '--security-opt=no-new-privileges' # no escalation
    ].join(space)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def ulimit(name, limit)
    "--ulimit #{name}=#{limit}"
  end

  KB = 1024
  MB = 1024 * KB
  GB = 1024 * MB

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def remove_container
    shell.assert("docker rm --force #{container_name}")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def container_name
    # Give containers a name with a specific prefix so they
    # can be cleaned up if any fail to be removed/reaped.
    'test_run__runner_processful_' + kata_id
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # kata
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  attr_reader :kata_id

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

  def kata_exists?
    container_exists?
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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
    raise bad_argument("kata_id:#{message}")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # avatar
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  attr_reader :avatar_name

  def assert_avatar_exists
    assert_valid_avatar_name
    unless avatar_exists?
      fail_avatar_name('!exists')
    end
  end

  def refute_avatar_exists
    assert_valid_avatar_name
    if avatar_exists?
      fail_avatar_name('exists')
    end
  end

  def avatar_exists?
    cmd = "[ -d #{sandbox_dir} ] || printf 'not_found'"
    stdout = shell.assert(docker_exec(cmd))
    stdout != 'not_found'
  end

  def assert_valid_avatar_name
    unless valid_avatar_name?
      fail_avatar_name('invalid')
    end
  end

  def valid_avatar_name?
    all_avatars_names.include?(avatar_name)
  end

  include AllAvatarsNames

  def fail_avatar_name(message)
    raise bad_argument("avatar_name:#{message}")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def group
    'cyber-dojo'
  end

  def gid
    5000
  end

  def uid
    40000 + all_avatars_names.index(avatar_name)
  end

  def sandbox_dir
    "#{sandboxes_root_dir}/#{avatar_name}"
  end

  def sandboxes_root_dir
    '/sandboxes'
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # dirs
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def make_and_chown_dirs
    # first avatar makes the shared dir
    shared_dir = "#{sandboxes_root_dir}/shared"
    shell.assert(docker_exec("mkdir -p -m 775 #{shared_dir}"))
    shell.assert(docker_exec("chown root:#{group} #{shared_dir}"))

    shell.assert(docker_exec("mkdir -m 755 #{sandbox_dir}"))
    shell.assert(docker_exec("chown #{uid}:#{gid} #{sandbox_dir}"))
  end

  def remove_sandbox_dir
    shell.assert(docker_exec("rm -rf #{sandbox_dir}"))
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def bad_argument(message)
    ArgumentError.new(message)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -

  def docker_exec(cmd)
    # This is _not_ the main docker-exec
    # for run_cyber_dojo_sh
    "docker exec --user=root #{container_name} sh -c '#{cmd}'"
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def space
    ' '
  end

  def my_dir
    File.expand_path(File.dirname(__FILE__))
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def disk
    @external.disk
  end

  def shell
    @external.shell
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
# For interests sake here's how you tar pipe from a string and
# avoid the intermediate /tmp files:
#
# require 'open3'
# files.each do |name,content|
#   filename = sandbox_dir + '/' + name
#   dir = File.dirname(filename)
#   shell_cmd = "mkdir -p #{dir};"
#   shell_cmd += "cat > #{filename} && chown #{uid}:#{gid} #{filename}"
#   cmd = [
#     'docker exec',
#     '--interactive',
#     '--user=root',
#     container_name,
#     "sh -c '#{shell_cmd}'"
#   ].join(space)
#   stdout,stderr,ps = Open3.capture3(cmd, :stdin_data => content)
#   assert ps.success?
# end
# - - - - - - - - - - - - - - - - - - - - - - - -
