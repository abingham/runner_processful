require_relative 'test_base'
require_relative 'os_helper'

class ForkBombTest < TestBase

  include OsHelper

  def self.hex_prefix
    '35758'
  end

  def hex_setup
    kata_setup
  end

  def hex_teardown
    kata_teardown
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -
  # fork-bombs from the source
  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'CD5',
  %w( [Alpine] fork-bomb does not run indefinitely ) do
    content = '#include "hiker.h"' + "\n" + fork_bomb_definition
    as('lion') {
      run4({ avatar_name: 'lion',
           changed_files: {'hiker.c' => content },
             max_seconds: 5
      })
    }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'CD6',
  %w( [Ubuntu] fork-bomb does not run indefinitely ) do
    content = '#include "hiker.hpp"' + "\n" + fork_bomb_definition
    as('lion') {
      run4({ avatar_name: 'lion',
           changed_files: { 'hiker.cpp' => content },
             max_seconds: 5
      })
    }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def fork_bomb_definition
    [ '#include <stdio.h>',
      '#include <unistd.h>',
      '',
      'int answer(void)',
      '{',
      '    for(;;)',
      '    {',
      '        int pid = fork();',
      '        fprintf(stdout, "fork() => %d\n", pid);',
      '        fflush(stdout);',
      '        if (pid == -1)',
      '            break;',
      '    }',
      '    return 6 * 7;',
      '}'
    ].join("\n")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -
  # fork-bombs from the shell
  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '4DE',
  %w( [Alpine] fork-bomb does not run indefinitely ) do
    @log = LoggerSpy.new(nil)
    as('lion') {
      begin
        run_shell_fork_bomb
      rescue ArgumentError
      end
    }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '4DF',
  %w( [Ubuntu] fork-bomb does not run indefinitely ) do
    @log = LoggerSpy.new(nil)
    as('lion') {
      begin
        run_shell_fork_bomb
      rescue ArgumentError
      end
    }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def run_shell_fork_bomb
    shell_fork_bomb = 'bomb() { bomb | bomb & }; bomb'
    run4({
        avatar_name: 'lion',
      changed_files: {'cyber-dojo.sh' => shell_fork_bomb },
        max_seconds: 5
    })
  end

end
