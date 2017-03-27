require_relative 'test_base'

class TimeoutTest < TestBase

  def self.hex_prefix; '45B57'; end
  def hex_setup; kata_setup; end
  def hex_teardown; kata_teardown; end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'B2B', %w( [gcc,assert]
  when run(test-code)
    does not complete in max_seconds
      and
    does not produce output
  then
    the output is empty
      and
    the status is timed_out
  ) do
    gcc_assert_files['hiker.c'] = [
      '#include "hiker.h"',
      'int answer(void)',
      '{',
      '    for(;;); ',
      '    return 6 * 7;',
      '}'
    ].join("\n")
    named_args = {
      changed_files:gcc_assert_files,
      max_seconds:2
    }
    stdout,stderr = assert_run_times_out(named_args)
    assert_equal '', stdout
    assert_equal '', stderr
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '4D7', %w( [gcc,assert]
  when run(test-code)
    does not complete in max_seconds
      and
    does produce output
  then
    the output is nonetheless empty
      and
    the status is timed_out
  ) do
    gcc_assert_files['hiker.c'] = [
      '#include "hiker.h"',
      '#include <stdio.h>',
      'int answer(void)',
      '{',
      '    for(;;)',
      '        puts("Hello");',
      '    return 6 * 7;',
      '}'
    ].join("\n")
    named_args = {
      changed_files:gcc_assert_files,
      max_seconds:2
    }
    stdout,stderr = assert_run_times_out(named_args)
    assert_equal '', stdout
    assert_equal '', stderr
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def gcc_assert_files
    files('gcc_assert')
  end

end


